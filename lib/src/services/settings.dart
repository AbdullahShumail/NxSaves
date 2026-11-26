import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';

/// User preferences, persisted with shared_preferences.
class Settings extends ChangeNotifier {
  Settings._(this._prefs);

  static Future<Settings> load() async => Settings._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  /// Android downloads on the phone. iOS can't run the downloader itself (no helper processes,
  /// no downloaded code), so it always goes through the NxSaves server.
  bool get canRunLocally => Platform.isAndroid;

  /// Tests can force an engine; the app itself never changes it.
  EngineKind? engineOverride;

  EngineKind get engine => engineOverride ?? (canRunLocally ? EngineKind.local : EngineKind.remote);

  String get serverUrl => _prefs.getString('serverUrl') ?? '';
  set serverUrl(String value) => _set('serverUrl', value.trim());

  String get serverToken => _prefs.getString('serverToken') ?? '';
  set serverToken(String value) => _set('serverToken', value.trim());

  bool get serverConfigured => serverUrl.isNotEmpty;

  /// The last quality picked, offered first next time. 0 = best available.
  int get defaultHeight => _prefs.getInt('defaultHeight') ?? 1080;
  set defaultHeight(int value) => _set('defaultHeight', value);

  MediaKind get defaultKind => enumByName(MediaKind.values, _prefs.getString('defaultKind'), MediaKind.video);
  set defaultKind(MediaKind value) => _set('defaultKind', value.name);

  AudioFormat get defaultAudioFormat =>
      enumByName(AudioFormat.values, _prefs.getString('defaultAudioFormat'), AudioFormat.mp3);
  set defaultAudioFormat(AudioFormat value) => _set('defaultAudioFormat', value.name);

  int get maxConcurrent => 2;

  /// iOS: also add finished videos to the Photos library.
  bool get autoSaveToPhotos => _prefs.getBool('autoSaveToPhotos') ?? true;
  set autoSaveToPhotos(bool value) => _set('autoSaveToPhotos', value);

  DateTime? get lastUpdateCheck {
    final ms = _prefs.getInt('lastUpdateCheck');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  set lastUpdateCheck(DateTime? value) => value == null
      ? _remove('lastUpdateCheck')
      : _set('lastUpdateCheck', value.millisecondsSinceEpoch);

  /// Android: cookies.txt imported into app storage, for posts that need a signed-in account.
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
