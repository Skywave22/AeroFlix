#!/usr/bin/env node
// Validates tj_flutter_providers/assets/js/{crypto-js.min.js,polyfill.js,call.js}
// against a real Plugins-TJ provider bundle in QuickJS, emulating exactly what
// the Dart JsRuntime does:
//   - sendMessage(channel, JSON {__tjId, __tjData})  (fire and forget)
//   - Dart replies by evaluating __TJ_DELIVER(id, ok, "<json>")
//   - Dart pumps executePendingJob() and polls globalThis.__TJ_DONE / __TJ_RESULT
//
// Usage: node test_flutter_polyfill.mjs <providerId> <tmdbId> [movie|tv] [season] [episode]
// Env:   DEBUG_FETCH=1 to log every HTTP request.
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const [id, tmdbId, mediaType = "movie", season, episode] = process.argv.slice(2);
if (!id || !tmdbId) {
  console.error("usage: node test_flutter_polyfill.mjs <id> <tmdbId> [movie|tv] [s] [e]");
  process.exit(2);
}

// Paths: TJ_PROVIDERS_DIR points at a Plugins-TJ checkout (default: sibling clone).
// The polyfill/call/crypto-js assets are read from this package's assets/js.
const SCRIPT_DIR = path.dirname(new URL(import.meta.url).pathname);
const ROOT = process.env.TJ_PROVIDERS_DIR || path.resolve(SCRIPT_DIR, "../../Plugins-TJ");
const FLUTTER = path.resolve(SCRIPT_DIR, "../assets/js");
if (!fs.existsSync(path.join(ROOT, "providers", `${id}.js`))) {
  console.error(`provider not found: ${path.join(ROOT, "providers", id + ".js")}`);
  console.error("set TJ_PROVIDERS_DIR=/path/to/Plugins-TJ/providers-parent (a Plugins-TJ checkout)");
  process.exit(2);
}
const read = (p) => fs.readFileSync(p, "utf8");
const providerCode = read(path.join(ROOT, "providers", `${id}.js`));
const polyfill = read(path.join(FLUTTER, "polyfill.js"));
const callCode = read(path.join(FLUTTER, "call.js"));
const cryptoJs = read(path.join(FLUTTER, "crypto-js.min.js"));

// quickjs-emscripten is resolved from the Plugins-TJ checkout (npm install there),
// falling back to a local node_modules next to this tool.
async function loadQuickJs() {
  try {
    return (await import("quickjs-emscripten")).getQuickJS;
  } catch (_) {
    const { createRequire } = await import("node:module");
    const req = createRequire(path.join(ROOT, "package.json"));
    return (await import(req.resolve("quickjs-emscripten"))).getQuickJS;
  }
}
const QUICKJS = await (await loadQuickJs())();
const rt = QUICKJS.newRuntime();
rt.setMemoryLimit(512 * 1024 * 1024);
const vm = rt.newContext();
const t0 = Date.now();
let httpCount = 0, inflight = 0;

const dump = (h) => (h === undefined ? undefined : vm.dump(h));
const jsString = (s) => JSON.stringify(String(s)).replace(/\u2028/g, "\\u2028").replace(/\u2029/g, "\\u2029");

function define(name, fn) {
  const h = vm.newFunction(name, fn);
  vm.setProp(vm.global, name, h);
  h.dispose();
}

// ── Dart emulation ────────────────────────────────────────────────────────
function deliver(jsId, ok, payload) {
  if (!vm.alive) return;
  const r = vm.evalCode(`__TJ_DELIVER(${Number(jsId)}, ${ok ? "true" : "false"}, ${jsString(payload)});`, "deliver.js");
  if (r.error) { r.error.dispose(); } else { r.value.dispose(); }
  pump();
}

function pump() {
  if (!vm.alive) return;
  try { rt.executePendingJobs(); } catch {}
}

const HASHES = { MD5: "md5", SHA1: "sha1", SHA256: "sha256", SHA384: "sha384", SHA512: "sha512" };
const hashName = (n) => HASHES[String(n || "SHA256").toUpperCase().replace(/[^A-Z0-9]/g, "")] || "sha256";
const hex = (s) => Buffer.from(String(s || ""), "hex");
const toHex = (b) => Buffer.from(b).toString("hex");

