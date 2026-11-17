# TJ Flutter Providers

Run **[Plugins-TJ](https://github.com/Skywave22/Plugins-TJ)** (25 Nuvio streaming providers) inside your **Flutter app** — with **automatic updates** whenever the repo owner ships a fix.

Your app already uses TMDB for posters/data. This package adds the missing half: **playable streams** for any TMDB id, from Cinezo, ScreenScape, Nxsha, AniHype, KatDrama + 20 more — the same provider code Nuvio runs, executed in a real JS engine inside your app.

**Verified working** against the live providers (this build, Inception `tmdb 27205` unless noted):

| Provider | Result | Time |
|---|---|---|
| Cinezo | 20 links (Hindi first, up to 4K) | 14 s |
| ScreenScape | 20 links | 16 s |
| Nxsha (movie) | 19 links | 11 s |
| Nxsha (S01E01 `tmdb 1396`) | 16 links | 11 s |
| AniHype (S01E01 `tmdb 95479`) | 10 links | 7 s |
| CineJoy (AES-GCM crypto path) | 26 links | 10 s |
| CineHD (AES-GCM crypto path) | 17 links | 14 s |
| Net77 (session/cookie flow) | 1 link | 41 s |

KatDrama returns 0 for titles it does not carry (Squid Game packs currently resolve to an empty page) — that is upstream behaviour, confirmed identical with Nuvio's own test harness.

---

## 1. How it works

```
GitHub (Skywave22/Plugins-TJ)
  manifest.json        versions of all 25 providers
  providers/<id>.js    ready-to-run provider bundles (CommonJS getStreams)

Your Flutter app (this package)
  ProviderManager   fetches manifest.json, compares versions, downloads changed
                    .js to <appDocs>/tj_providers/   (NOT bundled in the APK)
  JsRuntime         runs provider JS in QuickJS-NG, wiring fetch / timers / crypto
                    to Dart
  ProviderService   getStreams(tmdbId, "movie") -> List<StreamResult>
  ProvidersScreen   drop-in settings UI with "Update available" badges
  StreamsSheet      drop-in bottom sheet that lists links and calls your player
```

**Auto-update:** provider `.js` files live on GitHub, never in your APK. When Skywave22 pushes a fix, users get it on the next launch or refresh — **no Play Store release needed**. Only the runtime (`polyfill.js`, `call.js`, `crypto-js.min.js`) ships with the app, and it changes only if the provider contract changes.

---

## 2. Install

### Dependencies

```yaml
# pubspec.yaml
environment:
  sdk: '>=3.8.0 <4.0.0'      # required by the JS engine
  flutter: '>=3.32.0'

dependencies:
  quickjs_engine: ^0.1.7     # QuickJS-NG 0.14 — the JS engine
  http: ^1.2.0
  path_provider: ^2.1.0
  path: ^1.9.0
  crypto: ^3.0.3
  pointycastle: ^3.9.1

flutter:
  assets:
    - assets/js/polyfill.js
    - assets/js/call.js
    - assets/js/crypto-js.min.js
```

Either depend on this folder as a path package, or copy `lib/` + `assets/js/` into your app.

Android: `minSdkVersion 21`+, and the NDK is needed once (the engine compiles its C sources — standard for Flutter plugins with native code). iOS: nothing extra, CocoaPods builds it.

> **Why QuickJS-NG and not `flutter_js`?** `flutter_js` bundles an old QuickJS that cannot even compile these bundles — it fails with `InternalError: unconsistent stack size` before running a line. `quickjs_engine` is an API-compatible fork with QuickJS-NG 0.14 and runs every provider tested. This is why the package needs Flutter 3.32+; on older Flutter the engine cannot be installed.

### Wire it up

```dart
import 'package:tj_flutter_providers/tj_providers.dart';

final manager = ProviderManager();
final service = ProviderService(
  manager: manager,
  tmdbApiKey: 'YOUR_TMDB_API_KEY',            // the key you already use for posters
  enabledIds: ProviderManager.recommendedIds, // cinezo, screenscape, nxsha, anihype, katdrama
);

// Splash / app start: download providers + pick up upstream updates
await service.syncOnLaunch();
```

### Show streams on a detail page

```dart
showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  builder: (_) => StreamsSheet(
    service: service,
    tmdbId: '27205',        // movie
    mediaType: 'movie',     // or 'tv'
    // season: 1, episode: 2,   for series
    title: 'Inception',
    onPlay: (stream) {
      player.open(Media(
        stream.url,
        headers: stream.headers,        // required by some servers
        // stream.subtitles -> [{url, language}]
      ));
    },
  ),
);
```

Or call it directly:

```dart
final streams = await service.getStreams(
  tmdbId: '27205',
  mediaType: 'movie',
);
// StreamResult(name: "Cinezo · Scape Nitro - Hindi · English", quality: "1080p",
//              url: "https://...", language: "Hindi",
//              headers: {"Referer": "..."}, subtitles: [...])
// Already sorted Hindi-first, then best quality.
```

### Settings UI (providers + manual update)

```dart
Navigator.push(context, MaterialPageRoute(
  builder: (_) => ProvidersScreen(service: service),
));
```

Lists all providers with versions, "Update available: v1.0.9 → v1.0.12" badges, enable/disable switches, pull-to-refresh and an Update button.

---

## 3. Auto-update in detail

| Trigger | Behaviour |
|---|---|
| App launch (`syncOnLaunch`) | Fetch `manifest.json`, compare per-provider versions, download new/changed `.js` |
| "Check for updates" (ProvidersScreen) | Same, on demand |
| Offline / GitHub down | Falls back to cached `manifest.json` + cached `.js`; app keeps working |
| Provider deleted upstream | Cached file removed on next sync |
| Download fails | Old cached version is kept and stays usable |

Storage: `<appDocuments>/tj_providers/meta.json` (versions, paths, sizes), `<id>.js`, `manifest.json`.

Version compare is per-provider (`cinezo 1.0.12` > `cinezo 1.0.9`), not per-repo, so a 200 KB provider update does not re-download everything — a normal launch when up to date costs one ~18 KB manifest request.

---

## 4. Provider set

**Recommended starter pack** (`ProviderManager.recommendedIds`): `cinezo`, `screenscape`, `nxsha`, `anihype`, `katdrama`.

To offer everything (all 25):

```dart
final manifest = await manager.fetchManifest();
final allIds = manifest.scrapers.map((e) => e.id).toList();
final service = ProviderService(manager: manager, tmdbApiKey: key, enabledIds: allIds);
```

All ids: anihype, bingr, cinehd, cinejoy, cinezo, desidubanime, fmovies, hicine, histream, katdrama, katmoviehd, kdmaza, kmmovies, movieshubhd, net77, nxsha, pikahd, rareanimes, rivestream, screenscape, ssrmovies, subdubanime, vidbox, zenix, zxcstream.

Notes: `kdmaza` is TV-only, `kmmovies` is movie-only. More providers = more latency when opening a title (they run in parallel, ~10–40 s worst case) — 5 well-chosen providers is usually the better UX.

---

## 5. Project layout

```
tj_flutter_providers/
  lib/
    tj_providers.dart                 exports
    src/
      models.dart                     ProviderInfo, Manifest, StreamResult, CachedProvider
      provider_manager.dart           manifest fetch, version compare, download, cache
      provider_service.dart           getStreams() across providers, sorting, timeouts
      js_runtime.dart                 QuickJS-NG runtime + fetch/timers/crypto bridges
      crypto_bridge.dart              Dart crypto for crypto.subtle (AES-CBC/GCM, SHA, HMAC, PBKDF2)
      widgets/providers_screen.dart   providers + updates UI
      widgets/streams_sheet.dart      link picker UI
  assets/js/
    polyfill.js                       fetch / timers / crypto.subtle / URL / atob / TextEncoder
    call.js                           getStreams invocation wrapper
    crypto-js.min.js                  CryptoJS 4.1.1 (for plugins using global CryptoJS)
  example/                            runnable demo app
  test/                               unit tests + opt-in live tests
  tool/test_polyfill.mjs              QuickJS harness (Node) for debugging providers
```

---

## 6. How the JS side is wired

Each provider bundle expects Nuvio's runtime. This package reproduces it:

| JS global | Backed by | Notes |
|---|---|---|
| `fetch` | `__native_fetch` → Dart `http` | OkHttp-like: default Windows Chrome UA, redirects, 1 MB body cap, 20 s timeout, `status: 0` on network error; response exposes `text()`, `json()`, `arrayBuffer()`, `headers.get()` — no `.body` (same as Nuvio; `host.js` uses `res.text()`) |
| `setTimeout` / `setInterval` | `__plugin_sleep` → `Future.delayed` | QuickJS has no event loop, so Dart drives the clock |
| `crypto.subtle` | `__crypto` → `CryptoBridge` | digest, HMAC, PBKDF2, AES-CBC/ECB/GCM, `getRandomValues`, `randomUUID` |
| `atob` / `btoa`, `TextEncoder/Decoder`, `URL`, `URLSearchParams`, `AbortController` | pure JS in `polyfill.js` | no bridge needed |
| `TMDB_API_KEY`, `SCRAPER_ID`, `SCRAPER_SETTINGS` | set by Dart before load | the key you pass in |

Bridges use an explicit id/deliver handshake (`sendMessage(channel, {__tjId, __tjData})` → Dart → `__TJ_DELIVER(id, ok, json)`), so behaviour does not depend on `flutter_js`-style `sendMessage` return values.

Load order: `crypto-js.min.js` → `polyfill.js` → provider `.js` → `call.js`. Then Dart pumps the job queue until `__TJ_DONE`, with a 60 s cap per provider (Nuvio's own limit).

Dart-side correctness of the crypto bridge is pinned by tests against OpenSSL vectors (`AES-128-CBC/ECB`, `AES-256-GCM`, SHA-256, MD5, HMAC-SHA256, PBKDF2-SHA256`).

---

## 7. Tests

```bash
flutter test                                   # unit tests (manifest, versions, cache, offline, parsing)
```

Opt-in live tests (network + the native engine):

```bash
# build the engine once for desktop testing
(cd ~/.pub-cache/hosted/pub.dev/quickjs_engine-0.1.7 && sh tool/build_native.sh)
export LIBQUICKJSC_TEST_PATH=~/.pub-cache/hosted/pub.dev/quickjs_engine-0.1.7/native/build/libquickjs_c_bridge_plugin.so

# every bridge (fetch, timers, crypto.subtle incl. AES-GCM) in one provider
TJ_LIVE_TESTS=1 flutter test test/js_runtime_live_test.dart

# a real Plugins-TJ provider end to end
TJ_PROVIDER_DIR=/path/to/Plugins-TJ/providers TJ_PROVIDER=cinezo \
  TJ_TMDB_ID=27205 TJ_MEDIA_TYPE=movie flutter test test/real_provider_live_test.dart
```

Debugging a provider outside Flutter (fastest loop, no device):

```bash
cd /path/to/Plugins-TJ && npm install
node ../tj_flutter_providers/tool/test_polyfill.mjs cinezo 27205 movie
DEBUG_FETCH=1 node ../tj_flutter_providers/tool/test_polyfill.mjs nxsha 1396 tv 1 1
```

---

## 8. Troubleshooting

| Symptom | Fix |
|---|---|
| `unconsistent stack size` | You are on `flutter_js`, not `quickjs_engine` — swap the dependency (see §2) |
| Everything returns `[]` | Providers not downloaded yet (`syncOnLaunch()`), no network, or the sites are down; open ProvidersScreen → Update |
| One title shows nothing | Normal: not every title is on every site. Try another provider or title. |
| AES-GCM providers (CineHD/CineJoy) fail | `pointycastle` + `crypto` must be dependencies (they are, in this package) |
| Links 403 in the player | Pass `stream.headers` (especially `Referer`) to the player |
| Slow first open | 5 providers in parallel ≈ 7–20 s; the first run also downloads the bundles |
| Net77 slow | It runs a mobile session handshake — 30–45 s is expected |
| Links work on device but not in desktop tests | Some hosts do Cloudflare/UA checks — trust device results |

---

## 9. Credits & licences

- Providers: **[Skywave22/Plugins-TJ](https://github.com/Skywave22/Plugins-TJ)** — the repo hosts only code; media comes from third-party sites. Respect your local laws.
- Runtime behaviour mirrors **NuvioMobile** `JsBindings.kt` (GPL-3.0, NuvioMedia): `polyfill.js`/`call.js` are adapted re-implementations. If you ship this in a closed-source app, review GPL obligations or rewrite those two files.
- QuickJS-NG via `quickjs_engine` (MIT), CryptoJS (MIT), pointycastle (MIT).
- This package: use it freely within the constraints above.
