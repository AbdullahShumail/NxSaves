import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../core/progress_parser.dart';

abstract class DownloadEngine {
  EngineKind get kind;

  /// yt-dlp metadata (`-J`) for a link.
  Future<Map<String, dynamic>> fetchInfo(String url);

  /// Downloads [task] into [workDir] and returns the finished media file.
  /// Throws [EngineException] (with `canceled: true` after [stop]).
  Future<File> download(DownloadTask task, Directory workDir, void Function(TaskProgress) onProgress);

  /// Stops a running download. The on-device engine keeps partial data so it can resume.
  Future<void> stop(DownloadTask task);

  /// Called once the file was saved, or the task was removed (deletes any server-side copy).
  Future<void> release(DownloadTask task);
}

const _sidecarExtensions = {
  '.part', '.ytdl', '.temp', '.tmp', '.jpg', '.jpeg', '.png', '.webp', '.json', '.description', //
  '.vtt', '.srt', '.ass', '.lrc', '.txt',
};

/// After a successful yt-dlp run the work folder holds the final file (intermediate streams are
/// deleted after merging); pick the largest media file and ignore partials and sidecars.
File? findOutputFile(Directory dir) {
  if (!dir.existsSync()) return null;
  final files = dir.listSync().whereType<File>().where((f) {
    final name = p.basename(f.path).toLowerCase();
    if (name.contains('.part-frag') || name.startsWith('.')) return false;
    return !_sidecarExtensions.contains(p.extension(name));
  }).toList()
    ..sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
  return files.isEmpty ? null : files.first;
}