async function handleFetch(d) {
  httpCount++;
  const method = (d.method || "GET").toUpperCase();
  if (process.env.DEBUG_FETCH) console.log(`  REQ ${method} ${String(d.url).slice(0, 150)}`);
  const hdrs = { ...(d.headers || {}) };
  for (const k of Object.keys(hdrs)) if (/^accept-encoding$/i.test(k)) delete hdrs[k];
  if (!Object.prototype.hasOwnProperty.call(hdrs, "User-Agent")) {
    hdrs["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
  }
  try {
    const init = { method, headers: hdrs, redirect: d.followRedirects === false ? "manual" : "follow" };
    if (d.bodyKind === "text" && method !== "GET" && method !== "HEAD") init.body = d.body;
    if (d.bodyKind === "base64") init.body = Buffer.from(d.body, "base64");
    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(), 20000);
    init.signal = ac.signal;
    const res = await fetch(d.url, init);
    clearTimeout(timer);
    const buf = Buffer.from(await res.arrayBuffer()).subarray(0, 1024 * 1024);
    const respHeaders = {};
    res.headers.forEach((v, k) => { respHeaders[k.toLowerCase()] = v; });
    if (typeof res.headers.getSetCookie === "function") {
      const cookies = res.headers.getSetCookie();
      if (cookies.length) respHeaders["set-cookie"] = cookies.join(",");
    }
    return JSON.stringify({
      ok: res.status >= 200 && res.status < 300,
      status: res.status,
      statusText: res.statusText,
      url: res.url || d.url,
      body: buf.toString("utf8"),
      bodyBase64: buf.toString("base64"),
      headers: respHeaders,
    });
  } catch (e) {
    return JSON.stringify({ ok: false, status: 0, statusText: String(e.message || e), url: d.url, body: "", bodyBase64: "", headers: {} });
  }
}

async function handleCrypto(d) {
  const a = d.action;
  if (a === "digest") return toHex(crypto.createHash(hashName(d.algo)).update(hex(d.dataHex)).digest());
  if (a === "hmac") return toHex(crypto.createHmac(hashName(d.hash), hex(d.keyHex)).update(hex(d.dataHex)).digest());
  if (a === "pbkdf2") {
    return toHex(crypto.pbkdf2Sync(hex(d.passwordHex), hex(d.saltHex), +d.iterations || 1000, (+d.keyLengthBits || 256) / 8, hashName(d.hash)));
  }
  if (a === "random") return toHex(crypto.randomBytes(+d.bytes || 16));
  if (a === "aesEncrypt" || a === "aesDecrypt") {
    const mode = String(d.mode || "AES-CBC").toUpperCase();
    const key = hex(d.keyHex), iv = hex(d.ivHex), data = hex(d.dataHex);
    const bits = key.length * 8;
    if (mode.includes("GCM")) {
      if (a === "aesEncrypt") {
        const c = crypto.createCipheriv(`aes-${bits}-gcm`, key, iv);
        return toHex(Buffer.concat([c.update(data), c.final(), c.getAuthTag()]));
      }
      const c = crypto.createDecipheriv(`aes-${bits}-gcm`, key, iv);
      c.setAuthTag(data.subarray(data.length - 16));
      return toHex(Buffer.concat([c.update(data.subarray(0, data.length - 16)), c.final()]));
    }
    if (mode.includes("ECB")) {
      const c = a === "aesEncrypt" ? crypto.createCipheriv(`aes-${bits}-ecb`, key, null) : crypto.createDecipheriv(`aes-${bits}-ecb`, key, null);
      c.setAutoPadding(true);
      return toHex(Buffer.concat([c.update(data), c.final()]));
    }
    const c = a === "aesEncrypt" ? crypto.createCipheriv(`aes-${bits}-cbc`, key, iv) : crypto.createDecipheriv(`aes-${bits}-cbc`, key, iv);
    c.setAutoPadding(true);
    return toHex(Buffer.concat([c.update(data), c.final()]));
  }
  throw new Error("unknown crypto action: " + a);
}

