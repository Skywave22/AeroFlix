import 'package:aeroflix/core/errors/failures.dart';
import 'package:aeroflix/shared/models/media_details.dart';
import 'package:aeroflix/shared/models/stream_source.dart';
import 'package:aeroflix/shared/providers/continue_watching_provider.dart';
import 'package:aeroflix/core/utils/trailer_helper.dart';
import 'package:aeroflix/shared/models/watch_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Failure', () {
    test('network failure surfaces a network message and keeps its cause', () {
      final f = Failure.network(cause: 'boom');
      expect(f.code, 'NETWORK');
      expect(f.cause, 'boom');
      expect(f.toUserMessage(), contains('internet'));
    });

    test('timeout keeps its cause', () {
      final f = Failure.timeout(cause: 't');
      expect(f.code, 'TIMEOUT');
      expect(f.cause, 't');
      expect(f.toUserMessage(), contains('too long'));
    });

    test('unknown codes fall back to the raw message', () {
      const f = Failure(code: 'WEIRD', message: 'custom text');
      expect(f.toUserMessage(), 'custom text');
    });

    test('parse failures expose a readable message', () {
      expect(Failure.parse(cause: Exception('x')).toUserMessage(), isNotEmpty);
    });
  });

  group('ContinueWatchingItem', () {
    ContinueWatchingItem item({int positionMs = 0, int durationMs = 1000}) =>
        ContinueWatchingItem(
          type: MediaType.movie,
          id: 42,
          title: 'Test',
          positionMs: positionMs,
          durationMs: durationMs,
          updatedAt: 1,
        );

    test('progress is clamped to 0..1', () {
      expect(item(positionMs: 500, durationMs: 1000).progress, 0.5);
      expect(item(positionMs: 5000, durationMs: 1000).progress, 1.0);
      expect(item(positionMs: 0, durationMs: 0).progress, 0.0);
    });

    test('isFinished within 30s of the end', () {
      const hour = 60 * 60 * 1000;
      expect(
          item(positionMs: hour - 15000, durationMs: hour).isFinished, isTrue);
      expect(item(positionMs: hour ~/ 2, durationMs: hour).isFinished, isFalse);
      expect(item(positionMs: 999999, durationMs: 0).isFinished, isFalse);
    });

    test('key format matches the details-screen convention', () {
      const i = ContinueWatchingItem(
        type: MediaType.tv,
        id: 7,
        title: 'Show',
        season: 2,
        episode: 3,
        positionMs: 0,
        durationMs: 0,
        updatedAt: 0,
      );
      expect(i.key, 'tv:7:2x03');
    });

    test('JSON round-trip preserves fields', () {
      const i = ContinueWatchingItem(
        type: MediaType.tv,
        id: 7,
        title: 'Show',
        posterPath: '/p.jpg',
        backdropPath: '/b.jpg',
        season: 1,
        episode: 4,
        episodeTitle: 'Pilot',
        positionMs: 123,
        durationMs: 456,
        updatedAt: 789,
      );
      final j = i.toJson();
      final back = ContinueWatchingItem.fromJson(j);
      expect(back.id, 7);
      expect(back.type, MediaType.tv);
      expect(back.season, 1);
      expect(back.episode, 4);
      expect(back.positionMs, 123);
      expect(back.durationMs, 456);
      expect(back.episodeTitle, 'Pilot');
      expect(back.key, i.key);
    });
  });

  group('stream sorting (real provider output)', () {
    StreamSource s(String quality, String language, {String? name}) =>
        StreamSource(
          url: 'https://example.com/x.m3u8',
          name: name ?? 'Provider · $quality',
          providerId: 'cinezo',
          quality: quality,
          language: language,
        );

    test('best quality first, Hindi before other languages at equal quality',
        () {
      // Mirror of StreamService's ordering contract.
      final list = [
        s('480p', 'Hindi'),
        s('1080p', 'English'),
        s('1080p', 'Hindi'),
        s('4K', 'English'),
      ];
      int rank(String? q) {
        final v = (q ?? '').toLowerCase();
        if (v.contains('4k') || v.contains('2160')) return 5;
        if (v.contains('1440')) return 4;
        if (v.contains('1080')) return 3;
        if (v.contains('720')) return 2;
        if (v.contains('480')) return 1;
        return 0;
      }

      list.sort((a, b) {
        final byQuality = rank(b.quality).compareTo(rank(a.quality));
        if (byQuality != 0) return byQuality;
        final aHindi =
            (a.language ?? '').toLowerCase().contains('hindi') ? 0 : 1;
        final bHindi =
            (b.language ?? '').toLowerCase().contains('hindi') ? 0 : 1;
        return aHindi.compareTo(bHindi);
      });

      expect(list.first.quality, '4K');
      expect(list[1].quality, '1080p');
      expect(list[1].language, 'Hindi');
      expect(list.last.quality, '480p');
    });

    test('StreamSource carries headers and subtitles through', () {
      const src = StreamSource(
        url: 'https://example.com/a.m3u8',
        name: 'Cinezo · Scape Nitro',
        providerId: 'cinezo',
        quality: '1080p',
        language: 'Hindi + English',
        headers: {'Referer': 'https://cinezo.gd/'},
        subtitles: [
          SubtitleTrack(
              url: 'https://example.com/en.vtt',
              language: 'English',
              label: 'English'),
        ],
      );
      expect(src.headers['Referer'], contains('cinezo'));
      expect(src.subtitles.single.language, 'English');
    });
  });

  group('trailerUrl', () {
    MediaDetails withTrailers(List<VideoTrailer> trailers) => MediaDetails(
        type: MediaType.movie, id: 1, title: 'T', trailers: trailers);

    const other = VideoTrailer(
        id: '1', key: 'aaa', name: 'Teaser', site: 'YouTube', type: 'Trailer');
    const official = VideoTrailer(
        id: '2',
        key: 'bbb',
        name: 'Official Trailer',
        site: 'YouTube',
        type: 'Trailer',
        official: true);

    test('prefers the entry named Official Trailer', () {
      final d = withTrailers([other, official]);
      expect(trailerUrl(d), 'https://www.youtube.com/watch?v=bbb');
    });

    test('returns the first YouTube trailer when none is official', () {
      final d = withTrailers([other]);
      expect(trailerUrl(d), 'https://www.youtube.com/watch?v=aaa');
    });

    test('ignores non-YouTube and non-Trailer entries', () {
      final d = withTrailers([
        const VideoTrailer(
            id: '3', key: 'ccc', name: 'Clip', site: 'Vimeo', type: 'Trailer'),
        const VideoTrailer(
            id: '4',
            key: 'ddd',
            name: 'Featurette',
            site: 'YouTube',
            type: 'Featurette'),
      ]);
      expect(trailerUrl(d), isNull);
    });
  });

  group('StreamSource', () {
    test('copyWith preserves identity fields', () {
      const s = StreamSource(
          url: 'https://x/y.mp4',
          name: 'Test',
          providerId: 'p',
          quality: '720p');
      final s2 = s.copyWith(quality: '1080p');
      expect(s2.url, s.url);
      expect(s2.providerId, s.providerId);
      expect(s2.quality, '1080p');
    });
  });

  group('WatchProviders', () {
    test('empty when every group is empty', () {
      const p = WatchProviders(region: 'US');
      expect(p.isEmpty, isTrue);
    });

    test('not empty with a streaming provider; logo URL built from path', () {
      const netflix = WatchProvider(
          providerId: 8, displayName: 'Netflix', logoPath: '/xyz.jpg');
      const p = WatchProviders(
          region: 'IN', flatrate: [netflix], link: 'https://link');
      expect(p.isEmpty, isFalse);
      expect(netflix.logoUrl, 'https://image.tmdb.org/t/p/w92/xyz.jpg');
      expect(const WatchProvider(providerId: 1, displayName: 'NoLogo').logoUrl,
          '');
    });

    test('fromJson reads provider fields safely', () {
      final wp = WatchProvider.fromJson({
        'provider_id': 9,
        'provider_name': 'Prime Video',
        'logo_path': '/p.png'
      });
      expect(wp.providerId, 9);
      expect(wp.displayName, 'Prime Video');
      expect(wp.logoUrl, contains('/p.png'));
    });
  });
}
