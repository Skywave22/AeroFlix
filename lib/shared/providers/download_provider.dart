import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DownloadStatus { queued, downloading, paused, completed, failed }

class DownloadItem {
  final String key; // 'movie:id' or 'tv:id:s:e'
  final String title;
  final String subtitle;
  final String? posterPath;
  final String kind; // 'movie' | 'tv'
  final int mediaId;
  final int season, episode;

  /// Remote source to download from. Items without a URL are refused —
  /// AeroFlix never fakes a download.
  final String? url;

  /// Local file path, set once the download completes.
  final String? filePath;
  final int sizeBytes;
  final DownloadStatus status;
  final double progress; // 0..1
  final String? error;

  const DownloadItem({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.posterPath,
    required this.kind,
    required this.mediaId,
    required this.season,
    required this.episode,
    this.url,
    this.filePath,
    this.sizeBytes = 0,
    this.status = DownloadStatus.queued,
    this.progress = 0,
    this.error,
  });

  DownloadItem copyWith({
    String? title,
    String? subtitle,
    String? posterPath,
    String? url,
    String? filePath,
    int? sizeBytes,
    DownloadStatus? status,
    double? progress,
    String? error,
    bool clearError = false,
  }) =>
      DownloadItem(
        key: key,
        title: title ?? this.title,
        subtitle: subtitle ?? this.subtitle,
        posterPath: posterPath ?? this.posterPath,
        kind: kind,
        mediaId: mediaId,
        season: season,
        episode: episode,
        url: url ?? this.url,
        filePath: filePath ?? this.filePath,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        error: clearError ? null : (error ?? this.error),
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'title': title,
        'subtitle': subtitle,
        'posterPath': posterPath,
        'kind': kind,
        'mediaId': mediaId,
        'season': season,
        'episode': episode,
        'url': url,
        'filePath': filePath,
        'sizeBytes': sizeBytes,
        'status': status.name,
        'progress': progress,
        'error': error,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> j) {
    final statusName = (j['status'] as String?) ?? 'queued';
    return DownloadItem(
      key: (j['key'] ?? '') as String,
      title: (j['title'] ?? 'Download') as String,
      subtitle: (j['subtitle'] ?? '') as String,
      posterPath: j['posterPath'] as String?,
      kind: (j['kind'] ?? 'movie') as String,
      mediaId: (j['mediaId'] as int?) ?? 0,
      season: (j['season'] as int?) ?? 0,
      episode: (j['episode'] as int?) ?? 0,
      url: j['url'] as String?,
      filePath: j['filePath'] as String?,
      sizeBytes: (j['sizeBytes'] as int?) ?? 0,
      status: DownloadStatus.values.firstWhere((s) => s.name == statusName,
          orElse: () => DownloadStatus.queued),
      progress: ((j['progress'] as num?) ?? 0).toDouble().clamp(0.0, 1.0),
      error: j['error'] as String?,
    );
  }

  String get sizeLabel {
    if (sizeBytes <= 0) return '—';
    const units = ['B', 'KB', 'MB', 'GB'];
    double v = sizeBytes.toDouble();
    var u = 0;
    while (v >= 1024 && u < units.length - 1) {
      v /= 1024;
      u++;
    }
    return '${v.toStringAsFixed(u == 0 ? 0 : 1)} ${units[u]}';
  }
}

