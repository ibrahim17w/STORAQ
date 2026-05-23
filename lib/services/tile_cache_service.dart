//tile_cache_service.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:path/path.dart' as p;

class TileCacheService {
  static String? _cacheDir;
  static const int _maxCacheSize = 1000;

  static Future<void> init() async {
    if (_cacheDir != null) return;
    final dir = await getApplicationDocumentsDirectory();
    _cacheDir = p.join(dir.path, 'map_tiles');
    final cacheDir = Directory(_cacheDir!);
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
  }

  static String _hashUrl(String url) {
    return md5.convert(utf8.encode(url)).toString();
  }

  static String _getFilePath(String url) {
    final hash = _hashUrl(url);
    return p.join(_cacheDir!, '$hash.png');
  }

  static Future<Uint8List?> getTile(String url) async {
    await init();
    final path = _getFilePath(url);
    final file = File(path);
    try {
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (_) {
      // File may be corrupt or locked; treat as missing
    }
    return null;
  }

  static Future<void> saveTile(String url, Uint8List data) async {
    await init();
    final path = _getFilePath(url);
    final file = File(path);

    try {
      // Write atomically so partial files never exist
      final tempPath = '$path.tmp';
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(data, flush: true);
      await tempFile.rename(path);
    } catch (_) {
      return;
    }

    // Defer cleanup so rapid zooms don't hammer the filesystem
    await _enforceCacheLimit();
  }

  static Future<void> _enforceCacheLimit() async {
    try {
      final dir = Directory(_cacheDir!);
      final entities = await dir.list().toList();

      final files = <File>[];
      for (final e in entities) {
        if (e is File && p.extension(e.path) == '.png') {
          files.add(e);
        }
      }

      if (files.length <= _maxCacheSize) return;

      // Safely get modified times, skipping files that disappear mid-sort
      final List<MapEntry<File, DateTime>> timed = [];
      for (final f in files) {
        try {
          final stat = await f.stat();
          timed.add(MapEntry(f, stat.modified));
        } catch (_) {
          // File deleted between list and stat; ignore
        }
      }

      timed.sort((a, b) => a.value.compareTo(b.value));

      final toDelete = (timed.length - _maxCacheSize) + 50;
      for (int i = 0; i < toDelete && i < timed.length; i++) {
        try {
          await timed[i].key.delete();
        } catch (_) {
          // Already gone
        }
      }
    } catch (_) {
      // If cleanup fails, don't crash the tile fetch
    }
  }

  static Future<void> clearCache() async {
    await init();
    final dir = Directory(_cacheDir!);
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create();
      }
    } catch (_) {}
  }

  static Future<int> getCacheSize() async {
    await init();
    final dir = Directory(_cacheDir!);
    try {
      if (!await dir.exists()) return 0;
      final entities = await dir.list().toList();
      return entities.where((e) => e is File).length;
    } catch (_) {
      return 0;
    }
  }
}
