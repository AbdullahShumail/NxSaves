import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/errors.dart';
import '../core/models.dart';
import '../core/progress_parser.dart';
import '../engine/engine.dart';
import '../engine/local_engine.dart';
import '../engine/remote_engine.dart';
import 'android_platform.dart';
import 'app_paths.dart';
import 'json_store.dart';
import 'library.dart';
import 'settings.dart';

/// The download queue: runs up to [Settings.maxConcurrent] tasks, persists itself across app
/// restarts (interrupted downloads resume), and hands finished files to the [Library].
class DownloadManager extends ChangeNotifier {
  DownloadManager({
    required this.settings,
    required this.paths,
    required this.library,
    required this.remote,
    this.local,
    this.android,
  });

  final Settings settings;
  final AppPaths paths;
  final Library library;
  final LocalEngine? local;
  final RemoteEngine remote;
  final AndroidPlatform? android;

  late final JsonStore _store = JsonStore(paths.queueFile);
  final List<DownloadTask> _tasks = [];
  final Set<String> _running = {};
  final Set<String> _removing = {};
  final Set<String> _saving = {};
  final _completed = StreamController<LibraryItem>.broadcast();
  final _random = Random();
  Timer? _notifyTimer;
  Timer? _persistTimer;
  DateTime _lastServiceSync = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPersist = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastServiceActive = -1;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  /// Emits every download that finished and was saved.
  Stream<LibraryItem> get completed => _completed.stream;

  int get activeCount => _tasks.where((t) => t.isActive).length;

  bool isSaving(DownloadTask task) => _saving.contains(task.id);

  bool canPause(DownloadTask task) =>
      task.engine == EngineKind.local && task.isActive && !_saving.contains(task.id);

  Future<void> load() async {
    final data = await _store.read();
    if (data is List) {
      for (final raw in data) {
        try {
          final task = DownloadTask.fromJson(Map<String, dynamic>.from(raw as Map));
          // Downloads interrupted by the app being closed restart (yt-dlp resumes .part files).
          if (task.status == TaskStatus.running) task.status = TaskStatus.queued;
          task.stage = _idleStage(task);
          _tasks.add(task);
        } catch (e) {
          debugPrint('Skipping unreadable queue entry: $e');
        }
      }
    }
    await _removeOrphanWorkDirs();
    settings.addListener(_pump);
    notifyListeners();
    _pump();
  }

  DownloadEngine _engineFor(DownloadTask task) =>
      task.engine == EngineKind.local && local != null ? local! : remote;

  DownloadEngine get currentEngine => settings.engine == EngineKind.local && local != null ? local! : remote;

  DownloadTask enqueue({
    required String url,
    required String title,
    required DownloadSpec spec,
    String? thumbnail,
    String? uploader,
    double? duration,
    String? extractor,
  }) {
    final task = DownloadTask(
      id: _newId(),
      url: url,
      title: title,
      spec: spec,
      engine: settings.engine,
      createdAt: DateTime.now(),
      thumbnail: thumbnail,
      uploader: uploader,
      duration: duration,
      extractor: extractor,
    );
    _tasks.add(task);
    _changed(immediate: true, persist: true);
    _askForNotificationsOnce();
    _pump();
    return task;
  }

  Future<void> pause(DownloadTask task) async {
    if (!canPause(task)) return;
    if (task.status == TaskStatus.queued) {
      task.status = TaskStatus.paused;
      task.stage = 'Paused';
      _changed(immediate: true, persist: true);
      return;
    }
    task.status = TaskStatus.paused;
    task.stage = 'Pausing…';
    _changed(immediate: true, persist: true);
    await _engineFor(task).stop(task);
  }

  void resume(DownloadTask task) {
    if (task.status != TaskStatus.paused && task.status != TaskStatus.failed) return;
    task.status = TaskStatus.queued;
    task.stage = 'Waiting…';
    task.error = null;
    task.errorDetail = null;
    _changed(immediate: true, persist: true);
    _pump();
  }

  void retry(DownloadTask task) {
    // A failed server job is gone for good; ask the server for a fresh one.
    if (task.engine == EngineKind.remote && task.status == TaskStatus.failed) task.remoteJobId = null;
    resume(task);
  }

  Future<void> remove(DownloadTask task) async {
    if (_running.contains(task.id)) {
      _removing.add(task.id);
      task.stage = 'Removing…';
      _changed(immediate: true);
      await _engineFor(task).stop(task);
      return;
    }
    _tasks.remove(task);
    _changed(immediate: true, persist: true);
    await _engineFor(task).release(task);
    await _deleteDir(paths.workDirFor(task.id));
  }

  Future<void> clearFailed() async {
    for (final task in _tasks.where((t) => t.status == TaskStatus.failed).toList()) {
      await remove(task);
    }
  }

  void _pump() {
    final limit = settings.maxConcurrent;
    for (final task in List.of(_tasks)) {
      if (_running.length >= limit) break;
      if (task.status == TaskStatus.queued && !_running.contains(task.id)) unawaited(_run(task));
    }
    _syncService(force: true);
  }

