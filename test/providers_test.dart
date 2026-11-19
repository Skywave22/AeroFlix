import 'package:aeroflix/shared/models/media_details.dart';
import 'package:aeroflix/shared/providers/download_provider.dart';
import 'package:aeroflix/shared/providers/watchlist_provider.dart';
import 'package:aeroflix/shared/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('DownloadItem', () {
    test('JSON round-trip preserves every field', () {
      const item = DownloadItem(
        key: 'movie:10378',
        title: 'Big Buck Bunny',
        subtitle: 'Movie',
        posterPath: '/poster.jpg',
        kind: 'movie',
        mediaId: 10378,
        season: 0,
        episode: 0,
        url: 'https://example.com/bbb.mp4',
        filePath: '/docs/downloads/movie_10378.mp4',
        sizeBytes: 158000000,
        status: DownloadStatus.completed,
        progress: 1.0,
      );
      final back = DownloadItem.fromJson(item.toJson());
      expect(back.key, item.key);
      expect(back.title, item.title);
      expect(back.posterPath, item.posterPath);
      expect(back.url, item.url);
      expect(back.filePath, item.filePath);
      expect(back.sizeBytes, item.sizeBytes);
      expect(back.status, DownloadStatus.completed);
      expect(back.progress, 1.0);
    });

    test('unknown status names fall back to queued', () {
      final item = DownloadItem.fromJson({
        'key': 'movie:1',
        'title': 'T',
        'status': 'not-a-real-status',
      });
      expect(item.status, DownloadStatus.queued);
    });

    test('sizeLabel formats bytes', () {
      const zero = DownloadItem(
          key: 'k',
          title: 't',
          subtitle: 's',
          posterPath: null,
          kind: 'movie',
          mediaId: 1,
          season: 0,
          episode: 0);
      expect(zero.sizeLabel, '—');
      expect(zero.copyWith(sizeBytes: 2048).sizeLabel, '2.0 KB');
      expect(zero.copyWith(sizeBytes: 5 * 1024 * 1024).sizeLabel, '5.0 MB');
      expect(
          zero.copyWith(sizeBytes: 2 * 1024 * 1024 * 1024).sizeLabel, '2.0 GB');
    });

    test('copyWith clears error only when asked', () {
      const item = DownloadItem(
          key: 'k',
          title: 't',
          subtitle: 's',
          posterPath: null,
          kind: 'movie',
          mediaId: 1,
          season: 0,
          episode: 0,
          error: 'boom');
      expect(item.copyWith().error, 'boom');
      expect(item.copyWith(clearError: true).error, isNull);
    });
  });

  group('WatchlistNotifier', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'watchlist': ['movie:1', 'tv:9'],
      });
    });

    test('initial load restores persisted keys', () async {
      final n = WatchlistNotifier();
      // toggle() awaits the internal ready future, so state is loaded by then.
      await n.toggle(MediaType.movie, 2);
      expect(n.isWatched(MediaType.movie, 1), isTrue);
      expect(n.isWatched(MediaType.tv, 9), isTrue);
      expect(n.isWatched(MediaType.movie, 2), isTrue);
      n.dispose();
    });

    test('toggle removes existing keys', () async {
      final n = WatchlistNotifier();
      await n.toggle(MediaType.movie, 1);
      expect(n.isWatched(MediaType.movie, 1), isFalse);
      expect(n.isWatched(MediaType.tv, 9), isTrue);
      n.dispose();
    });
  });

  group('SettingsNotifier', () {
    test('defaults are sensible', () async {
      SharedPreferences.setMockInitialValues({});
      final n = SettingsNotifier();
      await n.setDefaultSpeed(1.5); // waits for the internal ready future
      expect(n.state.autoPlayNext, isTrue);
      expect(n.state.cellularAllowed, isTrue);
      expect(n.state.defaultSpeed, 1.5);
      n.dispose();
    });

    test('persisted values win over defaults', () async {
      SharedPreferences.setMockInitialValues({
        'settings.autoPlayNext': false,
        'settings.defaultSpeed': 2.0,
      });
      final n = SettingsNotifier();
      await n.setCellularAllowed(false); // sync barrier on the ready future
      expect(n.state.autoPlayNext, isFalse);
      expect(n.state.defaultSpeed, 2.0);
      expect(n.state.cellularAllowed, isFalse);
      n.dispose();
    });
  });
}