// sendMessage(channel, message) — fire and forget, exactly like the Dart bridge.
define("sendMessage", (...args) => {
  const [channel, message] = args.map(dump);
  let envelope = {};
  try { envelope = JSON.parse(message || "{}"); } catch {}
  const jsId = envelope.__tjId;
  const data = envelope.__tjData || {};
  if (channel === "ConsoleLog") {
    try {
      const list = JSON.parse(message);
      const level = list.shift();
      if (level === "error" || process.env.DEBUG_FETCH) console.log(`  [${level}] ${list.join(" ").slice(0, 300)}`);
    } catch {}
    return vm.undefined;
  }
  inflight++;
  (async () => {
    try {
      let payload;
      if (channel === "__native_fetch") payload = await handleFetch(data);
      else if (channel === "__plugin_sleep") {
        await new Promise((r) => setTimeout(r, Math.min(60000, Math.max(0, Number(data.ms) || 0))));
        payload = "true";
      } else if (channel === "__crypto") payload = await handleCrypto(data);
      else throw new Error("unknown channel " + channel);
      deliver(jsId, true, payload);
    } catch (e) {
      deliver(jsId, false, String((e && e.message) || e));
    } finally {
      inflight--;
    }
  })();
  return vm.undefined;
});

// console (provider logs)
const consoleObj = vm.newObject();
for (const level of ["log", "warn", "error", "info", "debug"]) {
  const h = vm.newFunction(level, (...args) => {
    if (level === "error" || process.env.DEBUG_FETCH) {
      console.log(`  [${level}] ${args.map(dump).join(" ").slice(0, 300)}`);
    }
  });
  vm.setProp(consoleObj, level, h);
  h.dispose();
}
vm.setProp(vm.global, "console", consoleObj);
consoleObj.dispose();

function run(src, label) {
  const r = vm.evalCode(src, label);
  if (r.error) {
    const e = vm.dump(r.error);
    r.error.dispose();
    throw new Error(`${label}: ${typeof e === "object" ? (e.message || "") + "\n" + (e.stack || "") : e}`);
  }
  r.value.dispose();
}

console.log(`▶ ${id} — getStreams(${tmdbId}, ${mediaType}${season ? `, ${season}, ${episode}` : ""}) via Flutter polyfill`);
try {
  run(cryptoJs, "crypto-js.min.js");
  run(polyfill, "polyfill.js");
  run(
    `globalThis.SCRAPER_ID = ${JSON.stringify(id)};
     globalThis.SCRAPER_SETTINGS = {};
     globalThis.TMDB_API_KEY = ${JSON.stringify(process.env.TMDB_API_KEY || "439c478a771f35c05022f9feabcca01c")};
     globalThis.__TJ_CALL_ARGS = ${JSON.stringify({ tmdbId: String(tmdbId), mediaType, season: season ? +season : null, episode: episode ? +episode : null })};
     globalThis.__TJ_DONE = false; globalThis.__TJ_RESULT = null; globalThis.__TJ_ERROR = null;`,
    "globals.js",
  );
  run(`var module = { exports: {} };\nvar exports = module.exports;\n(function() {\n${providerCode}\n})();`, `providers/${id}.js`);
  run(callCode, "call.js");
} catch (e) {
  console.log("✖ evaluation failed: " + e.message);
  process.exit(1);
}

const deadline = Date.now() + 60000;
let done = false;
while (Date.now() < deadline) {
  pump();
  const r = vm.evalCode("globalThis.__TJ_DONE === true", "poll");
  done = dump(r.value) === true;
  r.value.dispose();
  if (done) break;
  await new Promise((r) => setTimeout(r, inflight ? 10 : 5));
}

const resR = vm.evalCode("globalThis.__TJ_RESULT", "result");
const resStr = dump(resR.value);
resR.value.dispose();
const errR = vm.evalCode("globalThis.__TJ_ERROR", "err");
const errStr = dump(errR.value);
errR.value.dispose();

const seconds = ((Date.now() - t0) / 1000).toFixed(1);
let streams = [];
try { streams = JSON.parse(resStr || "[]"); } catch { console.log("result not JSON: " + String(resStr).slice(0, 400)); }
if (!done) console.log(`⏱ timed out (60s), partial: ${streams.length}`);
if (errStr) console.log(`  error: ${errStr}`);

console.log(`${streams.length ? "✔" : "○"} ${streams.length} stream(s) in ${seconds}s, ${httpCount} requests`);
for (const s of streams.slice(0, 12)) {
  console.log(`  ${s.name} [${s.quality} ${s.language || ""}] ${String(s.url).slice(0, 110)}`);
}
process.exit(streams.length ? 0 : 1);
