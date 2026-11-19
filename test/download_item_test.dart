import 'package:aeroflix/shared/providers/download_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for two data bugs that only showed up on a device:
///
/// 1. `DownloadItem` dropped the provider's HTTP headers, so a header-gated
///    CDN answered 403 during download while the same URL played fine.
/// 2. `DownloadItem` gained a `headers` field; the JSON round-trip has to keep
///    it or every relaunch loses the headers again.
void main() {
  DownloadItem sample({Map<String, String> headers = const {}}) => DownloadItem(
        key: 'movie:550',
        title: 'Fight Club',
        subtitle: 'Movie',
        posterPath: '/poster.jpg',
        kind: 'movie',
        mediaId: 550,
        season: 0,
        episode: 0,
        url: 'https://cdn.example.com/fight-club.mp4',
        headers: headers,
        status: DownloadStatus.failed,
        error: 'HTTP 403',
      );

  test('headers survive the JSON round-trip', () {
    final original = sample(
      headers: {
        'Referer': 'https://stream.example.com/',
        'Origin': 'https://stream.example.com',
        'User-Agent': 'Mozilla/5.0',
      },
    );
    final restored = DownloadItem.fromJson(original.toJson());

    expect(restored.headers, original.headers);
    expect(restored.url, original.url);
    expect(restored.status, DownloadStatus.failed);
  });

  test('items persisted before headers existed load with none', () {
    // A v1.4.0 index entry has no 'headers' key at all.
    final legacy = {
      'key': 'tv:1399:1:1',
      'title': 'Game of Thrones',
      'subtitle': 'S01E01',
      'kind': 'tv',
      'mediaId': 1399,
      'season': 1,
      'episode': 1,
      'url': 'https://cdn.example.com/s1e1.mp4',
      'status': 'completed',
      'progress': 1.0,
    };
    final item = DownloadItem.fromJson(legacy);
    expect(item.headers, isEmpty);
    expect(item.status, DownloadStatus.completed);
  });

  test('copyWith keeps headers unless they are replaced', () {
    final original = sample(headers: {'Referer': 'https://a.example'});
    expect(original.copyWith(title: 'Renamed').headers, original.headers);
    expect(
      original.copyWith(headers: {'Referer': 'https://b.example'}).headers,
      {'Referer': 'https://b.example'},
    );
  });

  test('size label is honest for unknown and known sizes', () {
    expect(sample().sizeLabel, '—');
    expect(
      const DownloadItem(
        key: 'movie:1',
        title: 'x',
        subtitle: '',
        posterPath: null,
        kind: 'movie',
        mediaId: 1,
        season: 0,
        episode: 0,
        sizeBytes: 1536,
      ).sizeLabel,
      '1.5 KB',
    );
  });
}
