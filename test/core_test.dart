import 'package:aeroflix/core/errors/failures.dart';
import 'package:aeroflix/shared/models/media_details.dart';
import 'package:aeroflix/shared/models/stream_source.dart';
import 'package:aeroflix/shared/providers/continue_watching_provider.dart';
import 'package:aeroflix/shared/providers/open_cinema_provider.dart';
import 'package:aeroflix/core/utils/trailer_helper.dart';
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

  group('Open Cinema library', () {
    test('known id yields a playable HTTPS stream', () async {
      final streams = await openCinemaGetStreams(
          const MediaDetails(type: MediaType.movie, id: 10378, title: 'BBB'));
      expect(streams, isNotEmpty);
      expect(streams.first.url, startsWith('https://'));
      expect(streams.first.providerId, 'open-cinema');
    });

    test('unknown id yields no streams', () async {
      final streams = await openCinemaGetStreams(
          const MediaDetails(type: MediaType.movie, id: 1234567, title: 'X'));
      expect(streams, isEmpty);
    });

    test('id lookup is exact, not a prefix match', () {
      expect(isOpenCinemaId(10378), isTrue);
      expect(isOpenCinemaId(1037), isFalse);
      expect(isOpenCinemaId(103780), isFalse);
    });

    test('MP4 entries support offline download, HLS does not', () {
      expect(openCinemaSupportsDownload(10378), isTrue); // Big Buck Bunny MP4
      expect(openCinemaSupportsDownload(900001), isFalse); // HLS test stream
      expect(openCinemaSupportsDownload(999999), isFalse); // unknown
    });

    test('openCinemaStreamUrl mirrors the map', () {
      expect(openCinemaStreamUrl(7486), contains('Sintel.mp4'));
      expect(openCinemaStreamUrl(999999), isNull);
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
}
