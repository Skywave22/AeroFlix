# AeroFlix

Premium cinematic streaming app for Android & Android TV, built with Flutter.

- Dark cinematic design system (deep surfaces, restrained crimson accent, Inter typography)
- TMDB catalog (trending, popular, top-rated, Hindi cinema, anime, now playing)
- Streaming providers adapted from [TJ-Plugins](https://github.com/Skywave22/TJ-Plugins) / [Plugins-TJ](https://github.com/Skywave22/Plugins-TJ)
- Feature-first architecture, Riverpod state, go_router navigation
- Full-screen HLS/MP4 video player via media_kit

## Getting Started

```bash
flutter pub get
flutter run
```

## APK Build

Push to `main` and GitHub Actions builds both debug and release APKs as artifacts.
See `.github/workflows/build-android.yml`.

## Design System

- Colors, typography, spacing and radii live in `lib/app/theme/`
- No hardcoded colors outside `app_colors.dart`
- 4px spacing scale; 8/12/14/18 corner radii
- Single accent (`#E50938`) used sparingly for primary CTAs and active states
