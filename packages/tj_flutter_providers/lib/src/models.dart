/// Models matching Plugins-TJ manifest.json + provider getStreams() output.
///
/// Manifest (https://raw.githubusercontent.com/Skywave22/Plugins-TJ/main/manifest.json):
/// {
///   "name": "TJ-Plugins", "version": "1.0.72",
///   "scrapers": [
///     { "id": "cinezo", "name": "Cinezo", "version": "1.0.12",
///       "filename": "providers/cinezo.js", "supportedTypes": ["movie","tv"],
///       "formats": ["m3u8","mp4"], "logo": "...", "contentLanguage": ["hi","en"] }
///   ]
/// }
///
/// Stream (from src/_lib/adapter.js toNuvio()):
/// { "name": "Cinezo · Nitro", "title": "Inception (2010)",
///   "url": "https://...m3u8", "quality": "1080p", "provider": "cinezo",
///   "language": "Hindi", "size": "1.2 GB",
///   "headers": {"Referer": "..."}, "subtitles": [{"url": "...", "language": "English"}] }

class ProviderInfo {
  final String id;
  final String name;
  final String description;
  final String version;
  final String author;
  final List<String> supportedTypes; // ["movie","tv"]
  final String filename; // "providers/cinezo.js"
  final bool enabled;
  final List<String> formats; // ["m3u8","mp4"]
  final String? logo;
  final List<String> contentLanguage;

  const ProviderInfo({
    required this.id,
    required this.name,
    this.description = '',
    required this.version,
    this.author = 'TJ-Plugins',
    this.supportedTypes = const ['movie', 'tv'],
    required this.filename,
    this.enabled = true,
    this.formats = const [],
    this.logo,
    this.contentLanguage = const [],
  });

  factory ProviderInfo.fromJson(Map<String, dynamic> json) {
    return ProviderInfo(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      version: json['version']?.toString() ?? '1.0.0',
      author: json['author']?.toString() ?? 'TJ-Plugins',
      supportedTypes: _stringList(json['supportedTypes']),
      filename: json['filename']?.toString() ?? 'providers/${json['id']}.js',
      enabled: json['enabled'] != false,
      formats: _stringList(json['formats']),
      logo: json['logo']?.toString(),
      contentLanguage: _stringList(json['contentLanguage']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'version': version,
    'author': author,
    'supportedTypes': supportedTypes,
    'filename': filename,
    'enabled': enabled,
    'formats': formats,
    'logo': logo,
    'contentLanguage': contentLanguage,
  };

  static List<String> _stringList(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    return [];
  }

  @override
  String toString() => 'ProviderInfo($id v$version)';
}

class Manifest {
  final String name;
  final String version;
  final String description;
  final String author;
  final List<ProviderInfo> scrapers;

  const Manifest({
    required this.name,
    required this.version,
    this.description = '',
    this.author = 'TJ-Plugins',
    required this.scrapers,
  });

  factory Manifest.fromJson(Map<String, dynamic> json) {
    final list = (json['scrapers'] as List?) ?? [];
    return Manifest(
      name: json['name']?.toString() ?? 'TJ-Plugins',
      version: json['version']?.toString() ?? '1.0.0',
      description: json['description']?.toString() ?? '',
      author: json['author']?.toString() ?? 'TJ-Plugins',
      scrapers: list
          .whereType<Map>()
          .map((e) => ProviderInfo.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  ProviderInfo? byId(String id) {
    for (final p in scrapers) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// One playable link returned by a provider's getStreams().
class StreamResult {
  final String name; // "Cinezo · Nitro"
  final String title; // "Inception (2010)" or with S01E02
  final String url; // https://...m3u8 / .mp4 / .mkv
  final String quality; // "1080p", "4K", "Auto", "CAM"
  final String provider; // provider id, e.g. "cinezo"
  final String? language; // "Hindi", "Hindi + English (Multi)"
  final String? size; // "1.2 GB"
  final Map<String, String> headers;
  final List<Subtitle> subtitles;

  const StreamResult({
    required this.name,
    required this.title,
    required this.url,
    this.quality = 'Auto',
    required this.provider,
    this.language,
    this.size,
    this.headers = const {},
    this.subtitles = const [],
  });

  factory StreamResult.fromJson(Map<String, dynamic> json) {
    final headers = <String, String>{};
    final rawHeaders = json['headers'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) {
        if (v != null && v is! Map && v is! List)
          headers[k.toString()] = v.toString();
      });
    }
    final subs = <Subtitle>[];
    final rawSubs = json['subtitles'];
    if (rawSubs is List) {
      for (final s in rawSubs) {
        if (s is Map) {
          final url = s['url']?.toString() ?? s['file']?.toString() ?? '';
          if (url.isNotEmpty) {
            subs.add(
              Subtitle(
                url: url,
                language:
                    s['language']?.toString() ??
                    s['label']?.toString() ??
                    s['name']?.toString() ??
                    'Unknown',
              ),
            );
          }
        }
      }
    }
    return StreamResult(
      name: json['name']?.toString() ?? 'Server',
      title: json['title']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      quality: json['quality']?.toString() ?? 'Auto',
      provider: json['provider']?.toString() ?? '',
      language: json['language']?.toString(),
      size: json['size']?.toString(),
      headers: headers,
      subtitles: subs,
    );
  }

  bool get isHls =>
      url.contains('.m3u8') ||
      url.startsWith('data:application/vnd.apple.mpegurl');
  bool get isMp4 => url.contains('.mp4');
  bool get isMkv => url.contains('.mkv');

  @override
  String toString() => 'StreamResult($name [$quality] $url)';
}

class Subtitle {
  final String url;
  final String language;
  const Subtitle({required this.url, required this.language});
}

/// Local cache state for one downloaded provider.
class CachedProvider {
  final String id;
  final String version; // version from manifest at download time
  final String filePath; // absolute path to providers/<id>.js on disk
  final DateTime downloadedAt;
  final int sizeBytes;

  const CachedProvider({
    required this.id,
    required this.version,
    required this.filePath,
    required this.downloadedAt,
    this.sizeBytes = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'version': version,
    'filePath': filePath,
    'downloadedAt': downloadedAt.toIso8601String(),
    'sizeBytes': sizeBytes,
  };

  factory CachedProvider.fromJson(Map<String, dynamic> json) {
    return CachedProvider(
      id: json['id']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      filePath: json['filePath']?.toString() ?? '',
      downloadedAt:
          DateTime.tryParse(json['downloadedAt']?.toString() ?? '') ??
          DateTime.now(),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Result of a manifest check.
class UpdateCheckResult {
  final Manifest manifest;
  final List<ProviderInfo> available; // in manifest, not yet downloaded
  final List<ProviderInfo>
  updatesAvailable; // downloaded version < manifest version
  final List<ProviderInfo> upToDate; // downloaded version == manifest version
  final List<String> removedIds; // cached but no longer in manifest

  const UpdateCheckResult({
    required this.manifest,
    required this.available,
    required this.updatesAvailable,
    required this.upToDate,
    this.removedIds = const [],
  });

  bool get hasUpdates => updatesAvailable.isNotEmpty || available.isNotEmpty;
}
