import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/links.dart';
import '../core/models.dart';
import '../services/app_services.dart';
import 'home/home_controller.dart';
import 'home/home_page.dart';
import 'library/library_page.dart';
import 'queue/queue_page.dart';
import 'settings/settings_page.dart';
import 'widgets/common.dart';

/// Bottom navigation with four tabs. Tabs stay alive (IndexedStack) and fade in when selected.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  int _tab = 0;
  late final AppServices _services = Services.of(context);
  late final HomeController _home = HomeController(_services);
  StreamSubscription<String>? _shareSub;
  StreamSubscription<LibraryItem>? _doneSub;

  static AppShellState? of(BuildContext context) => context.findAncestorStateOfType<AppShellState>();

  void goTo(int tab) {
    if (tab == _tab) return;
    HapticFeedback.selectionClick();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _tab = tab);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_doneSub != null) return;
    _doneSub = _services.downloads.completed.listen(_onCompleted);
    final android = _services.android;
    if (android != null) {
      _shareSub = android.sharedText.listen(_onShared);
      android.takePendingShare().then((text) {
        if (text != null) _onShared(text);
      });
    }
  }

  void _onShared(String text) {
    final url = extractUrl(text);
    if (url == null || !mounted) return;
    goTo(0);
    _home.fetch(url);
  }

  void _onCompleted(LibraryItem item) {
    if (!mounted) return;
    HapticFeedback.lightImpact();
    final where = Platform.isAndroid
        ? (item.kind == MediaKind.audio ? 'Music/NxSaves' : 'Movies/NxSaves')
        : (item.savedToPhotos ? 'Photos and Files' : 'Files › NxSaves');
    showSnack(context, 'Saved to $where: ${item.title}', actionLabel: 'Open', onAction: () {
      _services.library.open(item);
    });
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    _doneSub?.cancel();
    _home.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloads = _services.downloads;
    final pages = [
      HomePage(controller: _home),
      const QueuePage(),
      const LibraryPage(),
      const SettingsPage(),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_tab != 0) {
          goTo(0);
        } else {
          // Keep the app (and its downloads) alive instead of finishing the activity.
          _services.android?.moveToBackground();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            for (var i = 0; i < pages.length; i++)
              _TabPage(active: i == _tab, child: pages[i]),
          ],
        ),
        bottomNavigationBar: ListenableBuilder(
          listenable: downloads,
          builder: (context, _) {
            final active = downloads.activeCount;
            return NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: goTo,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.add_link_rounded),
                  selectedIcon: Icon(Icons.add_link_rounded),
                  label: 'Download',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: active > 0,
                    label: Text('$active'),
                    child: const Icon(Icons.downloading_rounded),
                  ),
                  label: 'Queue',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.video_library_outlined),
                  selectedIcon: Icon(Icons.video_library_rounded),
                  label: 'Library',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.tune_rounded),
                  label: 'Settings',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Keeps a tab's state while hidden; fades and lifts it in when it becomes active.
class _TabPage extends StatelessWidget {
  const _TabPage({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The fade itself must stay outside TickerMode, otherwise muting the hidden tab's tickers
    // would freeze its fade-out halfway.
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !active,
        child: AnimatedOpacity(
          opacity: active ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: AnimatedSlide(
            offset: active ? Offset.zero : const Offset(0, 0.015),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            child: TickerMode(
              enabled: active,
              child: ExcludeSemantics(excluding: !active, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
