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
flutter build apk --release     # sideloadable APK (debug-signed unless configured)
```

### Signing a release build

`flutter build apk --release` produces a working APK out of the box, but it is
signed with the **debug** key unless you supply a real keystore. A debug-signed
build cannot be published to Google Play and cannot be updated in place by a
properly signed build later, so configure signing before the first public
release.

1. Create an upload keystore (once, keep it safe — losing it means you can never
   update the app on Play):

   ```bash
   keytool -genkey -v -keystore aeroflix-release.jks -keyalg RSA \
     -keysize 2048 -validity 10000 -alias aeroflix
   ```

2. Put it at `android/app/aeroflix-release.jks` and create
   `android/key.properties` (both git-ignored):

   ```properties
   storeFile=aeroflix-release.jks
   storePassword=…
   keyAlias=aeroflix
   keyPassword=…
   ```

3. `android/app/build.gradle` picks the file up automatically and falls back to
   the debug keystore only when it is missing. CI does the same from the
   `KEYSTORE_BASE64`, `KEY_ALIAS`, `KEY_PASSWORD` and `STORE_PASSWORD` secrets
   and prints a warning when they are absent.

### TMDB API key

A development key is compiled in by default. For release builds inject your own:

```bash
flutter build apk --release --dart-define=TMDB_API_KEY=your_key_here
```

or set the `TMDB_API_KEY` repository secret — CI passes it through automatically.

> **This key is not a secret.** Anything passed with `--dart-define` is compiled
> into the Dart snapshot, and the bundled provider (`assets/providers/tjaio.js`)
> also carries the same development key as a fallback. Treat it as public, keep
> rate limits in mind, and rotate it via TMDB if it is ever abused.

## Verify before pushing

```bash
dart format --output=none --set-exit-if-changed lib test \
  packages/tj_flutter_providers/lib packages/tj_flutter_providers/test
flutter analyze          # must be clean (errors/warnings)
flutter test
```

CI (`.github/workflows/build-android.yml`) runs format → analyze → test for
both the app and `packages/tj_flutter_providers` (which has its own suite and
was previously skipped), then builds debug and release APKs and uploads them as
artifacts.

## Architecture notes

- `lib/app/theme/` is the only place sizes, radii and type come from:
  `AppSpacing` (spacing scale, poster/row sizes, text-scale-aware rows and
  adaptive grid columns), `AppRadii` (card/sheet radii) and `AppTypography`
  (the single type scale). Screen code should not hard-code numbers or
  `TextStyle`s.
- `lib/shared/widgets/` holds the reusable building blocks (poster card,
  continue-watching card, section placeholders/errors). `PosterCard` and
  `ContinueCard` take their height from the parent, so a row height can never
  clip a title.
- Error surfaces use `SectionErrorState` / `InlineErrorRow` with a retry, and
  text from `Failure.toUserMessage()` — never a raw exception string.
- Player overlays are wrapped in `IgnorePointer` when hidden; an
  `AnimatedOpacity` at 0 still hit-tests, which is what made "invisible"
  controls steal taps.

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
