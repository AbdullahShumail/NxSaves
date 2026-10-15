import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/errors.dart';
import '../core/models.dart';
import '../core/progress_parser.dart';
import '../services/settings.dart';
import 'engine.dart';

/// Talks to your self-hosted NxSaves server (server/nxsaves_server.py), which runs yt-dlp +
/// ffmpeg. Used on iOS (required) and optionally on Android.
class RemoteEngine implements DownloadEngine {
  RemoteEngine(this.settings);

  final Settings settings;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 30);
  final _stopped = <String>{};

  @override
  EngineKind get kind => EngineKind.remote;

  Uri _uri(String path) {
    final base = settings.serverUrl.trim();
    if (base.isEmpty) throw EngineException('Add your NxSaves server address in Settings first.');
    final normalized = base.contains('://') ? base : 'http://$base';
    final root = Uri.tryParse(normalized.endsWith('/') ? normalized : '$normalized/');
    if (root == null || root.host.isEmpty) throw EngineException('The server address in Settings is not valid.');
    return root.resolve(path);
  }

  Future<Map<String, dynamic>> _call(
    String method,
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final HttpClientResponse response;
    final String text;
    try {
      final request = await _http.openUrl(method, _uri(path)).timeout(timeout);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${settings.serverToken}');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        request.headers.contentType = ContentType.json;
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      response = await request.close().timeout(timeout);
      text = await response.transform(utf8.decoder).join().timeout(timeout);
    } on TimeoutException {
      throw EngineException("The server didn't answer in time.", detail: '$method $path timed out');
    } on SocketException catch (e) {
      throw EngineException(
        "Can't reach your NxSaves server. Check the address and that the server is running.",
        detail: '$e',
      );
    } on HandshakeException catch (e) {
      throw EngineException('Secure connection to the server failed.', detail: '$e');
    } on HttpException catch (e) {
      throw EngineException('Connection to the server was interrupted.', detail: '$e');
    }

    Object? decoded;
    try {
      decoded = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      decoded = null;
    }
    if (response.statusCode == HttpStatus.unauthorized) {
      throw EngineException('The server rejected the access token. Check it in Settings.', statusCode: 401);
    }
    if (response.statusCode >= 400) {
      final detail = decoded is Map ? '${decoded['detail'] ?? text}' : text;
      throw EngineException(friendlyError(detail), detail: detail, statusCode: response.statusCode);
    }
    if (decoded is! Map) {
      throw EngineException("That address doesn't look like an NxSaves server.", detail: text);
    }
    return Map<String, dynamic>.from(decoded);
  }

  /// Server status for "Test connection" in Settings.
  Future<Map<String, dynamic>> health() => _call('GET', 'api/health', timeout: const Duration(seconds: 10));

  @override
  Future<Map<String, dynamic>> fetchInfo(String url) =>
      _call('POST', 'api/info', body: {'url': url}, timeout: const Duration(minutes: 3));

  Future<String> _createJob(DownloadTask task) async {
    final job = await _call('POST', 'api/jobs', body: {'url': task.url, 'spec': task.spec.toJson(), 'title': task.title});
    return job['id'] as String;
  }

  @override
  Future<File> download(DownloadTask task, Directory workDir, void Function(TaskProgress) onProgress) async {
    _stopped.remove(task.id);
    await workDir.create(recursive: true);
    task.remoteJobId ??= await _createJob(task);
    onProgress(const TaskProgress(stage: 'Queued on server'));

    var recreated = false;
    var failures = 0;
    Map<String, dynamic> job;
    while (true) {
      _throwIfStopped(task);
      try {
        job = await _call('GET', 'api/jobs/${task.remoteJobId}', timeout: const Duration(seconds: 20));
        failures = 0;
      } on EngineException catch (e) {
        if (e.statusCode == 404 && !recreated) {
          // The server restarted or cleaned the job up; start it again.
          recreated = true;
          task.remoteJobId = await _createJob(task);
          continue;
        }
        // Brief network drops (switching Wi-Fi, app was suspended) shouldn't fail the download.
        if (e.statusCode == null && ++failures < 15) {
          onProgress(const TaskProgress(stage: 'Reconnecting to server…'));
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
        rethrow;
      }

      final status = job['status'];
      if (status == 'ready') break;
      if (status == 'error') {
        final detail = '${job['error'] ?? 'Unknown server error'}';
        throw EngineException(friendlyError(detail), detail: detail);
      }
      if (status == 'canceled') throw EngineException.canceled();
      onProgress(TaskProgress(
        stage: 'Server · ${job['stage'] ?? 'Working'}',
        fraction: asDouble(job['progress']),
        downloaded: asInt(job['downloaded']),
        total: asInt(job['total']),
        speed: asDouble(job['speed']),
        eta: asInt(job['eta']),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }

    final name = _safeName('${job['filename'] ?? 'download'}');
    final dest = File(p.join(workDir.path, name));
    await _transfer(task, dest, asInt(job['size']), onProgress);
    return dest;
  }

  /// Streams the finished file from the server, resuming with HTTP Range after interruptions.
  Future<void> _transfer(DownloadTask task, File dest, int? expected, void Function(TaskProgress) onProgress) async {
    final url = _uri('api/jobs/${task.remoteJobId}/file');
    var attempts = 0;
    while (true) {
      _throwIfStopped(task);
      final existing = await dest.exists() ? await dest.length() : 0;
      if (expected != null && existing == expected) return;
      IOSink? sink;
      try {
        final request = await _http.getUrl(url).timeout(const Duration(seconds: 20));
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${settings.serverToken}');
        if (existing > 0) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
        final response = await request.close().timeout(const Duration(seconds: 30));

        if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
          await response.drain<void>();
          await dest.delete();
          continue;
        }
        if (response.statusCode != HttpStatus.ok && response.statusCode != HttpStatus.partialContent) {
          final body = await response.transform(utf8.decoder).join();
          throw EngineException('The server could not send the file (HTTP ${response.statusCode}).', detail: body);
        }
        final append = response.statusCode == HttpStatus.partialContent;
        var received = append ? existing : 0;
        final total = expected ?? (response.contentLength >= 0 ? received + response.contentLength : null);
        sink = dest.openWrite(mode: append ? FileMode.append : FileMode.write);

        final watch = Stopwatch()..start();
        var lastReport = 0;
        var windowBytes = 0;
        var speed = 0.0;
        await for (final chunk in response.timeout(const Duration(seconds: 45))) {
          _throwIfStopped(task);
          sink.add(chunk);
          received += chunk.length;
          windowBytes += chunk.length;
          final elapsed = watch.elapsedMilliseconds;
          if (elapsed - lastReport >= 400) {
            speed = windowBytes * 1000 / (elapsed - lastReport);
            windowBytes = 0;
            lastReport = elapsed;
            onProgress(TaskProgress(
              stage: 'Saving to phone',
              fraction: total == null || total == 0 ? null : received / total,
              downloaded: received,
              total: total,
              speed: speed,
              eta: total == null || speed <= 0 ? null : ((total - received) / speed).round(),
            ));
          }
        }
        await sink.flush();
        await sink.close();
        sink = null;
        if (total != null && received < total) throw const SocketException('Transfer ended early');
        return;
      } on EngineException {
        await _closeQuietly(sink);
        rethrow;
      } catch (e) {
        await _closeQuietly(sink);
        if (++attempts >= 8) {
          throw EngineException('The file transfer from the server kept failing.', detail: '$e');
        }
        onProgress(const TaskProgress(stage: 'Connection lost, resuming…'));
        await Future<void>.delayed(Duration(seconds: 2 * attempts));
      }
    }
  }

  static Future<void> _closeQuietly(IOSink? sink) async {
    try {
      await sink?.close();
    } catch (_) {}
  }

  void _throwIfStopped(DownloadTask task) {
    if (_stopped.contains(task.id)) throw EngineException.canceled();
  }

  @override
  Future<void> stop(DownloadTask task) async {
    _stopped.add(task.id);
    await release(task);
  }

  @override
  Future<void> release(DownloadTask task) async {
    final id = task.remoteJobId;
    if (id == null) return;
    try {
      await _call('DELETE', 'api/jobs/$id', timeout: const Duration(seconds: 10));
    } catch (_) {
      // Best effort: the server also deletes old jobs on its own.
    }
  }

  static String _safeName(String name) {
    final cleaned = p.basename(name).replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    return cleaned.isEmpty ? 'download' : cleaned;
  }
}
