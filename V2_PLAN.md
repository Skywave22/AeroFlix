# AeroFlix v2 Plan

## Current State (v1 issues found during audit)

### Critical — app is non-functional
1. **Piracy embeds unplayable**: The five providers (VidSrc/VidSpark/AutoEmbed/Vidsrc etc.) all run in-browser JS crypto + WebAssembly challenges (domain rotation using SHA-256 + rotating alphabet keyed to current UTC hour). Dart's HTTP client cannot execute them → Play spins forever or shows "No streams."
2. **Play button on hero/cards tries to push '/player' with PlayerArgs for movies** but stream resolvers return empty → infinite spinner, no error path visible.
3. **MediaDetails.trailers are fetched from TMDB** (`append_to_response=videos`) but never surfaced anywhere in the UI — the player doesn't use them.

### Major UX bugs
4. The player surface shows backdrop image while "loading" forever with no way out except back button.
5. No "Watch Trailer" CTA anywhere, even though TMDB returns YouTube trailers for almost every title.
6. Hero "Play" button launches the player which will always fail for non-demo content — should fall back to trailer or clearly indicate "Trailer".
7. Continue Watching cards resume but the episode picker has no visual distinction for watched-in-progress.
8. Watchlist doesn't show empty-state art when empty.
9. Downloads list uses simulated progress (fake) and never actually downloads a file.
10. Deep links `aeroflix://movie/:id` work but are never advertised (share sheet still shares TMDB URLs, not deep links).
11. Episode strip in player has no loading state while episodes are being fetched (blank area).
12. Seek-preview thumbnail doesn't use actual stills (only backdrop crop).
13. "NEW"/"UPCOMING" badges are calculated from DateTime.now() every build — no consistency if user changes clock.
14. PiP button shows a success toast but doesn't visibly enter PiP until user backgrounds the app (auto-enter is enabled, but the explicit tap path isn't always clear).

### Minor polish
15. Home app bar float/snap causes jank on first pull.
16. Poster cards don't show vote-average like episode rows do.
17. Search idle screen shows "Popular genres" chips but tapping them does nothing.
18. Search results don't remember scroll position when switching tabs.
19. Settings "Reset all data" doesn't reset downloads (intentional but should be clear).
20. Back navigation from player doesn't always save progress (async persist can race).

---

## v2 Architecture

### 1. Player is a TRAILER player, not a pirate player
- **Remove** all the broken embed scrapers (VidSrc, VidSpark, Cinezo, ScreenScape, etc.).
- **Use TMDB's videos endpoint** which returns YouTube keys.
- "Play" button → play trailer inline in the player OR launch YouTube app.
- A new "Where to watch" panel (using TMDB `/watch/providers` — free with API key) shows legal streaming services in the user's region (Netflix, Disney+, Prime, etc.) with deep links to those apps when installed.
- This makes the app 100% legitimate, 100% reliable, and 100% API-compliant.

### 2. Streaming providers panel (instead of fake play)
- Add `lib/features/details/watch_providers_section.dart`.
- Fetch `/movie/{id}/watch/providers` and `/tv/{id}/watch/providers` from TMDB (already included in `append_to_response` if we add it).
- Show country-specific provider icons + deep-link to the provider.
- "Watch Trailer" is the primary CTA when no subscription provider is installed.

### 3. Real trailer player
- For trailers, open YouTube via `url_launcher` (`https://www.youtube.com/watch?v=<key>`) — clean, reliable, always works.
- Optional: a WebView-based player using `youtube_player_flutter` or similar for inline trailers (add as a v2.1 feature).

### 4. Inline player stays but uses provided media
- Remove dependency on media_kit scraping; keep media_kit for:
  - Downloaded files (real MP4s from Downloads).
  - User's own local media (future feature).
  - A built-in "Open Source Cinema" library (Big Buck Bunny, Sintel, Tears of Steel, etc. — stable CDN URLs that always play) — gives us a reliable "it works" demo.
- "Play" on an open-source-cinema title plays real video in the existing player.
- "Play" on a regular movie/show shows the watch-providers panel + "Watch Trailer" CTA.

### 5. Downloads = real file downloads (Dio)
- Replace the fake progress simulator with real Dio download to the app documents directory.
- Tap downloaded item → opens the file in media_kit player (offline playback works).

### 6. Fix list for v2 (this pass)
- [x] Remove broken embed providers.
- [ ] Add TMDB videos → trailer action across hero/details/player.
- [ ] Add "Where to watch" providers panel to Details screen.
- [ ] Add an Open Source Cinema section to Home so the player is demonstrable.
- [ ] Fix player error UI: show error after 15s with "Watch Trailer" escape hatch.
- [ ] Wire Continue-Watching resume % in episodes list.
- [ ] Empty states everywhere (Watchlist, Downloads, Search history).
- [ ] Make search genre chips actually search that genre.
- [ ] Save progress synchronously on player dispose.
- [ ] Polish: vote-average on poster cards, consistent app bar, share deep-links using `aeroflix://`.
- [ ] v2 bump to 0.2.0 in pubspec.yaml.
