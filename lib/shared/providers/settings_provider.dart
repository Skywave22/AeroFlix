import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  final bool autoPlayNext;
  final bool autoplayTrailers;
  final bool cellularAllowed;
  final bool subtitlesOnByDefault;
  final double defaultSpeed;
  const Settings({
    this.autoPlayNext = true,
    this.autoplayTrailers = true,
    this.cellularAllowed = true,
    this.subtitlesOnByDefault = false,
    this.defaultSpeed = 1.0,
  });
  Settings copyWith({
    bool? autoPlayNext,
    bool? autoplayTrailers,
    bool? cellularAllowed,
    bool? subtitlesOnByDefault,
    double? defaultSpeed,
  }) => Settings(
    autoPlayNext: autoPlayNext ?? this.autoPlayNext,
    autoplayTrailers: autoplayTrailers ?? this.autoplayTrailers,
    cellularAllowed: cellularAllowed ?? this.cellularAllowed,
    subtitlesOnByDefault: subtitlesOnByDefault ?? this.subtitlesOnByDefault,
    defaultSpeed: defaultSpeed ?? this.defaultSpeed,
  );
}

class SettingsNotifier extends StateNotifier<Settings> {
  SettingsNotifier() : super(const Settings()) {
    _ready = _load();
  }

  late final Future<void> _ready;
  static const _kAutoPlay = 'settings.autoPlayNext';
  static const _kTrailerAuto = 'settings.autoplayTrailers';
  static const _kCellular = 'settings.cellularAllowed';
  static const _kSubs = 'settings.subtitlesOnByDefault';
  static const _kSpeed = 'settings.defaultSpeed';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    state = Settings(
      autoPlayNext: p.getBool(_kAutoPlay) ?? true,
      autoplayTrailers: p.getBool(_kTrailerAuto) ?? true,
      cellularAllowed: p.getBool(_kCellular) ?? true,
      subtitlesOnByDefault: p.getBool(_kSubs) ?? false,
      defaultSpeed: p.getDouble(_kSpeed) ?? 1.0,
    );
  }

  Future<void> setAutoPlayNext(bool v) async {
    await _ready;
    state = state.copyWith(autoPlayNext: v);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAutoPlay, v);
  }

  Future<void> setAutoplayTrailers(bool v) async {
    await _ready;
    state = state.copyWith(autoplayTrailers: v);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kTrailerAuto, v);
  }

  Future<void> setCellularAllowed(bool v) async {
    await _ready;
    state = state.copyWith(cellularAllowed: v);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kCellular, v);
  }

  Future<void> setSubtitlesOnByDefault(bool v) async {
    await _ready;
    state = state.copyWith(subtitlesOnByDefault: v);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSubs, v);
  }

  Future<void> setDefaultSpeed(double v) async {
    await _ready;
    state = state.copyWith(defaultSpeed: v);
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kSpeed, v);
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, Settings>(
  (_) => SettingsNotifier(),
);