  Future<void> _run(DownloadTask task) async {
    _running.add(task.id);
    task
      ..status = TaskStatus.running
      ..stage = 'Starting…'
      ..error = null
      ..errorDetail = null
      ..clearProgress();
    _changed(immediate: true, persist: true);

    final engine = _engineFor(task);
    final workDir = paths.workDirFor(task.id);
    try {
      final file = await engine.download(task, workDir, (progress) => _onProgress(task, progress));
      if (_removing.contains(task.id)) throw EngineException.canceled();
      _saving.add(task.id);
      task
        ..stage = 'Saving…'
        ..clearProgress();
      _changed(immediate: true);
      final item = await library.addDownload(task, file);
      _tasks.remove(task);
      _completed.add(item);
      unawaited(engine.release(task));
      unawaited(_deleteDir(workDir));
    } catch (error, stack) {
      if (_removing.remove(task.id)) {
        _tasks.remove(task);
        unawaited(engine.release(task));
        unawaited(_deleteDir(workDir));
      } else if (error is EngineException && error.canceled) {
        task
          ..status = TaskStatus.paused
          ..stage = 'Paused';
      } else {
        task
          ..status = TaskStatus.failed
          ..stage = 'Failed'
          ..error = error is EngineException ? error.message : 'Unexpected error: $error'
          ..errorDetail = error is EngineException ? error.detail : '$error\n$stack';
      }
    } finally {
      if (task.status == TaskStatus.paused) {
        // Keep how far it got so the paused card still shows it.
        task
          ..speed = null
          ..eta = null;
      } else {
        task.clearProgress();
      }
      _saving.remove(task.id);
      _running.remove(task.id);
      _changed(immediate: true, persist: true);
      _pump();
    }
  }

  void _onProgress(DownloadTask task, TaskProgress progress) {
    if (task.status != TaskStatus.running || _removing.contains(task.id)) return;
    task
      ..stage = progress.stage
      ..progress = progress.fraction
      ..downloadedBytes = progress.downloaded
      ..totalBytes = progress.total
      ..speed = progress.speed
      ..eta = progress.eta;
    // Persist now and then so a server job id survives the app being killed.
    final persist = DateTime.now().difference(_lastPersist) > const Duration(seconds: 10);
    _changed(persist: persist);
  }

  void _changed({bool immediate = false, bool persist = false}) {
    if (persist) {
      _lastPersist = DateTime.now();
      _persistTimer?.cancel();
      _persistTimer = Timer(const Duration(milliseconds: 300), () {
        _store.write([for (final t in _tasks) t.toJson()]);
      });
    }
    if (immediate) {
      _notifyTimer?.cancel();
      _notifyTimer = null;
      notifyListeners();
      _syncService(force: true);
      return;
    }
    _notifyTimer ??= Timer(const Duration(milliseconds: 250), () {
      _notifyTimer = null;
      notifyListeners();
      _syncService();
    });
  }

  /// Android: keeps the foreground service (and its notification) in step with the queue.
  void _syncService({bool force = false}) {
    final platform = android;
    if (platform == null) return;
    final active = _tasks.where((t) => t.isActive).toList();
    final now = DateTime.now();
    if (!force && now.difference(_lastServiceSync) < const Duration(seconds: 1)) return;
    if (active.isEmpty && _lastServiceActive == 0) return;
    _lastServiceSync = now;
    _lastServiceActive = active.length;

    final running = active.where((t) => t.status == TaskStatus.running).toList();
    final fractions = running.map((t) => t.progress).whereType<double>().toList();
    final progress = running.isNotEmpty && fractions.length == running.length
        ? (fractions.reduce((a, b) => a + b) / fractions.length * 100).round()
        : -1;
    final title = running.isEmpty
        ? '${active.length} download${active.length == 1 ? '' : 's'} waiting'
        : running.length == 1
            ? running.first.title
            : 'Downloading ${running.length} of ${active.length}';
    final text = running.isEmpty ? 'Waiting to start' : running.first.stage;
    unawaited(platform
        .setServiceState(active: active.length, title: title, text: text, progress: progress)
        .catchError((Object e) => debugPrint('Service update failed: $e')));
  }

  void _askForNotificationsOnce() {
    if (android == null || settings.askedNotifications) return;
    settings.askedNotifications = true;
    unawaited(android!.requestNotificationPermission().catchError((Object _) => false));
  }

  String _idleStage(DownloadTask task) => switch (task.status) {
        TaskStatus.paused => 'Paused',
        TaskStatus.failed => 'Failed',
        _ => 'Waiting…',
      };

  String _newId() =>
      '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_random.nextInt(1 << 32).toRadixString(36)}';

  Future<void> _removeOrphanWorkDirs() async {
    final known = _tasks.map((t) => t.id).toSet();
    try {
      await for (final entry in paths.work.list()) {
        if (entry is Directory && !known.contains(p.basename(entry.path))) {
          await _deleteDir(entry);
        }
      }
    } catch (e) {
      debugPrint('Work folder cleanup failed: $e');
    }
  }

  static Future<void> _deleteDir(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('Could not delete ${dir.path}: $e');
    }
  }

  @override
  void dispose() {
    settings.removeListener(_pump);
    _notifyTimer?.cancel();
    _persistTimer?.cancel();
    _completed.close();
    super.dispose();
  }
}
