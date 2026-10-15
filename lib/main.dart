import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/services/app_services.dart';
import 'src/ui/shell.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  try {
    final services = await AppServices.create();
    runApp(NxSavesApp(services: services));
  } catch (error, stack) {
    debugPrint('Startup failed: $error\n$stack');
    runApp(_StartupError(error: error));
  }
}

class NxSavesApp extends StatelessWidget {
  const NxSavesApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return Services(
      services: services,
      child: MaterialApp(
        title: 'NxSaves',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const AppShell(),
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('NxSaves could not start:\n\n$error', textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}
