import 'dart:async';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Initializes sqflite FFI after the first frame so [runApp] is not blocked.
class DesktopDbInit {
  DesktopDbInit._();

  static Completer<void>? _completer;
  static bool _done = false;

  static Future<void> ensureInitialized() {
    if (!Platform.isWindows && !Platform.isLinux) {
      return Future.value();
    }
    if (_done) return Future.value();
    _completer ??= Completer<void>();
    if (!_completer!.isCompleted) {
      scheduleMicrotask(() {
        try {
          sqfliteFfiInit();
          databaseFactory = databaseFactoryFfi;
          _done = true;
          _completer!.complete();
        } catch (e, st) {
          _completer!.completeError(e, st);
        }
      });
    }
    return _completer!.future;
  }
}
