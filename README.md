# AeroFlix

Premium cinematic streaming for Android phones and Android TV, built with Flutter.

AeroFlix is a **catalogue + playback** app: TMDB supplies posters, ratings, cast,
artwork and "where to watch", and the actual playable links are resolved at
request time by the [TJ-Plugins](https://github.com/Skywave22/Plugins-TJ)
provider plugins running inside the app.

## What works (no demo content, no fake buttons)

| Area | Behaviour |
|---|---|
| Catalogue | TMDB trending / popular / top-rated / Hindi rows / anime / now playing, search, person pages |
| Playback | Real HLS/MP4/MKV links resolved from 5 bundled providers (Cinezo, ScreenScape, Nxsha, AniHype, KatDrama) with per-link headers and subtitles |
| Provider updates | A snapshot of the providers ships inside the APK, so the first launch works even with GitHub blocked; on every launch the app also syncs from GitHub (raw → jsDelivr → githack) and picks up upstream fixes with no app update |
| Trailer | Official YouTube trailer as the fallback when nothing resolves |
| Downloads | Real byte-for-byte downloads of direct MP4/MKV sources, offline playback from the player |
| Player | media_kit: resume, auto-advance to the next episode, speed, subtitles, PiP, wake lock |
| Watchlist / Continue watching | Persisted locally |

Empty states are honest: if a provider has no working link for a title, the app
says so and offers the trailer instead of showing a broken player.

## Providers

Provider JS bundles are **shipped in the APK** (`assets/providers/`, a snapshot
of `Skywave22/Plugins-TJ`) and copied into `<appDocs>/tj_providers/` on first
launch — so streams resolve with no network at all. On every launch the app then
fetches `manifest.json` from GitHub (falling back to jsDelivr and githack when
raw.githubusercontent.com is unreachable), compares versions, and downloads only
what changed.

- Settings → **Providers** shows every provider, its version, and an
  "Update available" badge with a manual update button.
- Settings → **Provider status** is the diagnostics screen: seed/sync state,
  the mirror that answered, cached versions, and a live "run every provider"
  test that reports link counts and errors per provider.
- The engine is QuickJS-NG (`quickjs_engine`), which is required: the older
  `flutter_js` QuickJS cannot compile these bundles.
- `packages/tj_flutter_providers/` is the vendored runtime (Dart bridges for
  fetch / timers / crypto, the Nuvio-compatible JS polyfill, and the call
  wrapper). See its README for the internals.

## Requirements

- Flutter **3.50.0** (Dart 3.14) — pinned in CI; `quickjs_engine` needs Dart ≥ 3.8
- Gradle **9.5.0**, AGP **9.3.1**, Kotlin **2.4.20** (Flutter 3.50 rejects older ones)
- `compileSdk 36`, NDK **27** (native QuickJS + media_kit), JDK 17
- APK size: ~100 MB universal (libmpv + QuickJS for 4 ABIs); use
  `--split-per-abi` for ~35 MB arm64 builds

## Build

```bash
flutter pub get
flutter run                     # device / emulator
flutter build apk --release     # sideloadable APK (debug-signed)
```

### TMDB API key

A development key is compiled in by default. For release builds inject your own:

```bash
flutter build apk --release --dart-define=TMDB_API_KEY=your_key_here
```

or set the `TMDB_API_KEY` repository secret — CI passes it through automatically.

## Verify before pushing

```bash
dart format --output=none --set-exit-if-changed lib test \
  packages/tj_flutter_providers/lib packages/tj_flutter_providers/test
flutter analyze          # must be clean (errors/warnings)
flutter test
```

CI (`.github/workflows/build-android.yml`) runs format → analyze → test, then
builds debug and release APKs and uploads them as artifacts.

## Brand

- Logo: the Aero mark (blue → violet gradient) with the `AeroFlix` wordmark; the
  adaptive launcher icon, monochrome layer and splash all derive from
  `assets/images/logo_mark.png`.
- Launcher label is `AeroFlix` via `@string/app_name`.
- Colours and type scale live in `lib/app/theme/` — the accent is the logo blue
  (`#2F7BFF`) with the violet end (`#7B2BF7`) used for gradients.

## Legal

AeroFlix hosts no video. It resolves links from third-party sites through
community provider plugins; availability and legality vary by region. TMDB data
is used under their API terms — this product is not endorsed or certified by
TMDB.
