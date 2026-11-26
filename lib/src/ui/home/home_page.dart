import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/links.dart';
import '../../core/models.dart';
import '../../services/app_services.dart';
import '../settings/settings_page.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'home_controller.dart';
import 'link_sheet.dart';
import 'tiles.dart';

/// The whole app on one screen: a link bar, what's downloading and what's saved.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final AppServices _services = Services.of(context);
  late final HomeController _controller = HomeController(_services);
  final _input = TextEditingController();
  final _focus = FocusNode();
  StreamSubscription<String>? _shareSub;
  StreamSubscription<LibraryItem>? _doneSub;
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    _focus.addListener(() => setState(() {}));
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

  @override
  void dispose() {
    _shareSub?.cancel();
    _doneSub?.cancel();
    _controller.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onShared(String text) {
    final url = extractUrl(text);
    if (url == null || !mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst || route is ModalBottomSheetRoute);
    _input.text = url;
    _submit();
  }

  void _onCompleted(LibraryItem item) {
    if (!mounted) return;
    HapticFeedback.lightImpact();
    showSnack(context, 'Saved  ·  ${item.title}', actionLabel: 'Open', onAction: () => _services.library.open(item));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (!mounted) return;
    if (text == null || text.isEmpty || extractUrl(text) == null) {
      showSnack(context, 'Copy a link first');
      return;
    }
    _input.text = extractUrl(text)!;
    _submit();
  }

  void _submit() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _focus.unfocus();
    _controller.fetch(text);
    _openSheet();
  }

  Future<void> _openSheet() async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    final queued = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => LinkSheet(controller: _controller, onOpenSettings: _openSettings),
    );
    _sheetOpen = false;
    if (queued == true) _input.clear();
    _controller.reset();
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
  }

  @override
  Widget build(BuildContext context) {
    final downloads = _services.downloads;
    final library = _services.library;
    final settings = _services.settings;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (context.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: PopScope(
        canPop: false,
        // Keep the app (and its downloads) alive instead of closing it.
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _services.android?.moveToBackground();
        },
        child: Scaffold(
          body: GestureDetector(
            onTap: () => _focus.unfocus(),
            behavior: HitTestBehavior.translucent,
            child: ListenableBuilder(
              listenable: Listenable.merge([downloads, library, settings]),
              builder: (context, _) {
                final tasks = downloads.tasks;
                final items = library.items;
                final needsServer = settings.engine == EngineKind.remote && !settings.serverConfigured;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: CustomScrollView(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      slivers: [
                        SliverSafeArea(
                          bottom: false,
                          sliver: SliverPadding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                            sliver: SliverList.list(
                              children: [
                                _Header(onSettings: _openSettings, attention: needsServer)
                                    .animate()
                                    .fadeIn(duration: 400.ms)
                                    .slideY(begin: -0.2, curve: Curves.easeOutCubic),
                                const SizedBox(height: 26),
                                _LinkBar(
                                  controller: _input,
                                  focusNode: _focus,
                                  onPaste: _paste,
                                  onSubmit: _submit,
                                )
                                    .animate()
                                    .fadeIn(delay: 90.ms, duration: 450.ms)
                                    .slideY(begin: 0.25, curve: Curves.easeOutCubic),
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOutCubic,
                                  child: needsServer
                                      ? Padding(
                                          padding: const EdgeInsets.only(top: 14),
                                          child: _ServerBanner(onTap: _openSettings),
                                        )
                                      : const SizedBox(width: double.infinity),
                                ),
                                const SizedBox(height: 30),
                              ],
                            ),
                          ),
                        ),
                        if (tasks.isNotEmpty)
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            sliver: SliverToBoxAdapter(child: SectionLabel('Downloading', count: tasks.length)),
                          ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          sliver: AnimatedSliverItems<DownloadTask>(
                            items: tasks,
                            idOf: (t) => t.id,
                            itemBuilder: (context, task) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: TaskTile(task: task, downloads: downloads),
                            ),
                          ),
                        ),
                        if (tasks.isNotEmpty) const SliverToBoxAdapter(child: SizedBox(height: 20)),
                        if (items.isNotEmpty)
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            sliver: SliverToBoxAdapter(
                              child: const SectionLabel('Saved').animate().fadeIn(delay: 160.ms, duration: 400.ms),
                            ),
                          ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          sliver: AnimatedSliverItems<LibraryItem>(
                            items: items,
                            idOf: (i) => i.id,
                            itemBuilder: (context, item) => SavedTile(item: item, library: library),
                          ),
                        ),
                        if (tasks.isEmpty && items.isEmpty)
                          const SliverFillRemaining(hasScrollBody: false, child: _EmptyState()),
                        SliverToBoxAdapter(child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onSettings, required this.attention});

  final VoidCallback onSettings;
  final bool attention;

  @override
  Widget build(BuildContext context) {
    final nx = context.nx;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: nx.accent, borderRadius: BorderRadius.circular(11)),
          child: Icon(Icons.arrow_downward_rounded, color: nx.onAccent, size: 22)
              .animate(delay: 500.ms)
              .moveY(begin: -10, end: 0, duration: 550.ms, curve: Curves.bounceOut)
              .fadeIn(duration: 200.ms),
        ),
        const SizedBox(width: 12),
        Text('NxSaves', style: context.text.headlineSmall?.copyWith(fontSize: 26)),
        const Spacer(),
        Stack(
          clipBehavior: Clip.none,
          children: [
            RoundIconButton(icon: Icons.tune_rounded, tooltip: 'Settings', onTap: onSettings, size: 42),
            if (attention)
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: NxColors.amber,
                    shape: BoxShape.circle,
                    border: Border.all(color: nx.background, width: 2),
                  ),
                ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 0.8, end: 1.15, duration: 900.ms),
              ),
          ],
        ),
      ],
    );
  }
}

