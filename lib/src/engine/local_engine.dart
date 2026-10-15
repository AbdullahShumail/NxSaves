import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/errors.dart';
import '../core/models.dart';
import '../core/progress_parser.dart';
import '../core/ytdlp_args.dart';
import '../services/settings.dart';
import 'engine.dart';

enum LocalEngineState { starting, ready, updating, failed }

class LocalEngineStatus {
  const LocalEngineStatus(this.state, {this.version, this.message});

  final LocalEngineState state;
  final String? version;
  final String? message;
}

/// Android: real yt-dlp running on the phone through youtubedl-android (Kotlin side:
/// android/app/src/main/kotlin/com/nxsaves/app/YtDlpBridge.kt).
class LocalEngine implements DownloadEngine {
  LocalEngine(this.settings);

  static const _method = MethodChannel('nxsaves/ytdlp');
  static const _events = EventChannel('nxsaves/ytdlp/events');

  final Settings settings;
  final status = ValueNotifier(const LocalEngineStatus(LocalEngineState.starting));
  final _runs = <String, _LocalRun>{};
  final _ready = Completer<void>();
  StreamSubscription<dynamic>? _subscription;
  int _infoSeq = 0;
  String? _activeInfoRequest;

  @override
  EngineKind get kind => EngineKind.local;

  Future<void> start() async {
    _subscription ??= _events.receiveBroadcastStream().listen(_onEvent);
    try {
      final result = await _method.invokeMapMethod<String, dynamic>('init');
      status.value = LocalEngineStatus(LocalEngineState.ready, version: result?['version'] as String?);
      if (!_ready.isCompleted) _ready.complete();
    } on PlatformException catch (e) {
      status.value = LocalEngineStatus(LocalEngineState.failed, message: e.message);
      if (!_ready.isCompleted) {
        _ready.completeError(EngineException('The download engine failed to start.', detail: e.message));
      }
    }
  }

  Future<void> _awaitReady() => _ready.future;

  /// Downloads the newest yt-dlp release (sites change often; updates fix most breakages).
  /// Returns 'updated' or 'up_to_date'.
  Future<String> update() async {
    await _awaitReady();
    final previous = status.value;
    status.value = LocalEngineStatus(LocalEngineState.updating, version: previous.version);
    try {
      final result = await _method.invokeMapMethod<String, dynamic>('update', {'channel': settings.updateChannel});
      settings.lastUpdateCheck = DateTime.now();
      status.value = LocalEngineStatus(LocalEngineState.ready, version: result?['version'] as String? ?? previous.version);
      return result?['status'] as String? ?? 'up_to_date';
    } on PlatformException catch (e) {
      status.value = LocalEngineStatus(LocalEngineState.ready, version: previous.version);
      throw EngineException(friendlyError(e.message), detail: e.message);
    }
  }

  @override
  Future<Map<String, dynamic>> fetchInfo(String url) async {
    await _awaitReady();
    final requestId = 'info-${_infoSeq++}';
    _activeInfoRequest = requestId;
    try {
      final out = await _method.invokeMethod<String>('getInfo', {
        'url': url,
        'requestId': requestId,
        'args': cookieArgs(_cookies),
      });
      if (out == null || out.trim().isEmpty) throw EngineException('yt-dlp returned no information for this link.');
      return await compute(_decodeInfo, out);
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') throw EngineException.canceled();
      throw EngineException(friendlyError(e.message), detail: e.message);
    } on FormatException catch (e) {
      throw EngineException('Could not read the information yt-dlp returned.', detail: '$e');
    } finally {
      if (_activeInfoRequest == requestId) _activeInfoRequest = null;
    }
  }

  /// Aborts a running [fetchInfo] (e.g. the user pasted another link).
  Future<void> cancelInfo() async {
    final id = _activeInfoRequest;
    if (id != null) await _method.invokeMethod('cancel', {'id': id});
  }

  String? get _cookies {
    final path = settings.cookiesPath;
    return path != null && File(path).existsSync() ? path : null;
  }

  @override
  Future<File> download(DownloadTask task, Directory workDir, void Function(TaskProgress) onProgress) async {
    await _awaitReady();
    await workDir.create(recursive: true);
    final run = _LocalRun(onProgress);
    _runs[task.id] = run;
    try {
      await _method.invokeMethod('start', {
        'taskId': task.id,
        'url': task.url,
        'args': buildDownloadArgs(task.spec, outputDir: workDir.path, cookiesFile: _cookies),
      });
      await run.done.future;
    } on PlatformException catch (e) {
      throw EngineException(friendlyError(e.message), detail: e.message);
    } finally {
      _runs.remove(task.id);
    }
    final file = findOutputFile(workDir);
    if (file == null) {
      throw EngineException('yt-dlp finished but no file was produced.', detail: run.parser.lastError);
    }
    return file;
  }

  @override
  Future<void> stop(DownloadTask task) async {
    await _method.invokeMethod('cancel', {'id': task.id});
  }

  @override
  Future<void> release(DownloadTask task) async {}

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;
    final run = _runs[raw['taskId']];
    if (run == null) return;
    switch (raw['type']) {
      case 'line':
        final progress = run.parser.feed('${raw['line']}');
        if (progress != null) run.onProgress(progress);
      case 'done':
        if (!run.done.isCompleted) run.done.complete();
      case 'canceled':
        if (!run.done.isCompleted) run.done.completeError(EngineException.canceled());
      case 'error':
        final message = '${raw['message'] ?? ''}';
        if (!run.done.isCompleted) {
          run.done.completeError(EngineException(friendlyError(message), detail: message));
        }
    }
  }
}

class _LocalRun {
  _LocalRun(this.onProgress);

  final void Function(TaskProgress) onProgress;
  final parser = YtDlpProgressParser();
  final done = Completer<void>();
}

Map<String, dynamic> _decodeInfo(String out) {
  // -J prints one JSON document; warnings go to stderr, but be tolerant of stray lines.
  final start = out.indexOf('{');
  final end = out.lastIndexOf('}');
  if (start < 0 || end < start) throw const FormatException('No JSON in yt-dlp output');
  return Map<String, dynamic>.from(jsonDecode(out.substring(start, end + 1)) as Map);
}
