# AeroFlix — status & roadmap

_Last updated: 2026-11-17 · v1.0.0 (build 4)_

The original v1 audit in this file listed 20 defects (broken embed scrapers,
fake downloads, infinite spinners, trailer data fetched but never used). All of
them are resolved; the notes below record how, and what is left.

## Resolved

| # | v1 defect | Now |
|---|---|---|
| 1 | Piracy embeds unplayable (JS crypto + WASM challenges) | Solved by running the provider bundles in a real JS engine (QuickJS-NG via `quickjs_engine`), not by scraping them from Dart |
| 2 | Play button → infinite spinner | Play resolves sources first; empty result opens the trailer with an explicit message |
| 3 | TMDB trailers fetched but never surfaced | "Watch Trailer" CTA on details + trailer fallback |
| 4 | Player surface spins forever with no exit | Loading/error states + retry + back |
| 5 | No trailer CTA | Added |
| 6 | Hero Play always fails | Hero Play → details; details Play → player with real sources |
| 7 | Continue-watching rows indistinguishable | Progress bar + remaining-time label |
| 8 | Empty watchlist had no art | Empty state |
| 9 | Downloads were simulated | Real HTTP downloads of direct MP4/MKV sources, resumable, offline playback |
| 10 | Deep links not advertised | Share uses `aeroflix://` deep links |
| 11 | Episode strip blank while loading | Loading skeleton |
| 13 | "NEW" badges recomputed per build | Computed once per catalogue load |
| 17 | Genre chips dead | Chips open filtered search |
| — | Demo "Free to Watch" library | Replaced with real TMDB rows |

## Current architecture

- **Catalogue**: TMDB (trending, popular, top rated, Hindi, anime, now playing,
  search, people, seasons/episodes, watch providers).
- **Sources**: `packages/tj_flutter_providers` — QuickJS-NG runtime + Dart
  bridges (fetch/timers/crypto) executing the [Plugins-TJ](https://github.com/Skywave22/Plugins-TJ)
  bundles, with manifest-based versioning and on-device caching.
- **Player**: media_kit (libmpv) with HLS/MP4/MKV, subtitles, headers, resume.
- **Build**: Flutter 3.50.0, Gradle 9.5.0, AGP 9.3.1, KGP 2.4.20, NDK 27,
  compileSdk 36, minSdk from Flutter (24).

## Provider delivery (2026-11-17)

- Bundled seed in `assets/providers/`: first launch works offline / on carriers
  where raw.githubusercontent.com is blocked.
- Sync falls back across mirrors (raw → jsDelivr → githack).
- Player streams results per provider: it starts the first working link while
  the remaining providers are still being scraped, and shows per-provider
  progress instead of a bare spinner.
- "Provider status" screen reports seed/sync state, mirror, cached versions and
  a live per-provider test with link counts and errors.
- "Where to Watch" (JustWatch/TMDB) was removed by request.

## Known limitations (honest list)

1. **HLS cannot be downloaded.** Offline copies require a direct MP4/MKV; the
   app tells the user instead of faking a download.
2. **Provider quality varies by title.** A provider that works for one film may
   return nothing for another; that is upstream behaviour, not an app bug.
3. **Provider breakage needs an upstream fix**, which arrives automatically on
   the next launch once Plugins-TJ is updated (Settings → Providers shows
   versions and a manual update button).
4. **`material_ui` migration.** Flutter 3.47+ deprecated `package:flutter/material.dart`
   in favour of `material_ui`; the app still uses `material.dart` (fully
   supported in 3.50) and mutes only that deprecation in `analysis_options.yaml`.
5. **Universal APK is ~100 MB** because it ships libmpv + QuickJS for four ABIs.
   Add `--split-per-abi` for ~35 MB arm64 builds.
6. **Release APK is debug-signed** so it can be sideloaded; add a keystore +
   signing config before publishing anywhere.

## Next ideas

- Per-ABI release artifacts + a signed build.
- Provider health dashboard (last success/latency per provider, from real runs).
- Cast support (media_kit has no cast; would need `flutter_cast_framework`).
- Trakt import for watchlists.
