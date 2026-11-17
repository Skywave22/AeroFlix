import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:quickjs_engine/quickjs_engine.dart';
import 'package:http/http.dart' as http;

import 'crypto_bridge.dart';

/// QuickJS / JavaScriptCore runtime that executes TJ-Plugins providers.
///
/// Bridge contract (see assets/js/polyfill.js):
///   JS -> Dart: `sendMessage(channel, JSON {"__tjId": <int>, "__tjData": {...}})`
///   Dart -> JS: `runtime.evaluate('__TJ_DELIVER(<id>, true, "<json string>")')`
///
/// Channels:
///   __native_fetch  -> Dart http (OkHttp-like semantics: default UA, redirects,
///                      1 MB body cap, 20 s timeout)
///   __plugin_sleep  -> Dart Future.delayed (QuickJS has no event loop)
///   __crypto        -> CryptoBridge (AES-CBC/GCM, digest, HMAC, PBKDF2, random)
///
/// The id/deliver handshake is used instead of relying on flutter_js's
/// `sendMessage` return value, which differs between versions and platforms.
///
/// Load order: crypto-js.min.js -> polyfill.js -> provider .js -> call.js
class JsRuntime {
  final String tmdbApiKey;
  final String scraperId;
  final Map<String, dynamic> scraperSettings;
  final Duration fetchTimeout;

  /// Hard cap for one provider call (Nuvio kills providers at 60 s).
  final Duration callTimeout;

  final http.Client _http;

  /// Optional pre-loaded runtime sources. When null (the default) they are read
  /// from the package assets (`assets/js/*.js`). Providing them lets you bundle
  /// the JS elsewhere or run the runtime in tests without an asset bundle.
  final String? polyfillCode;
  final String? callCode;
  final String? cryptoJsCode;

  JsRuntime({
    this.tmdbApiKey = '',
    this.scraperId = '',
    this.scraperSettings = const {},
    this.fetchTimeout = const Duration(seconds: 20),
    this.callTimeout = const Duration(seconds: 60),
    http.Client? httpClient,
    this.polyfillCode,
    this.callCode,
    this.cryptoJsCode,
  }) : _http = httpClient ?? http.Client();

  static const String _packagePrefix = 'packages/tj_flutter_providers/';

  /// Loads a runtime asset (`assets/js/polyfill.js`, `call.js`, `crypto-js`).
  ///
  /// Flutter namespaces package assets inside a host app
  /// (`packages/<package>/assets/js/...`), while the package's own tests and
  /// example see the bare path, so both are tried. Getting this wrong is fatal
  /// but silent: every provider call would throw and the app would report "no
  /// streams" for every title.
  Future<String> _loadAsset(String path, String? override) async =>
      override ?? await loadAsset(path);

  /// Public form of the loader above (used by [TjRuntimeAssets]).
  static Future<String> loadAsset(String path) async {
    try {
      return await rootBundle.loadString('$_packagePrefix$path');
    } catch (_) {
      return await rootBundle.loadString(path);
    }
  }

