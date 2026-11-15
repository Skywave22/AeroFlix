# AeroFlix

Premium cinematic streaming app for Android & Android TV, built with Flutter.

- Dark cinematic design system (deep surfaces, restrained crimson accent, Inter typography)
- TMDB catalog (trending, popular, top-rated, Hindi cinema, anime, now playing)
- Open Cinema library: royalty-free shorts (Big Buck Bunny, Sintel, …) that play **and download** for real, in-app
- Everything else: official YouTube trailer fallback + clear empty states
- Feature-first architecture, Riverpod state, go_router navigation
- Full-screen HLS/MP4 video player via media_kit (resume, auto-advance, PiP, subtitles, speed)

## Getting started

```bash
flutter pub get
flutter run
```

### TMDB API key

A development key is compiled in by default. For your own release builds,
**rotate it and inject your own at build time**:

```bash
flutter build apk --dart-define=TMDB_API_KEY=your_key_here
```

or set a `TMDB_API_KEY` repository secret in GitHub — the CI workflow picks it
up automatically. The key currently in git history is public to anyone with
repo access; treat it as compromised and rotate it.

## Verify before pushing

```bash
dart format --set-exit-if-changed lib test
flutter analyze        # any analyzer issue fails CI
flutter test
```

## APK build

Push to `main` (or use **Actions → Build Android APK → Run workflow**) and
GitHub Actions builds debug and release APKs as workflow artifacts.
See `.github/workflows/build-android.yml`.

The release APK is signed with the debug key so it can be sideloaded; add a
real `signingConfig` with secrets if you ship on Play.

## Design system

- Colors, typography, spacing and radii live in `lib/app/theme/`
- No hardcoded colors outside `app_colors.dart`
- 4px spacing scale; 8/12/14/18 corner radii
- Single accent (`#E50938`) used sparingly for primary CTAs and active states