/// The link field. Empty: a Paste button. With text: a go arrow.
class _LinkBar extends StatelessWidget {
  const _LinkBar({required this.controller, required this.focusNode, required this.onPaste, required this.onSubmit});

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onPaste;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final nx = context.nx;
    final empty = controller.text.trim().isEmpty;
    final focused = focusNode.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      height: 68,
      padding: const EdgeInsets.only(left: 18, right: 8),
      decoration: BoxDecoration(
        color: nx.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: focused ? nx.accent : nx.border, width: focused ? 1.6 : 1),
        boxShadow: [
          if (focused) BoxShadow(color: nx.accent.withValues(alpha: 0.18), blurRadius: 24, spreadRadius: 1),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.link_rounded, color: nx.muted, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              key: const ValueKey('linkField'),
              controller: controller,
              focusNode: focusNode,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => onSubmit(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                hintText: 'Paste a link',
                filled: false,
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: empty
                ? Pressable(
                    key: const ValueKey('paste'),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onPaste();
                    },
                    child: Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      decoration: BoxDecoration(color: nx.accent, borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        children: [
                          Icon(Icons.content_paste_rounded, color: nx.onAccent, size: 19),
                          const SizedBox(width: 8),
                          Text(
                            'Paste',
                            style: TextStyle(color: nx.onAccent, fontSize: 15.5, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  )
                : RoundIconButton(
                    key: const ValueKey('fetchButton'),
                    icon: Icons.arrow_forward_rounded,
                    filled: true,
                    size: 50,
                    tooltip: 'Go',
                    onTap: onSubmit,
                  ),
          ),
        ],
      ),
    );
  }
}

class _ServerBanner extends StatelessWidget {
  const _ServerBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nx = context.nx;
    return Pressable(
      onTap: onTap,
      child: NxCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: NxColors.amber.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: const Icon(Icons.dns_rounded, color: NxColors.amber, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('Connect your server', style: context.text.titleSmall?.copyWith(fontSize: 15))),
            Icon(Icons.chevron_right_rounded, color: nx.muted),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.1);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final nx = context.nx;
    return Padding(
      padding: const EdgeInsets.only(bottom: 80),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(color: nx.field.withValues(alpha: 0.6), shape: BoxShape.circle),
                ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 0.92, end: 1, duration: 1600.ms),
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(color: nx.card, shape: BoxShape.circle, border: Border.all(color: nx.border)),
                ),
                Icon(Icons.arrow_downward_rounded, size: 34, color: nx.text)
                    .animate(onPlay: (c) => c.repeat())
                    .moveY(begin: -14, end: 6, duration: 1300.ms, curve: Curves.easeIn)
                    .fadeIn(duration: 300.ms)
                    .then(delay: 700.ms)
                    .fadeOut(duration: 300.ms),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('Nothing saved yet', style: context.text.titleMedium?.copyWith(color: nx.muted)),
        ],
      ).animate().fadeIn(delay: 250.ms, duration: 500.ms),
    );
  }
}
