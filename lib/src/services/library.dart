import 'dart:async';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../core/errors.dart';
import '../core/models.dart';
import 'android_platform.dart';
import 'app_paths.dart';
import 'json_store.dart';
import 'settings.dart';

const _audioExtensions = {'mp3', 'm4a', 'aac', 'opus', 'ogg', 'oga', 'flac', 'wav', 'weba', 'mka', 'alac'};

const _mimeByExtension = {
  'mp4': 'video/mp4',
  'm4v': 'video/mp4',
  'webm': 'video/webm',
  'mkv': 'video/x-matroska',
  'mov': 'video/quicktime',
  'flv': 'video/x-flv',
  '3gp': 'video/3gpp',
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'opus': 'audio/ogg',
  'ogg': 'audio/ogg',
  'flac': 'audio/flac',
  'wav': 'audio/wav',
};

/// Finished downloads: saving them where the user can find them, and managing them afterwards.
///
/// * Android: copied into shared storage (Movies/NxSaves, Music/NxSaves) via MediaStore.
/// * iOS: moved into the app's Documents (visible in Files › On My iPhone › NxSaves), and videos
///   optionally added to Photos.
class Library extends ChangeNotifier {
  Library({required this.paths, required this.settings, this.android});

  final AppPaths paths;
  final Settings settings;
  final AndroidPlatform? android;
  late final JsonStore _store = JsonStore(paths.libraryFile);
  final List<LibraryItem> _items = [];
  int? _sdkInt;

  List<LibraryItem> get items => List.unmodifiable(_items);

  Future<void> load() async {
    final data = await _store.read();
    if (data is List) {
      for (final raw in data) {
        try {
          _items.add(LibraryItem.fromJson(Map<String, dynamic>.from(raw as Map)));
        } catch (e) {
          debugPrint('Skipping unreadable library entry: $e');
        }
      }
    }
    _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _sdkInt = await android?.sdkInt();
    notifyListeners();
    unawaited(refreshAvailability());
  }

