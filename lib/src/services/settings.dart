import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';

/// User preferences, persisted with shared_preferences.
class Settings extends ChangeNotifier {
  Settings._(this._prefs);

  static Future<Settings> load() async => Settings._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  /// iOS can't run yt-dlp on the device (no subprocesses, no downloaded code), so it always uses
  /// the NxSaves server. Android can do either.
  bool get canRunLocally => Platform.isAndroid;

  EngineKind get engine => canRunLocally
      ? enumByName(EngineKind.values, _prefs.getString('engine'), EngineKind.local)
      : EngineKind.remote;
  set engine(EngineKind value) => _set('engine', value.name);

  String get serverUrl => _prefs.getString('serverUrl') ?? '';
  set serverUrl(String value) => _set('serverUrl', value.trim());

  String get serverToken => _prefs.getString('serverToken') ?? '';
  set serverToken(String value) => _set('serverToken', value.trim());

  bool get serverConfigured => serverUrl.isNotEmpty;

  /// 0 = best available.
  int get defaultHeight => _prefs.getInt('defaultHeight') ?? 1080;
  set defaultHeight(int value) => _set('defaultHeight', value);

  MediaKind get defaultKind => enumByName(MediaKind.values, _prefs.getString('defaultKind'), MediaKind.video);
  set defaultKind(MediaKind value) => _set('defaultKind', value.name);

  AudioFormat get defaultAudioFormat =>
      enumByName(AudioFormat.values, _prefs.getString('defaultAudioFormat'), AudioFormat.mp3);
  set defaultAudioFormat(AudioFormat value) => _set('defaultAudioFormat', value.name);

  bool get preferCompat => _prefs.getBool('preferCompat') ?? true;
  set preferCompat(bool value) => _set('preferCompat', value);

  int get maxConcurrent => (_prefs.getInt('maxConcurrent') ?? 2).clamp(1, 3);
  set maxConcurrent(int value) => _set('maxConcurrent', value.clamp(1, 3));

  /// iOS: also add finished videos to the Photos library.
  bool get autoSaveToPhotos => _prefs.getBool('autoSaveToPhotos') ?? true;
  set autoSaveToPhotos(bool value) => _set('autoSaveToPhotos', value);

  bool get autoUpdateYtDlp => _prefs.getBool('autoUpdateYtDlp') ?? true;
  set autoUpdateYtDlp(bool value) => _set('autoUpdateYtDlp', value);

  /// 'stable' or 'nightly'.
  String get updateChannel => _prefs.getString('updateChannel') ?? 'stable';
  set updateChannel(String value) => _set('updateChannel', value);

  DateTime? get lastUpdateCheck {
    final ms = _prefs.getInt('lastUpdateCheck');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  set lastUpdateCheck(DateTime? value) => value == null
      ? _remove('lastUpdateCheck')
      : _set('lastUpdateCheck', value.millisecondsSinceEpoch);

  /// Android, on-device engine: cookies.txt imported into app storage.
  String? get cookiesPath => _prefs.getString('cookiesPath');
  set cookiesPath(String? value) => value == null ? _remove('cookiesPath') : _set('cookiesPath', value);

  bool get askedNotifications => _prefs.getBool('askedNotifications') ?? false;
  set askedNotifications(bool value) => _set('askedNotifications', value);

  void _set(String key, Object value) {
    switch (value) {
      case String v:
        _prefs.setString(key, v);
      case int v:
        _prefs.setInt(key, v);
      case bool v:
        _prefs.setBool(key, v);
    }
    notifyListeners();
  }

  void _remove(String key) {
    _prefs.remove(key);
    notifyListeners();
  }
}
