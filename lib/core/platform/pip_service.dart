import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Manages Android Picture-in-Picture via a platform channel.
/// On iOS / other platforms all methods gracefully no-op.
class PipService {
  static const _ch = MethodChannel('com.aeroflix.app/pip');
  bool _supported = false;
  bool _inPip = false;
  bool _enabled = false;
  final List<VoidCallback> _listeners = [];

  bool get supported => _supported;
  bool get inPip => _inPip;
  bool get enabled => _enabled;

  Future<void> init() async {
    if (!_isAndroid) return;
    try {
      _supported = await _ch.invokeMethod<bool>('isPipSupported') ?? false;
      _ch.setMethodCallHandler((call) async {
        if (call.method == 'onPipModeChanged') {
          final v = call.arguments == true;
          if (_inPip != v) {
            _inPip = v;
            for (final cb in _listeners) {
              cb();
            }
          }
        }
      });
    } catch (_) {
      _supported = false;
    }
  }

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  void addListener(VoidCallback cb) => _listeners.add(cb);
  void removeListener(VoidCallback cb) => _listeners.remove(cb);

  Future<bool> enterPip() async {
    if (!_isAndroid || !_supported || !_enabled) return false;
    try {
      return await _ch.invokeMethod<bool>('enterPip') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    if (!_isAndroid) return;
    try {
      await _ch.invokeMethod('setPipEnabled', {'enabled': v});
    } catch (_) {}
  }

  Future<void> setAutoEnterOnBackground(bool v) async {
    if (!_isAndroid || !_supported) return;
    try {
      await _ch.invokeMethod('setAutoEnterPip', {'enabled': v});
    } catch (_) {}
  }
}

final pipServiceProvider = Provider<PipService>((ref) {
  final s = PipService();
  // ignore: discarded_futures
  s.init();
  return s;
});