  /// Flags items whose files were deleted outside the app (e.g. from the gallery).
  Future<void> refreshAvailability() async {
    if (_items.isEmpty) return;
    final snapshot = List.of(_items);
    List<bool> exists;
    if (android != null) {
      exists = await android!.exists([for (final i in snapshot) (uri: i.contentUri, path: i.filePath)]);
    } else {
      exists = [for (final i in snapshot) absolutePath(i) != null && File(absolutePath(i)!).existsSync()];
    }
    var changed = false;
    for (var i = 0; i < snapshot.length && i < exists.length; i++) {
      if (snapshot[i].missing != !exists[i]) {
        snapshot[i].missing = !exists[i];
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// Decided by the file actually produced (a "video" link can turn out to be audio-only).
  static MediaKind kindOf(File file) {
    final ext = p.extension(file.path).replaceFirst('.', '').toLowerCase();
    return _audioExtensions.contains(ext) ? MediaKind.audio : MediaKind.video;
  }

  /// Moves a finished download into user-visible storage and records it.
  Future<LibraryItem> addDownload(DownloadTask task, File file) async {
    final kind = kindOf(file);
    final fileName = p.basename(file.path);
    final ext = p.extension(fileName).replaceFirst('.', '').toLowerCase();
    final size = await file.length();
    final id = task.id;
    final thumbnailFile = await _saveThumbnail(id, task.thumbnail);

    String? filePath;
    String? contentUri;
    var mime = _mimeByExtension[ext] ?? (kind == MediaKind.audio ? 'audio/*' : 'video/*');
    var savedToPhotos = false;

    if (android != null) {
      if ((_sdkInt ?? 99) < 29 && !await android!.requestLegacyStoragePermission()) {
        throw EngineException('NxSaves needs storage permission to save into your gallery.');
      }
      try {
        final saved = await android!.saveToPublic(path: file.path, kind: kind.name, name: fileName);
        filePath = saved['path'] as String?;
        contentUri = saved['uri'] as String?;
        mime = saved['mime'] as String? ?? mime;
      } catch (e) {
        throw EngineException('Could not save the file to your phone storage.', detail: '$e');
      }
      await _deleteQuietly(file);
    } else {
      final folder = Directory(p.join(paths.documents.path, kind == MediaKind.audio ? 'Audio' : 'Videos'));
      await folder.create(recursive: true);
      final dest = _uniqueFile(folder, fileName);
      try {
        await file.rename(dest.path);
      } on FileSystemException {
        await file.copy(dest.path);
        await _deleteQuietly(file);
      }
      filePath = p.relative(dest.path, from: paths.documents.path);
      if (kind == MediaKind.video && settings.autoSaveToPhotos) {
        savedToPhotos = await _addToPhotos(dest.path) == null;
      }
    }

    final item = LibraryItem(
      id: id,
      title: task.title,
      sourceUrl: task.url,
      kind: kind,
      fileName: fileName,
      mime: mime,
      sizeBytes: size,
      createdAt: DateTime.now(),
      uploader: task.uploader,
      extractor: task.extractor,
      duration: task.duration,
      filePath: filePath,
      contentUri: contentUri,
      thumbnailFile: thumbnailFile,
      savedToPhotos: savedToPhotos,
    );
    _items.insert(0, item);
    notifyListeners();
    await _persist();
    return item;
  }

  String? absolutePath(LibraryItem item) {
    final path = item.filePath;
    if (path == null) return null;
    return Platform.isIOS ? p.join(paths.documents.path, path) : path;
  }

  File? thumbnailOf(LibraryItem item) =>
      item.thumbnailFile == null ? null : File(p.join(paths.thumbs.path, item.thumbnailFile!));

  /// Returns an error message, or null on success.
  Future<String?> open(LibraryItem item) async {
    if (android != null) {
      final ok = await android!.open(uri: item.contentUri, path: item.filePath, mime: item.mime);
      return ok ? null : 'No app found to open this file.';
    }
    final path = absolutePath(item);
    if (path == null || !File(path).existsSync()) return 'The file no longer exists.';
    final result = await OpenFilex.open(path);
    return result.type == ResultType.done ? null : result.message;
  }

  Future<String?> share(LibraryItem item, {Rect? origin}) async {
    if (android != null) {
      final ok = await android!.share(uri: item.contentUri, path: item.filePath, mime: item.mime);
      return ok ? null : 'Sharing is not available.';
    }
    final path = absolutePath(item);
    if (path == null || !File(path).existsSync()) return 'The file no longer exists.';
    await SharePlus.instance.share(ShareParams(
      files: [XFile(path, mimeType: item.mime)],
      sharePositionOrigin: origin,
    ));
    return null;
  }

  /// iOS: add a video to the Photos library.
  Future<String?> saveToPhotos(LibraryItem item) async {
    final path = absolutePath(item);
    if (path == null || !File(path).existsSync()) return 'The file no longer exists.';
    final error = await _addToPhotos(path);
    if (error == null) {
      item.savedToPhotos = true;
      notifyListeners();
      await _persist();
    }
    return error;
  }

  Future<String?> _addToPhotos(String path) async {
    try {
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
        return 'Allow NxSaves to add to Photos in iOS Settings.';
      }
      await Gal.putVideo(path);
      return null;
    } on GalException catch (e) {
      return e.type == GalExceptionType.notSupportedFormat
          ? 'Photos does not support this video format (kept in Files).'
          : e.type.message;
    }
  }

  /// Removes the item; with [deleteFile] also deletes the saved file.
  Future<String?> remove(LibraryItem item, {required bool deleteFile}) async {
    if (deleteFile) {
      if (android != null) {
        final ok = await android!.delete(uri: item.contentUri, path: item.filePath);
        if (!ok) return 'Could not delete this file (it may belong to an older install). Delete it from your gallery.';
      } else {
        final path = absolutePath(item);
        if (path != null) await _deleteQuietly(File(path));
      }
    }
    final thumb = thumbnailOf(item);
    if (thumb != null) await _deleteQuietly(thumb);
    _items.removeWhere((i) => i.id == item.id);
    notifyListeners();
    await _persist();
    return null;
  }

  Future<void> _persist() => _store.write([for (final i in _items) i.toJson()]);

  /// Thumbnail URLs (TikTok/Instagram especially) expire quickly, so keep a local copy.
  Future<String?> _saveThumbnail(String id, String? url) async {
    if (url == null || !url.startsWith('http')) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 10));
      final response = await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      final name = '$id.thumb';
      final file = File(p.join(paths.thumbs.path, name));
      await response.pipe(file.openWrite()).timeout(const Duration(seconds: 20));
      return name;
    } catch (e) {
      debugPrint('Thumbnail download failed: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static File _uniqueFile(Directory dir, String name) {
    var candidate = File(p.join(dir.path, name));
    final base = p.basenameWithoutExtension(name);
    final ext = p.extension(name);
    var n = 1;
    while (candidate.existsSync()) {
      candidate = File(p.join(dir.path, '$base ($n)$ext'));
      n++;
    }
    return candidate;
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
