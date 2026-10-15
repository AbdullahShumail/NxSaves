import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A JSON document on disk, written atomically (temp file + rename) so a crash mid-write never
/// corrupts the queue or library.
class JsonStore {
  JsonStore(this.file);

  final File file;
  Future<void> _pending = Future.value();

  Future<Object?> read() async {
    try {
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString());
    } catch (e) {
      debugPrint('JsonStore: could not read ${file.path}: $e');
      // Keep the unreadable file for inspection instead of silently overwriting it.
      try {
        await file.rename('${file.path}.corrupt');
      } catch (_) {}
      return null;
    }
  }

  /// Serialized writes: each call waits for the previous one.
  Future<void> write(Object? data) {
    final encoded = jsonEncode(data);
    return _pending = _pending.then((_) async {
      final tmp = File('${file.path}.tmp');
      await file.parent.create(recursive: true);
      await tmp.writeAsString(encoded, flush: true);
      await tmp.rename(file.path);
    }).catchError((Object e) {
      debugPrint('JsonStore: could not write ${file.path}: $e');
    });
  }
}