/// Real download manager. Streams bytes with Dio into
/// `<app documents>/downloads/`, tracks progress, persists the index
/// (including path, size and resume-able metadata) to SharedPreferences, and
/// deletes files when entries are removed.
///
/// Only items carrying a source [DownloadItem.url] are accepted, one download
/// runs at a time, and `pause` cancels the transfer (resume restarts it —
/// byte-range resume is not supported by the CDN endpoints we use).
class DownloadNotifier extends StateNotifier<List<DownloadItem>> {
  static const _kKey = 'aeroflix.downloads.v2';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(minutes: 10),
    followRedirects: true,
    validateStatus: (s) => s != null && s < 400,
  ));
  final Map<String, CancelToken> _tokens = {};
  final Map<String, double> _lastReported = {};

  DownloadNotifier() : super(const []) {
    _ready = _load();
  }

  late final Future<void> _ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) {
      state = const [];
      return;
    }
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final items = <DownloadItem>[];
      for (final j in list) {
        var item = DownloadItem.fromJson(j);
        if (item.key.isEmpty) continue;
        if (item.status == DownloadStatus.completed) {
          final path = item.filePath;
          final ok = path != null && await File(path).exists();
          if (!ok) continue; // file vanished — drop the stale entry
        } else if (item.status != DownloadStatus.failed) {
          // Interrupted mid-flight or paused: requeue cleanly on next launch.
          item = item.copyWith(
            status: DownloadStatus.queued,
            progress: 0,
            clearError: true,
          );
        }
        items.add(item);
      }
      state = items;
    } catch (_) {
      state = const [];
    }
    _kickOff();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final list = state
        .map((d) => d.status == DownloadStatus.downloading
            ? d.copyWith(status: DownloadStatus.paused)
            : d)
        .map((e) => e.toJson())
        .toList();
    await prefs.setString(_kKey, jsonEncode(list));
  }

  /// True while at least one download is running or queued.
  bool get isBusy => state.any((d) =>
      d.status == DownloadStatus.downloading ||
      d.status == DownloadStatus.queued);

  Future<bool> enqueue(DownloadItem item) async {
    await _ready;
    final url = item.url;
    if (url == null || url.isEmpty) return false; // no real source
    if (state.any((d) => d.key == item.key)) return false;
    state = [
      item.copyWith(
          status: DownloadStatus.queued, progress: 0, clearError: true),
      ...state,
    ];
    await _persist();
    _kickOff();
    return true;
  }

  void _kickOff() {
    if (state.any((d) => d.status == DownloadStatus.downloading)) return;
    final i = state.indexWhere((d) => d.status == DownloadStatus.queued);
    if (i >= 0) unawaited(_start(i));
  }

  List<DownloadItem> _replace(DownloadItem item) {
    final next = [...state];
    final i = next.indexWhere((d) => d.key == item.key);
    if (i < 0) return next;
    next[i] = item;
    return next;
  }

  void _setProgress(String key, {double? progress, int? sizeBytes}) {
    final i = state.indexWhere((d) => d.key == key);
    if (i < 0) return;
    state = _replace(state[i].copyWith(
      progress: progress,
      sizeBytes: sizeBytes,
    ));
  }

  Future<void> _start(int index) async {
    final item = state[index];
    final url = item.url;
    if (url == null || url.isEmpty) {
      state = _replace(
          item.copyWith(status: DownloadStatus.failed, error: 'No source URL'));
      await _persist();
      _kickOff();
      return;
    }
    final token = CancelToken();
    _tokens[item.key] = token;
    state = _replace(item.copyWith(
        status: DownloadStatus.downloading, progress: 0, clearError: true));
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/downloads');
      await dir.create(recursive: true);
      final file = File('${dir.path}/${_fileNameFor(item)}');
      await _dio.download(
        url,
        file.path,
        cancelToken: token,
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          final p = (received / total).clamp(0.0, 1.0);
          final last = _lastReported[item.key] ?? -1.0;
          // Throttle UI updates to ~1% steps.
          if (p - last >= 0.01 || p == 1.0) {
            _lastReported[item.key] = p;
            _setProgress(item.key, progress: p, sizeBytes: total);
          }
        },
      );
      final len = await file.length();
      state = _replace(item.copyWith(
        status: DownloadStatus.completed,
        progress: 1,
        filePath: file.path,
        sizeBytes: len,
      ));
      await _persist();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        // Paused or removed by the user — state already updated by caller.
      } else {
        state = _replace(state
            .firstWhere((d) => d.key == item.key, orElse: () => item)
            .copyWith(status: DownloadStatus.failed, error: _dioError(e)));
        await _persist();
      }
    } catch (e) {
      state = _replace(state
          .firstWhere((d) => d.key == item.key, orElse: () => item)
          .copyWith(status: DownloadStatus.failed, error: e.toString()));
      await _persist();
    } finally {
      _tokens.remove(item.key);
      _lastReported.remove(item.key);
      _kickOff(); // start the next queued item
    }
  }

  String _fileNameFor(DownloadItem item) {
    final safeKey = item.key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final uri = Uri.tryParse(item.url ?? '');
    var ext = '';
    if (uri != null && uri.path.contains('.')) {
      ext = uri.path.substring(uri.path.lastIndexOf('.'));
      if (ext.length > 6) ext = '';
    }
    return '$safeKey${ext.isEmpty ? '.mp4' : ext}';
  }

  String _dioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Timed out';
      case DioExceptionType.connectionError:
        return 'No connection';
      default:
        final code = e.response?.statusCode;
        return code != null ? 'HTTP $code' : 'Download failed';
    }
  }

  /// Cancel an in-flight download and keep its partial progress as "paused".
  Future<void> pause(String key) async {
    await _ready;
    final i = state.indexWhere((d) => d.key == key);
    if (i < 0) return;
    final item = state[i];
    if (item.status != DownloadStatus.downloading &&
        item.status != DownloadStatus.queued) {
      return;
    }
    _tokens[key]?.cancel('paused');
    _tokens.remove(key);
    state = _replace(item.copyWith(status: DownloadStatus.paused));
    await _persist();
  }

  /// Requeue a paused/failed download. Downloads restart from byte 0.
  Future<void> resume(String key) async {
    await _ready;
    final i = state.indexWhere((d) => d.key == key);
    if (i < 0) return;
    final item = state[i];
    state = _replace(item.copyWith(
        status: DownloadStatus.queued, progress: 0, clearError: true));
    await _persist();
    _kickOff();
  }

  Future<void> retry(String key) => resume(key);

  Future<void> remove(String key) async {
    await _ready;
    _tokens[key]?.cancel('removed');
    _tokens.remove(key);
    final item = state.firstWhere((d) => d.key == key,
        orElse: () => DownloadItem(
            key: '',
            title: '',
            subtitle: '',
            posterPath: null,
            kind: 'movie',
            mediaId: 0,
            season: 0,
            episode: 0));
    // Delete the file (and any partial leftovers) from disk.
    final paths = <String>{
      if (item.filePath != null) item.filePath!,
      if (item.url != null)
        await getApplicationDocumentsDirectory()
            .then((d) => '${d.path}/downloads/${_fileNameFor(item)}'),
    };
    for (final path in paths) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    state = state.where((d) => d.key != key).toList();
    await _persist();
  }

  Future<void> clearCompleted() async {
    await _ready;
    final done = state
        .where((d) => d.status == DownloadStatus.completed)
        .map((d) => d.key)
        .toList();
    for (final key in done) {
      await remove(key);
    }
  }

  bool has(String key) => state.any((d) => d.key == key);
  DownloadItem? byKey(String key) {
    final i = state.indexWhere((d) => d.key == key);
    return i < 0 ? null : state[i];
  }

  @override
  void dispose() {
    for (final t in _tokens.values) {
      t.cancel('disposed');
    }
    _tokens.clear();
    _dio.close(force: true);
    super.dispose();
  }
}

final downloadProvider =
    StateNotifierProvider<DownloadNotifier, List<DownloadItem>>(
        (_) => DownloadNotifier());
