import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nxsaves/main.dart';
import 'package:nxsaves/src/core/models.dart';
import 'package:nxsaves/src/services/app_services.dart';

/// End to end through the real UI: paste a link, let an NxSaves server read and download it, and
/// check the finished file landed in the library (Documents on iOS, shared storage on Android).
/// This is the path the iPhone app uses; CI runs it on the iOS simulator (.github/workflows/ios-check.yml).
///
/// ```sh
/// flutter test integration_test -d DEVICE \
///   --dart-define=NXSAVES_TEST_SERVER=http://127.0.0.1:8765 --dart-define=NXSAVES_TEST_TOKEN=TOKEN
/// ```
const _server = String.fromEnvironment('NXSAVES_TEST_SERVER');
const _token = String.fromEnvironment('NXSAVES_TEST_TOKEN');

/// Big Buck Bunny trailer (CC BY 3.0, Blender Foundation) from Blender's own download server.
const _url = String.fromEnvironment(
  'NXSAVES_TEST_URL',
  defaultValue: 'https://download.blender.org/peach/trailer/trailer_iphone.m4v',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('downloads a link through the NxSaves server and saves it', (tester) async {
    expect(_server, isNotEmpty, reason: 'Pass --dart-define=NXSAVES_TEST_SERVER=http://host:port');
    final services = await AppServices.create();
    services.settings
      ..engine = EngineKind.remote
      ..serverUrl = _server
      ..serverToken = _token
      ..autoSaveToPhotos = false;
    final before = services.library.items.length;

    await tester.pumpWidget(NxSavesApp(services: services));
    await tester.pump(const Duration(seconds: 1));

    await tester.enterText(find.byKey(const ValueKey('linkField')), _url);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('fetchButton')));

    final download = find.byKey(const ValueKey('downloadButton'));
    await _pumpUntil(
      tester,
      () => download.evaluate().isNotEmpty || find.text('Try again').evaluate().isNotEmpty,
      const Duration(minutes: 2),
    );
    expect(download, findsOneWidget, reason: 'The server could not read the link');

    await tester.ensureVisible(download);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(download);

    await _pumpUntil(
      tester,
      () =>
          services.library.items.length > before ||
          services.downloads.tasks.any((t) => t.status == TaskStatus.failed),
      const Duration(minutes: 4),
    );
    final failed = services.downloads.tasks.where((t) => t.status == TaskStatus.failed).toList();
    expect(failed, isEmpty, reason: [for (final t in failed) '${t.error}\n${t.errorDetail}'].join('\n'));

    final item = services.library.items.first;
    final file = File(services.library.absolutePath(item)!);
    expect(file.existsSync(), isTrue, reason: 'Saved file is missing: ${file.path}');
    expect(file.lengthSync(), item.sizeBytes);
    expect(item.sizeBytes, greaterThan(100 * 1024));
    expect(item.kind, MediaKind.video);

    // Leave the Library on screen for the CI screenshots.
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Library')));
    await tester.pump(const Duration(seconds: 3));
  }, timeout: const Timeout(Duration(minutes: 8)));
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done, Duration timeout) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('Timed out after $timeout');
    await tester.pump(const Duration(milliseconds: 500));
  }
}
