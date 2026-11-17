// TJ Flutter Providers — JS polyfill for QuickJS / JavaScriptCore (flutter_js)
// Adapted from NuvioMobile JsBindings.kt polyfill behavior (GPL-3.0, NuvioMedia)
// but rewritten for flutter_js: only TWO async Dart bridges are used:
//   sendMessage('__native_fetch', JSON)  -> Dart http (OkHttp-like)
//   sendMessage('__plugin_sleep', JSON)  -> Dart Future.delayed (timers)
//   sendMessage('__crypto', JSON)        -> Dart crypto (AES-CBC/GCM, digest, HMAC, PBKDF2, random)
// Envelope: { __tjId, __tjData }. Dart answers by evaluating
//   __TJ_DELIVER(id, true, "<json string>")   (or false + error message).
// Everything else (atob/btoa, TextEncoder/Decoder, URL, AbortController) is pure JS.
// CryptoJS (assets/js/crypto-js.min.js) is loaded BEFORE this file for any
// plugin that uses global CryptoJS directly. This file defines crypto.subtle
// on top of the Dart bridge so host.js decryptAES works for CBC and GCM.
//
// Load order in Dart (JsRuntime):
//   1. crypto-js.min.js
//   2. this polyfill.js
//   3. provider code (providers/<id>.js, CommonJS: module.exports.getStreams)
//   4. call.js  (calls getStreams and returns JSON string via Promise)

