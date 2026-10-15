import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// App directories, resolved once at startup.
class AppPaths {
  AppPaths._(this.support, this.documents);

  static Future<AppPaths> resolve() async {
    final support = await getApplicationSupportDirectory();
    final documents = await getApplicationDocumentsDirectory();
    final paths = AppPaths._(support, documents);
    await Future.wait([paths.work.create(recursive: true), paths.thumbs.create(recursive: true)]);
    return paths;
  }

  /// Private app data (queue, library index, thumbnails, in-progress downloads).
  final Directory support;

  /// iOS: shown in the Files app ("On My iPhone › NxSaves"), where finished downloads live.
  final Directory documents;

  Directory get work => Directory(p.join(support.path, 'work'));
  Directory get thumbs => Directory(p.join(support.path, 'thumbs'));
  File get queueFile => File(p.join(support.path, 'queue.json'));
  File get libraryFile => File(p.join(support.path, 'library.json'));

  Directory workDirFor(String taskId) => Directory(p.join(work.path, taskId));
}
