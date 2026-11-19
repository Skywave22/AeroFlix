import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Best-effort image cache statistics. CachedNetworkImage stores files in the
/// temporary directory under `libCachedImageData/`. We measure that directory
/// when possible and ignore errors.
class ImageCacheService {
  static Future<Directory> _cacheDir() async {
    final tmp = await getTemporaryDirectory();
    return Directory('${tmp.path}/libCachedImageData');
  }

  static Future<int> sizeBytes() async {
    try {
      final dir = await _cacheDir();
      if (!await dir.exists()) return 0;
      var total = 0;
      await for (final f in dir.list(recursive: true, followLinks: false)) {
        if (f is File) {
          try {
            total += await f.length();
          } catch (_) {}
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> clear() async {
    try {
      final dir = await _cacheDir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