  /// Runs one provider's getStreams() and returns the raw JSON string
  /// (an array of stream objects — parse with StreamResult.fromJson).
  Future<String> getStreamsJson({
    required String providerCode,
    required String providerId,
    required String tmdbId,
    required String mediaType, // "movie" | "tv"
    int? season,
    int? episode,
    void Function(String)? onLog,
  }) async {
    final runtime = _createRuntime();
    try {
      _registerBridges(runtime, onLog: onLog);

      // 1. CryptoJS — optional, used by plugins that reference global CryptoJS.
      try {
        final cryptoJs = await _loadAsset(
          'assets/js/crypto-js.min.js',
          cryptoJsCode,
        );
        _eval(runtime, cryptoJs, 'crypto-js.min.js');
      } catch (_) {
        // Not fatal: host.js uses crypto.subtle (Dart bridge) when available.
      }

      // 2. Polyfill (fetch / timers / crypto.subtle / URL / atob / TextEncoder)
      final polyfill = await _loadAsset('assets/js/polyfill.js', polyfillCode);
      _eval(runtime, polyfill, 'polyfill.js');

      // 3. Globals the providers expect (mirrors Nuvio JsBindings staticPolyfillCode)
      final args = {
        'tmdbId': tmdbId,
        'mediaType': mediaType,
        'season': season,
        'episode': episode,
      };
      _eval(
        runtime,
        'globalThis.SCRAPER_ID = ${jsonEncode(providerId)};'
            'globalThis.SCRAPER_SETTINGS = ${jsonEncode(scraperSettings)};'
            'globalThis.TMDB_API_KEY = ${jsonEncode(tmdbApiKey)};'
            'globalThis.__TJ_CALL_ARGS = ${jsonEncode(args)};'
            'globalThis.__TJ_DONE = false;'
            'globalThis.__TJ_RESULT = null;'
            'globalThis.__TJ_ERROR = null;',
        'globals.js',
      );

      // Re-assert our fetch in case something else replaced globalThis.fetch.
      _eval(
        runtime,
        'if (globalThis.__TJ_FETCH) { globalThis.fetch = globalThis.__TJ_FETCH; }',
        'fetch.keep.js',
      );

      // 4. Provider bundle (CommonJS wrapper, same as Nuvio PluginRuntime)
      _eval(
        runtime,
        'var module = { exports: {} };\n'
            'var exports = module.exports;\n'
            '(function() {\n$providerCode\n})();',
        'providers/$providerId.js',
      );

      // 5. Kick off getStreams() via call.js
      _eval(
        runtime,
        'if (globalThis.__TJ_FETCH) { globalThis.fetch = globalThis.__TJ_FETCH; }',
        'fetch.keep2.js',
      );
      _eval(
        runtime,
        await _loadAsset('assets/js/call.js', callCode),
        'call.js',
      );

      // 6. Pump the promise queue until call.js flips __TJ_DONE.
      final deadline = DateTime.now().add(callTimeout);
      final doneMarker = 'globalThis.__TJ_DONE === true';
      while (DateTime.now().isBefore(deadline)) {
        runtime.executePendingJob();
        final doneRes = runtime.evaluate(doneMarker);
        if (doneRes.stringResult.trim() == 'true') {
          final errRes = runtime.evaluate('globalThis.__TJ_ERROR');
          final errText = errRes.stringResult.trim();
          if (errText.isNotEmpty &&
              errText != 'null' &&
              errText != 'undefined') {
            onLog?.call('provider error: $errText');
          }
          return runtime.evaluate('globalThis.__TJ_RESULT').stringResult;
        }
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
      onLog?.call('provider timed out after ${callTimeout.inSeconds}s');
      return '[]';
    } finally {
      try {
        runtime.dispose();
      } catch (_) {}
    }
  }

  /// Creates the JS engine.
  ///
  /// Engine: quickjs_engine (QuickJS-NG 0.14). The older flutter_js QuickJS
  /// cannot compile these minified provider bundles at all — it aborts with
  /// "InternalError: unconsistent stack size" — so QuickJS-NG is a hard
  /// requirement, verified against real Plugins-TJ providers.
  ///
  /// 16 MB stack: provider bundles contain deeply nested async generators that
  /// overflow flutter_js-style 1 MB defaults.
  static JavascriptRuntime _createRuntime() {
    try {
      return QuickJsRuntime2(stackSize: 16 * 1024 * 1024);
    } catch (_) {
      // Fall back to the package default (xhr:false keeps its own fetch out of
      // the way — ours implements the Nuvio contract: default UA, redirect
      // handling, base64 bodies, status 0 on failure).
      return getJavascriptRuntime(xhr: false);
    }
  }

  /// Evaluates [code]; throws with the JS error message on failure.
  static void _eval(JavascriptRuntime runtime, String code, String label) {
    final res = runtime.evaluate(code, sourceUrl: label);
    if (res.isError) {
      throw Exception('$label: ${res.stringResult}');
    }
  }

  void _registerBridges(
    JavascriptRuntime runtime, {
    void Function(String)? onLog,
  }) {
    runtime.onMessage('__native_fetch', (dynamic message) {
      // Handle off the platform thread; reply via __TJ_DELIVER so we never
      // depend on sendMessage's return value.
      unawaited(_bridgeFetch(runtime, _envelope(message)));
      return null;
    });

    runtime.onMessage('__plugin_sleep', (dynamic message) {
      unawaited(_bridgeSleep(runtime, _envelope(message)));
      return null;
    });

    runtime.onMessage('__crypto', (dynamic message) {
      unawaited(_bridgeCrypto(runtime, _envelope(message)));
      return null;
    });

    runtime.onMessage('ConsoleLog', (dynamic message) {
      try {
        final list = message is List
            ? message
            : jsonDecode(message.toString()) as List;
        onLog?.call(list.map((e) => e.toString()).join(' '));
      } catch (_) {}
      return null;
    });
  }

  Future<void> _bridgeFetch(
    JavascriptRuntime runtime,
    _Envelope envelope,
  ) async {
    final data = envelope.data;
    try {
      final payload = await _nativeFetch(
        url: data['url']?.toString() ?? '',
        method: data['method']?.toString() ?? 'GET',
        headers: _stringMap(data['headers']),
        bodyKind: data['bodyKind']?.toString() ?? 'none',
        body: data['body']?.toString() ?? '',
        followRedirects: data['followRedirects'] != false,
      );
      _deliver(runtime, envelope.id, true, payload);
    } catch (e) {
      _deliver(runtime, envelope.id, false, e.toString());
    }
  }

  Future<void> _bridgeSleep(
    JavascriptRuntime runtime,
    _Envelope envelope,
  ) async {
    final raw = envelope.data['ms'];
    final ms = (raw is num ? raw.toInt() : int.tryParse('$raw')) ?? 0;
    await Future<void>.delayed(Duration(milliseconds: ms.clamp(0, 60000)));
    _deliver(runtime, envelope.id, true, 'true');
  }

  Future<void> _bridgeCrypto(
    JavascriptRuntime runtime,
    _Envelope envelope,
  ) async {
    try {
      final hex = await CryptoBridge.handle(envelope.data);
      _deliver(runtime, envelope.id, true, hex);
    } catch (e) {
      _deliver(runtime, envelope.id, false, e.toString());
    }
  }

  /// Resolves the JS-side pending promise created by `__tj_bridge`.
  static void _deliver(
    JavascriptRuntime runtime,
    int id,
    bool ok,
    String payload,
  ) {
    try {
      runtime.evaluate(
        '__TJ_DELIVER($id, ${ok ? 'true' : 'false'}, ${_jsString(payload)});',
        sourceUrl: 'deliver.js',
      );
    } catch (_) {
      // Runtime may already be disposed (timeout) — nothing to do.
    }
  }

  /// Encodes [value] as a JS string literal (handles U+2028/U+2029, quotes).
  static String _jsString(String value) {
    final encoded = jsonEncode(value);
    return encoded
        .replaceAll('\u2028', r'\u2028')
        .replaceAll('\u2029', r'\u2029');
  }

  _Envelope _envelope(dynamic message) {
    dynamic decoded = message;
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        return const _Envelope(0, {});
      }
    }
    if (decoded is List && decoded.isNotEmpty) decoded = decoded.first;
    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      final id =
          (map['__tjId'] as num?)?.toInt() ??
          int.tryParse('${map['__tjId']}') ??
          0;
      final data = map['__tjData'];
      return _Envelope(
        id,
        data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
      );
    }
    return const _Envelope(0, {});
  }

  /// OkHttp-like fetch, matching Nuvio FetchBridge + tools/lib/fetch-emu.mjs:
  ///  - adds the Windows Chrome UA unless "User-Agent" was set explicitly
  ///  - drops Accept-Encoding (Dart http handles it)
  ///  - follows redirects unless followRedirects == false
  ///  - caps the body at 1 MB like Nuvio's MAX_BODY
  Future<String> _nativeFetch({
    required String url,
    required String method,
    required Map<String, String> headers,
    required String bodyKind,
    required String body,
    required bool followRedirects,
  }) async {
    const maxBody = 1024 * 1024;
    const defaultUa =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

    final hdrs = Map<String, String>.from(headers);
    hdrs.removeWhere((k, _) => k.toLowerCase() == 'accept-encoding');
    if (!hdrs.containsKey('User-Agent')) hdrs['User-Agent'] = defaultUa;

    final upperMethod = method.toUpperCase();
    try {
      final req = http.Request(upperMethod, Uri.parse(url));
      req.headers.addAll(hdrs);
      req.followRedirects = followRedirects;
      req.maxRedirects = 5;
      if (bodyKind == 'text' && upperMethod != 'GET' && upperMethod != 'HEAD') {
        req.body = body;
      } else if (bodyKind == 'base64') {
        req.bodyBytes = base64Decode(body);
      }

      final streamed = await _http.send(req).timeout(fetchTimeout);
      final bytes = await streamed.stream.toBytes().timeout(fetchTimeout);
      final truncated = bytes.length > maxBody;
      final bodyBytes = truncated ? bytes.sublist(0, maxBody) : bytes;
      final text = utf8.decode(bodyBytes, allowMalformed: true);

      final respHeaders = <String, String>{};
      streamed.headers.forEach((k, v) {
        respHeaders[k.toLowerCase()] = v.length > 8192
            ? '${v.substring(0, 8177)}...[truncated]'
            : v;
      });

      return jsonEncode({
        'ok': streamed.statusCode >= 200 && streamed.statusCode < 300,
        'status': streamed.statusCode,
        'statusText': streamed.reasonPhrase ?? '',
        'url': streamed.request?.url.toString() ?? url,
        'body': truncated ? '$text\n...[truncated]' : text,
        'bodyBase64': base64Encode(bodyBytes),
        'headers': respHeaders,
      });
    } catch (e) {
      // Never throw into JS: providers expect a response object (Nuvio returns
      // status 0 for network failures so scripts can handle it).
      return jsonEncode({
        'ok': false,
        'status': 0,
        'statusText': e.toString(),
        'url': url,
        'body': '',
        'bodyBase64': '',
        'headers': <String, String>{},
      });
    }
  }

  static Map<String, String> _stringMap(dynamic v) {
    final out = <String, String>{};
    if (v is Map) {
      v.forEach((k, val) {
        if (val != null) out[k.toString()] = val.toString();
      });
    }
    return out;
  }

  void dispose() => _http.close();
}

class _Envelope {
  final int id;
  final Map<String, dynamic> data;
  const _Envelope(this.id, this.data);
}

/// The three JS sources every provider needs (polyfill, call wrapper, CryptoJS).
///
/// Loaded once and reused — both in-process and inside provider isolates, which
/// cannot touch the asset bundle.
class TjRuntimeAssets {
  const TjRuntimeAssets({
    required this.polyfill,
    required this.call,
    required this.cryptoJs,
  });

  final String polyfill;
  final String call;
  final String cryptoJs;

  static TjRuntimeAssets? _cached;

  /// Loads the bundled sources (cached for the process lifetime).
  static Future<TjRuntimeAssets> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    final loaded = TjRuntimeAssets(
      polyfill: await JsRuntime.loadAsset('assets/js/polyfill.js'),
      call: await JsRuntime.loadAsset('assets/js/call.js'),
      cryptoJs: await JsRuntime.loadAsset('assets/js/crypto-js.min.js'),
    );
    _cached = loaded;
    return loaded;
  }
}