(function () {
  'use strict';

  // ── Globals ──────────────────────────────────────────────────────────────
  if (typeof globalThis.global === 'undefined') globalThis.global = globalThis;
  if (typeof globalThis.window === 'undefined') globalThis.window = globalThis;
  if (typeof globalThis.self === 'undefined') globalThis.self = globalThis;
  if (typeof globalThis.SCRAPER_ID === 'undefined') globalThis.SCRAPER_ID = '';
  if (typeof globalThis.SCRAPER_SETTINGS === 'undefined') globalThis.SCRAPER_SETTINGS = {};
  if (typeof globalThis.TMDB_API_KEY === 'undefined') globalThis.TMDB_API_KEY = '';

  // console: flutter_js may already provide it; ensure all levels exist
  if (typeof globalThis.console === 'undefined') {
    globalThis.console = { log: function () {}, error: function () {}, warn: function () {}, info: function () {}, debug: function () {} };
  } else {
    ['log', 'error', 'warn', 'info', 'debug'].forEach(function (k) {
      if (typeof globalThis.console[k] !== 'function') globalThis.console[k] = function () {};
    });
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  function __bytesToHex(bytes) {
    var out = '';
    for (var i = 0; i < bytes.length; i++) {
      var h = bytes[i].toString(16);
      out += (h.length === 1 ? '0' : '') + h;
    }
    return out;
  }
  function __hexToBytes(hex) {
    var out = new Uint8Array(Math.floor(String(hex || '').length / 2));
    for (var i = 0; i < out.length; i++) out[i] = parseInt(String(hex).substr(i * 2, 2), 16) || 0;
    return out;
  }
  function __toUint8Array(data) {
    if (data == null) return new Uint8Array(0);
    if (data instanceof Uint8Array) return data;
    if (typeof ArrayBuffer !== 'undefined' && data instanceof ArrayBuffer) return new Uint8Array(data);
    if (typeof ArrayBuffer !== 'undefined' && ArrayBuffer.isView && ArrayBuffer.isView(data)) {
      return new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
    }
    if (Array.isArray(data)) return new Uint8Array(data);
    if (typeof data === 'string') {
      var out = new Uint8Array(data.length);
      for (var i = 0; i < data.length; i++) out[i] = data.charCodeAt(i) & 255;
      return out;
    }
    return new Uint8Array(0);
  }
  function __bytesToArrayBuffer(bytes) {
    var copy = new Uint8Array(bytes.length);
    copy.set(bytes);
    return copy.buffer;
  }
  function __concatBytes() {
    var total = 0, i;
    for (i = 0; i < arguments.length; i++) total += arguments[i].length;
    var out = new Uint8Array(total), off = 0;
    for (i = 0; i < arguments.length; i++) { out.set(arguments[i], off); off += arguments[i].length; }
    return out;
  }


  // ── Dart bridge (id-based request/response) ─────────────────────────────
  // flutter_js's sendMessage return value is not reliable across versions, so
  // we never depend on it. Instead:
  //   1. JS assigns an id, stores the promise resolvers, and calls
  //      sendMessage(channel, JSON {__tjId, __tjData}).
  //   2. Dart handles the request asynchronously, then calls
  //      __TJ_DELIVER(id, ok, payloadString) via runtime.evaluate().
  // If sendMessage happens to return a Promise (some builds), we also accept
  // that as the answer — whichever arrives first wins.
  var __TJ_NEXT_ID = 0;
  var __TJ_PENDING = Object.create(null);
  function __TJ_safe_string(value) {
    if (typeof value === 'string') return value;
    try { return JSON.stringify(value); } catch (e) { return String(value); }
  }
  function __tj_bridge(channel, payload) {
    var id = ++__TJ_NEXT_ID;
    return new Promise(function (resolve, reject) {
      __TJ_PENDING[id] = { resolve: resolve, reject: reject };
      try {
        if (typeof sendMessage === 'function') {
          var maybe = sendMessage(channel, JSON.stringify({ __tjId: id, __tjData: payload || {} }));
          if (maybe && typeof maybe.then === 'function') {
            maybe.then(function (v) {
              if (__TJ_PENDING[id]) __TJ_DELIVER(id, true, __TJ_safe_string(v));
            }, function (e) {
              if (__TJ_PENDING[id]) __TJ_DELIVER(id, false, String((e && e.message) || e));
            });
          }
        } else if (typeof __tj_native_bridge === 'function') {
          __tj_native_bridge(channel, JSON.stringify({ __tjId: id, __tjData: payload || {} }));
        } else {
          delete __TJ_PENDING[id];
          reject(new Error('TJ bridge unavailable for channel: ' + channel));
        }
      } catch (e) {
        delete __TJ_PENDING[id];
        reject(e);
      }
    });
  }
  globalThis.__tj_bridge = __tj_bridge;
  globalThis.__TJ_DELIVER = function (id, ok, payloadString) {
    var entry = __TJ_PENDING[Number(id)];
    if (!entry) return false;
    delete __TJ_PENDING[Number(id)];
    if (ok) entry.resolve(payloadString);
    else entry.reject(new Error(String(payloadString || 'bridge error')));
    return true;
  };

  // ── Timers (via Dart __plugin_sleep) ────────────────────────────────────
  // QuickJS has no event loop. flutter_js provides executePendingJob/handlePromise
  // to pump promises, so timers backed by Dart sleep work.
  var __plugin_timer_id = 0;
  var __plugin_timers = Object.create(null);
  function __plugin_delay_value(value, interval) {
    var duration = Number(value);
    if (!isFinite(duration) || duration < 0) duration = 0;
    duration = Math.min(Math.floor(duration), 60000);
    return interval && duration < 1 ? 1 : duration;
  }
  function __plugin_report_timer_error(error) {
    try { console.error('[TJ] Timer callback failed:', error); } catch (e) {}
  }
  async function __plugin_sleep(ms) {
    var duration = Number(ms) || 0;
    if (typeof sendMessage === 'function' || typeof __tj_native_bridge === 'function') {
      return await __tj_bridge('__plugin_sleep', { ms: duration });
    }
    // Fallback for Node / browser (unit tests without a host)
    return new Promise(function (resolve) { setTimeout(resolve, duration); });
  }
  if (typeof globalThis.setTimeout === 'undefined') {
    globalThis.setTimeout = function (callback, delay) {
      if (typeof callback !== 'function') throw new TypeError('Timer callback must be a function');
      var id = ++__plugin_timer_id;
      var args = Array.prototype.slice.call(arguments, 2);
      __plugin_timers[id] = true;
      __plugin_sleep(__plugin_delay_value(delay, false)).then(function () {
        if (!__plugin_timers[id]) return;
        delete __plugin_timers[id];
        try { callback.apply(globalThis, args); } catch (error) { __plugin_report_timer_error(error); }
      }, function (error) { delete __plugin_timers[id]; __plugin_report_timer_error(error); });
      return id;
    };
  }
  if (typeof globalThis.clearTimeout === 'undefined') {
    globalThis.clearTimeout = function (id) { delete __plugin_timers[id]; };
  }
  if (typeof globalThis.setInterval === 'undefined') {
    globalThis.setInterval = function (callback, delay) {
      if (typeof callback !== 'function') throw new TypeError('Timer callback must be a function');
      var id = ++__plugin_timer_id;
      var duration = __plugin_delay_value(delay, true);
      var args = Array.prototype.slice.call(arguments, 2);
      __plugin_timers[id] = true;
      function tick() {
        __plugin_sleep(duration).then(function () {
          if (!__plugin_timers[id]) return;
          try { callback.apply(globalThis, args); } catch (error) { __plugin_report_timer_error(error); }
          if (__plugin_timers[id]) tick();
        }, function (error) { delete __plugin_timers[id]; __plugin_report_timer_error(error); });
      }
      tick();
      return id;
    };
  }
  if (typeof globalThis.clearInterval === 'undefined') {
    globalThis.clearInterval = function (id) { delete __plugin_timers[id]; };
  }

  // ── Fetch (via Dart __native_fetch) ─────────────────────────────────────
  function __normalize_fetch_headers(headers) {
    var out = {};
    if (!headers) return out;
    if (typeof headers.forEach === 'function') {
      headers.forEach(function (value, key) { out[key] = String(value); });
      return out;
    }
    if (Array.isArray(headers)) {
      headers.forEach(function (pair) { if (pair && pair.length >= 2) out[pair[0]] = String(pair[1]); });
      return out;
    }
    Object.keys(headers).forEach(function (key) { out[key] = String(headers[key]); });
    return out;
  }
  function __fetch_bytes_to_base64(bytes) {
    var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    var out = '';
    for (var i = 0; i < bytes.length; i += 3) {
      var a = bytes[i];
      var hasB = i + 1 < bytes.length;
      var hasC = i + 2 < bytes.length;
      var b = hasB ? bytes[i + 1] : 0;
      var c = hasC ? bytes[i + 2] : 0;
      out += chars.charAt(a >> 2);
      out += chars.charAt(((a & 3) << 4) | (b >> 4));
      out += hasB ? chars.charAt(((b & 15) << 2) | (c >> 6)) : '=';
      out += hasC ? chars.charAt(c & 63) : '=';
    }
    return out;
  }
  function __fetch_base64_to_bytes(value) {
    var binary = atob(value || '');
    var bytes = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }
  function __normalize_fetch_body(body) {
    if (body === undefined || body === null) return { kind: 'none', value: '' };
    if (typeof body === 'string') return { kind: 'text', value: body };
    var bytes = null;
    if (typeof ArrayBuffer !== 'undefined' && body instanceof ArrayBuffer) {
      bytes = new Uint8Array(body);
    } else if (typeof ArrayBuffer !== 'undefined' && typeof ArrayBuffer.isView === 'function' && ArrayBuffer.isView(body)) {
      bytes = new Uint8Array(body.buffer, body.byteOffset, body.byteLength);
    }
    if (bytes !== null) return { kind: 'base64', value: __fetch_bytes_to_base64(bytes) };
    return { kind: 'text', value: String(body) };
  }
  async function __native_fetch(url, method, headersJson, bodyKind, body, followRedirects) {
    var headersObj = {};
    try { headersObj = JSON.parse(headersJson || '{}') || {}; } catch (e) { headersObj = {}; }
    var result = await __tj_bridge('__native_fetch', {
      url: String(url), method: String(method || 'GET'),
      headers: headersObj,
      bodyKind: String(bodyKind || 'none'), body: String(body || ''),
      followRedirects: followRedirects !== false
    });
    if (typeof result === 'string') return result;
    return __TJ_safe_string(result);
  }
  // Only define fetch if not already provided by flutter_js built-in fetch.
  // flutter_js enableFetch() provides a native fetch; our bridge gives us
  // control over UA/timeout/redirects matching Nuvio, so we prefer ours
  // when sendMessage exists. If sendMessage is missing, keep native fetch.
  if (typeof sendMessage === 'function' || typeof __tj_native_bridge === 'function') {
    globalThis.fetch = async function (url, options) {
      options = options || {};
      var method = (options.method || 'GET').toUpperCase();
      var headers = __normalize_fetch_headers(options.headers);
      var body = __normalize_fetch_body(options.body);
      var followRedirects = options.redirect !== 'manual';
      var result = await __native_fetch(url, method, JSON.stringify(headers), body.kind, body.value, followRedirects);
      var parsed = JSON.parse(result);
      var responseBytes = __fetch_base64_to_bytes(parsed.bodyBase64 || '');
      return {
        ok: !!parsed.ok,
        status: parsed.status || 0,
        statusText: parsed.statusText || '',
        url: parsed.url || String(url),
        headers: {
          get: function (name) { return (parsed.headers || {})[String(name).toLowerCase()] || null; },
          forEach: function (cb) { Object.keys(parsed.headers || {}).forEach(function (k) { cb((parsed.headers || {})[k], k); }); }
        },
        arrayBuffer: function () {
          var copy = new Uint8Array(responseBytes.length);
          copy.set(responseBytes);
          return Promise.resolve(copy.buffer);
        },
        text: function () { return Promise.resolve(parsed.body || ''); },
        json: function () {
          try {
            if (!parsed.body) return Promise.resolve(null);
            return Promise.resolve(JSON.parse(parsed.body));
          } catch (e) { return Promise.resolve(null); }
        }
      };
    };
  }

  // ── AbortController / AbortSignal ───────────────────────────────────────
  if (typeof AbortSignal === 'undefined') {
    var AbortSignal = function () { this.aborted = false; this.reason = undefined; this._listeners = []; };
    AbortSignal.prototype.addEventListener = function (type, listener) {
      if (type !== 'abort' || typeof listener !== 'function') return;
      this._listeners.push(listener);
    };
    AbortSignal.prototype.removeEventListener = function (type, listener) {
      if (type !== 'abort') return;
      this._listeners = this._listeners.filter(function (l) { return l !== listener; });
    };
    AbortSignal.prototype.dispatchEvent = function (event) {
      if (!event || event.type !== 'abort') return true;
      for (var i = 0; i < this._listeners.length; i++) {
        try { this._listeners[i].call(this, event); } catch (e) {}
      }
      return true;
    };
    globalThis.AbortSignal = AbortSignal;
  }
  if (typeof AbortController === 'undefined') {
    var AbortController = function () { this.signal = new AbortSignal(); };
    AbortController.prototype.abort = function (reason) {
      if (this.signal.aborted) return;
      this.signal.aborted = true;
      this.signal.reason = reason;
      this.signal.dispatchEvent({ type: 'abort' });
    };
    globalThis.AbortController = AbortController;
  }

  // ── atob / btoa ──────────────────────────────────────────────────────────
  if (typeof atob === 'undefined') {
    globalThis.atob = function (input) {
      var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
      var str = String(input).replace(/=+$/, '');
      if (str.length % 4 === 1) throw new Error('InvalidCharacterError');
      var output = '';
      var bc = 0, bs, buffer, idx = 0;
      while ((buffer = str.charAt(idx++))) {
        buffer = chars.indexOf(buffer);
        if (buffer === -1) continue;
        bs = bc % 4 ? bs * 64 + buffer : buffer;
        if (bc++ % 4) output += String.fromCharCode(255 & (bs >> ((-2 * bc) & 6)));
      }
      return output;
    };
  }
  if (typeof btoa === 'undefined') {
    globalThis.btoa = function (input) {
      var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
      var str = String(input);
      var output = '';
      for (var block, charCode, idx = 0, map = chars;
           str.charAt(idx | 0) || (map = '=', idx % 1);
           output += map.charAt(63 & (block >> (8 - (idx % 1) * 8)))) {
        charCode = str.charCodeAt(idx += 3 / 4);
        if (charCode > 0xFF) throw new Error('InvalidCharacterError');
        block = (block << 8) | charCode;
      }
      return output;
    };
  }

  // ── TextEncoder / TextDecoder ───────────────────────────────────────────
  if (typeof TextEncoder === 'undefined') {
    globalThis.TextEncoder = function () {};
    globalThis.TextEncoder.prototype.encode = function (str) {
      str = String(str || '');
      var bytes = [];
      for (var i = 0; i < str.length; i++) {
        var code = str.charCodeAt(i);
        if (code < 0x80) bytes.push(code);
        else if (code < 0x800) { bytes.push(0xC0 | (code >> 6), 0x80 | (code & 0x3F)); }
        else if (code >= 0xD800 && code <= 0xDBFF && i + 1 < str.length) {
          var next = str.charCodeAt(i + 1);
          if (next >= 0xDC00 && next <= 0xDFFF) {
            var cp = 0x10000 + ((code - 0xD800) << 10) + (next - 0xDC00);
            bytes.push(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F));
            i++;
          } else bytes.push(0xEF, 0xBF, 0xBD);
        } else if (code >= 0xDC00 && code <= 0xDFFF) bytes.push(0xEF, 0xBF, 0xBD);
        else bytes.push(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F));
      }
      return new Uint8Array(bytes);
    };
  }
  if (typeof TextDecoder === 'undefined') {
    globalThis.TextDecoder = function () {};
    globalThis.TextDecoder.prototype.decode = function (bytes) {
      bytes = __toUint8Array(bytes);
      var str = '';
      for (var i = 0; i < bytes.length;) {
        var b = bytes[i];
        if (b < 0x80) { str += String.fromCharCode(b); i++; }
        else if ((b & 0xE0) === 0xC0 && i + 1 < bytes.length) {
          str += String.fromCharCode(((b & 0x1F) << 6) | (bytes[i + 1] & 0x3F)); i += 2;
        } else if ((b & 0xF0) === 0xE0 && i + 2 < bytes.length) {
          str += String.fromCharCode(((b & 0x0F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (bytes[i + 2] & 0x3F)); i += 3;
        } else if ((b & 0xF8) === 0xF0 && i + 3 < bytes.length) {
          var cp = ((b & 0x07) << 18) | ((bytes[i + 1] & 0x3F) << 12) | ((bytes[i + 2] & 0x3F) << 6) | (bytes[i + 3] & 0x3F);
          cp -= 0x10000;
          str += String.fromCharCode(0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF)); i += 4;
        } else { str += '\uFFFD'; i++; }
      }
      return str;
    };
  }

  // ── URL / URLSearchParams (pure JS, no native bridge) ───────────────────
  function __parseUrlPure(u) {
    var m = String(u || '').match(/^(https?:\/\/)?([^\/\?#:]+)(?::(\d+))?(\/[^\?#]*)?(\?[^\#]*)?(#.*)?$/i);
    if (!m) return { protocol: '', host: '', hostname: '', port: '', pathname: '/', search: '', hash: '' };
    var protocol = m[1] ? m[1].replace(/:$/, '') + ':' : '';
    var host = m[2] + (m[3] ? ':' + m[3] : '');
    return {
      protocol: protocol, host: host, hostname: m[2] || '', port: m[3] || '',
      pathname: m[4] || '/', search: m[5] || '', hash: m[6] || ''
    };
  }
  if (typeof URL === 'undefined') {
    var URL = function (urlString, base) {
      var fullUrl = String(urlString);
      if (base && !/^https?:\/\//i.test(fullUrl)) {
        var b = typeof base === 'string' ? base : base.href;
        if (fullUrl.charAt(0) === '/') {
          var mm = b.match(/^(https?:\/\/[^\/]+)/);
          fullUrl = mm ? mm[1] + fullUrl : fullUrl;
        } else {
          fullUrl = b.replace(/\/[^\/]*$/, '/') + fullUrl;
        }
      }
      var data = __parseUrlPure(fullUrl);
      this.href = fullUrl;
      this.protocol = data.protocol;
      this.host = data.host;
      this.hostname = data.hostname;
      this.port = data.port;
      this.pathname = data.pathname;
      this.search = data.search;
      this.hash = data.hash;
      this.origin = data.protocol + '//' + data.host;
      this.searchParams = new URLSearchParams(data.search || '');
    };
    URL.prototype.toString = function () { return this.href; };
    globalThis.URL = URL;
  }
  if (typeof URLSearchParams === 'undefined') {
    var URLSearchParams = function (init) {
      this._params = {};
      var self = this;
      if (init && typeof init === 'object' && !Array.isArray(init)) {
        Object.keys(init).forEach(function (key) { self._params[key] = String(init[key]); });
      } else if (typeof init === 'string') {
        init.replace(/^\?/, '').split('&').forEach(function (pair) {
          if (!pair) return;
          var parts = pair.split('=');
          try { self._params[decodeURIComponent(parts[0])] = decodeURIComponent(parts[1] || ''); } catch (e) { self._params[parts[0]] = parts[1] || ''; }
        });
      }
    };
    URLSearchParams.prototype.get = function (k) { return Object.prototype.hasOwnProperty.call(this._params, k) ? this._params[k] : null; };
    URLSearchParams.prototype.set = function (k, v) { this._params[k] = String(v); };
    URLSearchParams.prototype.toString = function () {
      var self = this;
      return Object.keys(self._params).map(function (k) { return encodeURIComponent(k) + '=' + encodeURIComponent(self._params[k]); }).join('&');
    };
    globalThis.URLSearchParams = URLSearchParams;
  }

  // Keep a reference so Dart can re-assert our fetch after any later
  // polyfill (e.g. flutter_js enableFetch) overwrites the global.
  globalThis.__TJ_FETCH = globalThis.fetch;

  // ── Crypto (via Dart __crypto bridge, async) ────────────────────────────
  // host.js makeCrypto() uses crypto.subtle if present, else CryptoJS.
  // We provide subtle via Dart so AES-GCM works (CryptoJS has no GCM).
  // If Dart bridge is unavailable, subtle methods throw and host.js
  // will NOT fallback to CryptoJS for GCM — so Dart bridge is required
  // for CineHD/CineJoy. For CBC-only providers, CryptoJS fallback also works.
  async function __crypto_call(action, params) {
    var result = await __tj_bridge('__crypto', Object.assign({ action: action }, params || {}));
    if (typeof result === 'string') return result;
    return __TJ_safe_string(result);
  }
  function __normalizeHashName(hash) {
    var name = hash && hash.name ? hash.name : hash;
    name = String(name || 'SHA-256').toUpperCase().replace(/[^A-Z0-9]/g, '');
    if (name === 'SHA1' || name === 'SHA256' || name === 'SHA384' || name === 'SHA512' || name === 'MD5') return name;
    throw new Error('Unsupported hash: ' + name);
  }
  function __normalizeAlgorithmName(algo) {
    var name = algo && algo.name ? algo.name : algo;
    name = String(name || '').toUpperCase();
    if (name.indexOf('AES-GCM') >= 0) return 'AES-GCM';
    if (name.indexOf('AES-CBC') >= 0) return 'AES-CBC';
    if (name.indexOf('AES-ECB') >= 0 || name === 'ECB') return 'AES-ECB';
    if (name.indexOf('PBKDF2') >= 0) return 'PBKDF2';
    if (name.indexOf('HMAC') >= 0) return 'HMAC';
    return name;
  }
  function __makeCryptoKey(type, algorithm, extractable, usages, rawBytes) {
    return { _raw: rawBytes, type: type, algorithm: algorithm, extractable: !!extractable, usages: usages || [] };
  }
  function __webCryptoAlgorithm(algo) {
    if (typeof algo === 'string') return { name: algo };
    return algo || { name: 'AES-CBC' };
  }

  // Only define crypto.subtle if Dart bridge exists OR CryptoJS exists.
  // If neither, leave crypto undefined so host.js throws clearly.
  var __hasCryptoBridge = (typeof sendMessage === 'function' || typeof __tj_native_bridge === 'function');
  if (__hasCryptoBridge || typeof globalThis.CryptoJS !== 'undefined') {
    globalThis.crypto = globalThis.crypto || {};
    // Preserve native subtle if already present (JavaScriptCore on iOS has it)
    var __nativeSubtle = globalThis.crypto.subtle;
    if (!__nativeSubtle || typeof __nativeSubtle.decrypt !== 'function') {
      globalThis.crypto.subtle = {
        digest: async function (algo, data) {
          var hex = await __crypto_call('digest', { algo: __normalizeHashName(algo), dataHex: __bytesToHex(__toUint8Array(data)) });
          return __bytesToArrayBuffer(__hexToBytes(hex));
        },
        importKey: async function (fmt, data, algo, extractable, usages) {
          fmt = String(fmt || 'raw').toLowerCase();
          if (fmt !== 'raw' && fmt !== 'pkcs8' && fmt !== 'spki') throw new Error('Unsupported key format: ' + fmt);
          var algorithm = __webCryptoAlgorithm(algo || {});
          var type = fmt === 'spki' ? 'public' : (fmt === 'pkcs8' ? 'private' : 'secret');
          return __makeCryptoKey(type, algorithm, extractable, usages || [], __toUint8Array(data));
        },
        exportKey: async function (fmt, key) {
          fmt = String(fmt || 'raw').toLowerCase();
          if (fmt !== 'raw' && fmt !== 'pkcs8' && fmt !== 'spki') throw new Error('Unsupported key format: ' + fmt);
          return __bytesToArrayBuffer(key._raw);
        },
        generateKey: async function (algo, extractable, usages) {
          var algorithm = __webCryptoAlgorithm(algo || {});
          if (algorithm.name !== 'AES-CBC' && algorithm.name !== 'AES-GCM' && algorithm.name !== 'HMAC') {
            throw new Error('Unsupported generateKey: ' + algorithm.name);
          }
          var length = algorithm.length || 256;
          var hex = await __crypto_call('random', { bytes: String(length / 8) });
          return __makeCryptoKey('secret', algorithm, extractable, usages || [], __hexToBytes(hex));
        },
        deriveBits: async function (params, key, len) {
          if (__normalizeAlgorithmName(params) !== 'PBKDF2') throw new Error('Only PBKDF2 deriveBits supported');
          var hex = await __crypto_call('pbkdf2', {
            passwordHex: __bytesToHex(__toUint8Array(key._raw)),
            saltHex: __bytesToHex(__toUint8Array(params.salt)),
            iterations: String(params.iterations || 1000),
            keyLengthBits: String(len || 256),
            hash: __normalizeHashName(params.hash || 'SHA-256')
          });
          return __bytesToArrayBuffer(__hexToBytes(hex));
        },
        deriveKey: async function (params, key, derivedKeyAlgo, extractable, usages) {
          var algorithm = __webCryptoAlgorithm(derivedKeyAlgo || {});
          var length = algorithm.length || 256;
          var raw = await globalThis.crypto.subtle.deriveBits(params, key, length);
          return __makeCryptoKey('secret', algorithm, extractable, usages || [], new Uint8Array(raw));
        },
        encrypt: async function (params, key, data) {
          var mode = __normalizeAlgorithmName(params);
          if (mode !== 'AES-CBC' && mode !== 'AES-GCM' && mode !== 'AES-ECB') throw new Error('Unsupported encrypt: ' + mode);
          var hex = await __crypto_call('aesEncrypt', {
            mode: mode,
            keyHex: __bytesToHex(__toUint8Array(key._raw)),
            ivHex: __bytesToHex(__toUint8Array(params.iv || new Uint8Array(0))),
            dataHex: __bytesToHex(__toUint8Array(data))
          });
          return __bytesToArrayBuffer(__hexToBytes(hex));
        },
        decrypt: async function (params, key, data) {
          var mode = __normalizeAlgorithmName(params);
          if (mode !== 'AES-CBC' && mode !== 'AES-GCM' && mode !== 'AES-ECB') throw new Error('Unsupported decrypt: ' + mode);
          var hex = await __crypto_call('aesDecrypt', {
            mode: mode,
            keyHex: __bytesToHex(__toUint8Array(key._raw)),
            ivHex: __bytesToHex(__toUint8Array(params.iv || new Uint8Array(0))),
            dataHex: __bytesToHex(__toUint8Array(data))
          });
          return __bytesToArrayBuffer(__hexToBytes(hex));
        },
        sign: async function (algo, key, data) {
          var hash = (algo && algo.hash) || (key.algorithm && key.algorithm.hash) || 'SHA-256';
          var hex = await __crypto_call('hmac', {
            hash: __normalizeHashName(hash),
            keyHex: __bytesToHex(__toUint8Array(key._raw)),
            dataHex: __bytesToHex(__toUint8Array(data))
          });
          return __bytesToArrayBuffer(__hexToBytes(hex));
        },
        verify: async function (algo, key, sig, data) {
          var hash = (algo && algo.hash) || (key.algorithm && key.algorithm.hash) || 'SHA-256';
          var expectedHex = await __crypto_call('hmac', {
            hash: __normalizeHashName(hash),
            keyHex: __bytesToHex(__toUint8Array(key._raw)),
            dataHex: __bytesToHex(__toUint8Array(data))
          });
          var expected = __hexToBytes(expectedHex);
          var actual = __toUint8Array(sig);
          if (expected.length !== actual.length) return false;
          var diff = 0;
          for (var i = 0; i < expected.length; i++) diff |= expected[i] ^ actual[i];
          return diff === 0;
        }
      };
    }
    if (typeof globalThis.crypto.getRandomValues !== 'function') {
      globalThis.crypto.getRandomValues = function (arr) {
        if (!arr) return arr;
        var byteLength = arr.byteLength != undefined ? arr.byteLength : arr.length;
        if (!byteLength) return arr;
        // Synchronous fallback using Math.random (not cryptographically secure,
        // but only used for nonces/IVs in most plugins). For secure random,
        // plugins should use subtle.generateKey which goes via Dart.
        // We try Dart sync if available, else Math.random.
        var bytes = new Uint8Array(byteLength);
        for (var i = 0; i < byteLength; i++) bytes[i] = Math.floor(Math.random() * 256);
        if (arr.buffer && arr.byteLength != undefined) {
          new Uint8Array(arr.buffer, arr.byteOffset || 0, arr.byteLength).set(bytes);
        } else {
          for (var j = 0; j < arr.length; j++) arr[j] = bytes[j] || 0;
        }
        return arr;
      };
    }
    if (typeof globalThis.crypto.randomUUID !== 'function') {
      globalThis.crypto.randomUUID = function () {
        var b = new Uint8Array(16);
        globalThis.crypto.getRandomValues(b);
        b[6] = (b[6] & 0x0f) | 0x40;
        b[8] = (b[8] & 0x3f) | 0x80;
        var h = __bytesToHex(b);
        return h.substr(0, 8) + '-' + h.substr(8, 4) + '-' + h.substr(12, 4) + '-' + h.substr(16, 4) + '-' + h.substr(20);
      };
    }
  }

  // ── Cheerio stub (providers do not use it; regex/JSON only) ─────────────
  ['__cheerio_load', '__cheerio_select', '__cheerio_find', '__cheerio_text', '__cheerio_html', '__cheerio_inner_html', '__cheerio_attr', '__cheerio_next', '__cheerio_prev'].forEach(function (n) {
    if (typeof globalThis[n] === 'undefined') globalThis[n] = function () { return '[]'; };
  });

  // ── require stub ────────────────────────────────────────────────────────
  if (typeof globalThis.require === 'undefined') {
    globalThis.require = function () { throw new Error('require not available in provider runtime'); };
  }

  // Expose bridges for debugging / tests
  globalThis.__tj_polyfill_loaded = true;
})();
