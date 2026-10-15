import 'dart:async';

import 'package:flutter/services.dart';

/// Wrapper for the Android-only channel implemented in PlatformBridge.kt.
class AndroidPlatform {
  AndroidPlatform() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShared' && call.arguments is String) {
        _shared.add(call.arguments as String);
      }
      return null;
    });
  }

  static const _channel = MethodChannel('nxsaves/platform');
  final _shared = StreamController<String>.broadcast();

  /// Text shared to NxSaves from other apps while it is running.
  Stream<String> get sharedText => _shared.stream;

  /// Text shared before Flutter was ready (cold start from the share sheet).
  Future<String?> takePendingShare() => _channel.invokeMethod<String>('takePendingShare');

  Future<int> sdkInt() async => await _channel.invokeMethod<int>('sdkInt') ?? 0;

  Future<Map<String, dynamic>> saveToPublic({required String path, required String kind, required String name}) async =>
      Map<String, dynamic>.from(
        await _channel.invokeMethod<Map>('saveToPublic', {'path': path, 'kind': kind, 'name': name}) ?? const {},
      );

  Future<bool> open({String? uri, String? path, required String mime}) async =>
      await _channel.invokeMethod<bool>('open', {'uri': uri, 'path': path, 'mime': mime}) ?? false;

  Future<bool> share({String? uri, String? path, required String mime}) async =>
      await _channel.invokeMethod<bool>('share', {'uri': uri, 'path': path, 'mime': mime}) ?? false;

  Future<bool> delete({String? uri, String? path}) async =>
      await _channel.invokeMethod<bool>('delete', {'uri': uri, 'path': path}) ?? false;

  Future<List<bool>> exists(List<({String? uri, String? path})> items) async {
    final result = await _channel.invokeListMethod<bool>('exists', {
      'items': [
        for (final item in items) {'uri': item.uri, 'path': item.path},
      ],
    });
    return result ?? List.filled(items.length, true);
  }

  Future<bool> requestNotificationPermission() async =>
      await _channel.invokeMethod<bool>('requestNotificationPermission') ?? false;

  Future<bool> requestLegacyStoragePermission() async =>
      await _channel.invokeMethod<bool>('requestLegacyStoragePermission') ?? false;

  Future<void> setServiceState({required int active, required String title, required String text, required int progress}) =>
      _channel.invokeMethod('setServiceState', {'active': active, 'title': title, 'text': text, 'progress': progress});

  Future<void> moveToBackground() => _channel.invokeMethod('moveToBackground');

  /// Lets the user pick a cookies.txt; returns its private copy's path (null if canceled).
  Future<String?> importCookies() => _channel.invokeMethod<String>('importCookies');
}
