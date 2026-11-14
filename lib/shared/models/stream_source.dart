import 'package:equatable/equatable.dart';

/// A playable stream link, mirroring Plugins-TJ's `toNuvio` output shape.
class StreamSource extends Equatable {
  final String url;
  final String name; // e.g. "Cinezo · VidNest 1080p"
  final String? quality; // "4K" | "1080p" | "720p" | "480p" | "Auto"
  final String? language; // "Hindi", "English", "Hindi + English (Multi)"
  final String? size; // "1.8GB" etc.
  final Map<String, String> headers;
  final List<SubtitleTrack> subtitles;
  final String providerId;

  const StreamSource({
    required this.url,
    required this.name,
    required this.providerId,
    this.quality,
    this.language,
    this.size,
    this.headers = const {},
    this.subtitles = const [],
  });

  StreamSource copyWith({
    String? url,
    String? name,
    String? providerId,
    String? quality,
    String? language,
    String? size,
    Map<String, String>? headers,
    List<SubtitleTrack>? subtitles,
  }) =>
      StreamSource(
        url: url ?? this.url,
        name: name ?? this.name,
        providerId: providerId ?? this.providerId,
        quality: quality ?? this.quality,
        language: language ?? this.language,
        size: size ?? this.size,
        headers: headers ?? this.headers,
        subtitles: subtitles ?? this.subtitles,
      );

  @override
  List<Object?> get props => [url, name, quality, language];
}

class SubtitleTrack extends Equatable {
  final String url;
  final String language;
  final String label;
  const SubtitleTrack(
      {required this.url, required this.language, required this.label});
  factory SubtitleTrack.fromJson(Map<String, dynamic> j) => SubtitleTrack(
        url: j['url'] as String? ?? '',
        language: (j['language'] ?? j['lang'] ?? 'Unknown') as String,
        label: (j['label'] ?? j['name'] ?? 'Subtitles') as String,
      );
  @override
  List<Object?> get props => [url, language];
}
