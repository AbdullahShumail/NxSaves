import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../engine/local_engine.dart';
import '../engine/remote_engine.dart';
import 'android_platform.dart';
import 'app_paths.dart';
import 'download_manager.dart';
import 'library.dart';
import 'settings.dart';

/// Everything the UI needs, created once at startup.
class AppServices {
  AppServices._({
    required this.settings,
    required this.paths,
    required this.library,
    required this.downloads,
    required this.remote,
    this.local,
    this.android,
  });

  static Future<AppServices> create() async {
    final settings = await Settings.load();
    final paths = await AppPaths.resolve();
    final android = Platform.isAndroid ? AndroidPlatform() : null;
    final local = Platform.isAndroid ? LocalEngine(settings) : null;
    final remote = RemoteEngine(settings);
    final library = Library(paths: paths, settings: settings, android: android);
    final downloads = DownloadManager(
      settings: settings,
      paths: paths,
      library: library,
      remote: remote,
      local: local,
      android: android,
    );
    final services = AppServices._(
      settings: settings,
      paths: paths,
      library: library,
      downloads: downloads,
      remote: remote,
      local: local,
      android: android,
    );
    await library.load();
    await downloads.load();
    if (local != null) unawaited(services._startLocalEngine(local, settings));
    return services;
  }

  final Settings settings;
  final AppPaths paths;
  final Library library;
  final DownloadManager downloads;
  final RemoteEngine remote;
  final LocalEngine? local;
  final AndroidPlatform? android;

  Future<void> _startLocalEngine(LocalEngine engine, Settings settings) async {
    await engine.start();
    // yt-dlp ships fixes for site changes every few weeks; keep it fresh automatically.
    final last = settings.lastUpdateCheck;
    final due = last == null || DateTime.now().difference(last) > const Duration(hours: 24);
    if (settings.autoUpdateYtDlp && due && engine.status.value.state == LocalEngineState.ready) {
      try {
        await engine.update();
      } catch (e) {
        debugPrint('Automatic yt-dlp update failed: $e');
      }
    }
  }
}

/// Makes [AppServices] available to the widget tree.
class Services extends InheritedWidget {
  const Services({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Services>()!.services;

  @override
  bool updateShouldNotify(Services oldWidget) => oldWidget.services != services;
}
