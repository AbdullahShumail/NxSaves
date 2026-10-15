import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/models.dart';
import '../../engine/local_engine.dart';
import '../../services/app_services.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'home_controller.dart';
import 'preview_cards.dart';
import 'quality_picker.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final HomeController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _input = TextEditingController();
  final _focus = FocusNode();

  HomeController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    _c.addListener(_syncInput);
  }

  /// Links shared from other apps arrive through the controller; mirror them in the field.
  void _syncInput() {
    final url = _c.url;
    if (url != null && _c.state == FetchState.loading && _input.text.trim() != url) {
      _input.text = url;
    }
  }

  @override
  void dispose() {
    _c.removeListener(_syncInput);
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      if (mounted) showSnack(context, 'The clipboard is empty. Copy a video link first.');
      return;
    }
    _input.text = text;
    _submit();
  }

  void _submit() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _focus.unfocus();
    _c.fetch(text);
  }

  void _clear() {
    _input.clear();
    _c.reset();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return GlowBackground(
      child: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([_c, services.settings]),
          builder: (context, _) {
            final needsServer = services.settings.engine == EngineKind.remote && !services.settings.serverConfigured;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                _Header(services: services),
                const SizedBox(height: 22),
                Text(
                  'Save videos & music\nfrom almost anywhere.',
                  style: context.text.headlineMedium?.copyWith(height: 1.12),
                ).animate().fadeIn(duration: 450.ms).slideY(begin: 0.15, curve: Curves.easeOutCubic),
                const SizedBox(height: 8),
                Text(
                  'YouTube, TikTok, Instagram, Facebook, X and 1,800+ more sites, powered by yt-dlp.',
                  style: context.text.bodyMedium?.copyWith(color: context.nx.muted),
                ).animate().fadeIn(delay: 80.ms, duration: 450.ms),
                const SizedBox(height: 20),
                _LinkField(
                  controller: _input,
                  focusNode: _focus,
                  onPaste: _paste,
                  onClear: _clear,
                  onSubmit: _submit,
                ).animate().fadeIn(delay: 140.ms, duration: 450.ms).slideY(begin: 0.1, curve: Curves.easeOutCubic),
                const SizedBox(height: 12),
                GradientButton(
                  key: const ValueKey('fetchButton'),
                  label: 'Get download options',
                  icon: Icons.auto_awesome_rounded,
                  loading: _c.state == FetchState.loading,
                  onPressed: _input.text.trim().isEmpty || needsServer ? null : _submit,
                ).animate().fadeIn(delay: 200.ms, duration: 450.ms),
                const SizedBox(height: 22),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 380),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(animation),
                      child: child,
                    ),
                  ),
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topCenter,
                    children: [...previous, ?current],
                  ),
                  child: _body(context, needsServer),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _body(BuildContext context, bool needsServer) {
    if (needsServer && _c.state != FetchState.loaded) return const _ServerSetupCard(key: ValueKey('server'));
    switch (_c.state) {
      case FetchState.idle:
        return const _IdleHints(key: ValueKey('idle'));
      case FetchState.loading:
        return const PreviewSkeleton(key: ValueKey('loading'));
      case FetchState.failed:
        return _ErrorCard(
          key: ValueKey('error-${_c.error}'),
          message: _c.error ?? 'Something went wrong.',
          detail: _c.errorDetail,
          onRetry: _submit,
        );
      case FetchState.loaded:
        final info = _c.info!;
        return Column(
          key: ValueKey('loaded-${info.url}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            info.isPlaylist ? PlaylistPreviewCard(info: info) : MediaPreviewCard(info: info),
            const SizedBox(height: 18),
            QualityPicker(controller: _c),
            const SizedBox(height: 18),
            _AddToQueueButton(controller: _c),
          ],
        );
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const BrandMark(),
        const SizedBox(width: 12),
        Text('NxSaves', style: context.text.titleLarge?.copyWith(fontSize: 22)),
        const Spacer(),
        _EngineChip(services: services),
      ],
    );
  }
}

class _EngineChip extends StatelessWidget {
  const _EngineChip({required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final settings = services.settings;
    final local = services.local;
    if (settings.engine == EngineKind.local && local != null) {
      return ValueListenableBuilder(
        valueListenable: local.status,
        builder: (context, status, _) {
          final (label, color, busy) = switch (status.state) {
            LocalEngineState.starting => ('Starting engine', context.nx.muted, true),
            LocalEngineState.updating => ('Updating yt-dlp', NxColors.amber, true),
            LocalEngineState.failed => ('Engine error', NxColors.red, false),
            LocalEngineState.ready => ('yt-dlp ${status.version ?? ''}'.trim(), NxColors.teal, false),
          };
          return _chip(context, label, color, busy, onTap: () => AppShellState.of(context)?.goTo(3));
        },
      );
    }
    final ok = settings.serverConfigured;
    return _chip(
      context,
      ok ? 'Server' : 'Set up server',
      ok ? NxColors.teal : NxColors.amber,
      false,
      icon: Icons.dns_rounded,
      onTap: () => AppShellState.of(context)?.goTo(3),
    );
  }

  Widget _chip(BuildContext context, String label, Color color, bool busy, {IconData? icon, VoidCallback? onTap}) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.8, color: color))
              else
                Icon(icon ?? Icons.bolt_rounded, size: 14, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkField extends StatelessWidget {
  const _LinkField({
    required this.controller,
    required this.focusNode,
    required this.onPaste,
    required this.onClear,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onPaste;
  final VoidCallback onClear;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final empty = controller.text.isEmpty;
    return TextField(
      key: const ValueKey('linkField'),
      controller: controller,
      focusNode: focusNode,
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.go,
      autocorrect: false,
      enableSuggestions: false,
      onSubmitted: (_) => onSubmit(),
      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: 'Paste a video or post link',
        prefixIcon: Icon(Icons.link_rounded, color: context.nx.muted),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: empty
                ? TextButton.icon(
                    key: const ValueKey('paste'),
                    onPressed: onPaste,
                    icon: const Icon(Icons.content_paste_rounded, size: 18),
                    label: const Text('Paste'),
                  )
                : IconButton(
                    key: const ValueKey('clear'),
                    tooltip: 'Clear',
                    onPressed: onClear,
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
      ),
    );
  }
}

class _IdleHints extends StatelessWidget {
  const _IdleHints({super.key});

  static const _sites = [
    ('YouTube', Icons.smart_display_rounded, Color(0xFFFF4E45)),
    ('TikTok', Icons.music_video_rounded, Color(0xFF25F4EE)),
    ('Instagram', Icons.camera_alt_rounded, Color(0xFFE1306C)),
    ('Facebook', Icons.facebook_rounded, Color(0xFF1877F2)),
    ('X', Icons.alternate_email_rounded, Color(0xFF9A9AB0)),
    ('Vimeo', Icons.play_circle_fill_rounded, Color(0xFF1AB7EA)),
    ('Reddit', Icons.forum_rounded, Color(0xFFFF5700)),
    ('SoundCloud', Icons.graphic_eq_rounded, Color(0xFFFF7700)),
  ];

  @override
  Widget build(BuildContext context) {
    final android = Platform.isAndroid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Works with', style: context.text.titleSmall?.copyWith(color: context.nx.muted)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (i, site) in _sites.indexed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: context.nx.card,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: context.nx.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(site.$2, size: 16, color: site.$3),
                    const SizedBox(width: 6),
                    Text(site.$1, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  ],
                ),
              ).animate().fadeIn(delay: (40 * i).ms, duration: 300.ms).scale(begin: const Offset(0.9, 0.9)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: NxColors.violet.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '+1,800 more',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: context.colors.primary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        NxCard(
          child: Row(
            children: [
              Icon(android ? Icons.ios_share_rounded : Icons.content_paste_go_rounded, color: context.colors.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  android
                      ? 'Tip: in YouTube, TikTok or Instagram tap Share › NxSaves to send the link here.'
                      : 'Tip: in any app tap Share › Copy link, then tap Paste above.',
                  style: context.text.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Only download content you own or have permission to save, and respect each site’s terms.',
          style: context.text.bodySmall?.copyWith(color: context.nx.muted),
        ),
      ],
    );
  }
}

class _ServerSetupCard extends StatelessWidget {
  const _ServerSetupCard({super.key});

  @override
  Widget build(BuildContext context) {
    return NxCard(
      highlight: true,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.dns_rounded, color: NxColors.amber),
              const SizedBox(width: 10),
              Text('Connect your NxSaves server', style: context.text.titleMedium),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            Platform.isIOS
                ? 'iOS doesn’t allow apps to run yt-dlp and ffmpeg on the phone, so NxSaves on iPhone downloads '
                    'through a small server you run on your own computer. Add its address and access token.'
                : 'Server mode is selected. Add your server’s address and access token, or switch back to '
                    'on-device downloads in Settings.',
            style: context.text.bodyMedium?.copyWith(color: context.nx.muted),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => AppShellState.of(context)?.goTo(3),
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({super.key, required this.message, required this.onRetry, this.detail});

  final String message;
  final String? detail;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return NxCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: NxColors.red.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: const Icon(Icons.error_outline_rounded, color: NxColors.red, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: context.text.bodyLarge)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
              if (detail != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => showErrorDetails(context, message: message, detail: detail),
                  child: const Text('Details'),
                ),
              ],
            ],
          ),
        ],
      ),
    ).animate().shakeX(hz: 3, amount: 4, duration: 380.ms);
  }
}

class _AddToQueueButton extends StatefulWidget {
  const _AddToQueueButton({required this.controller});

  final HomeController controller;

  @override
  State<_AddToQueueButton> createState() => _AddToQueueButtonState();
}

class _AddToQueueButtonState extends State<_AddToQueueButton> {
  bool _added = false;

  void _add() {
    final count = widget.controller.enqueue();
    if (count == 0) return;
    HapticFeedback.mediumImpact();
    setState(() => _added = true);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _added = false);
    });
    showSnack(
      context,
      count == 1 ? 'Added to the queue' : 'Added $count downloads to the queue',
      actionLabel: 'View',
      onAction: () => AppShellState.of(context)?.goTo(1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final info = c.info!;
    final label = _added
        ? 'Added to queue'
        : info.isPlaylist
            ? 'Download all ${info.entries.length}'
            : c.kind == MediaKind.audio
                ? 'Download audio'
                : 'Download video';
    return GradientButton(
      key: const ValueKey('downloadButton'),
      label: label,
      icon: _added ? Icons.check_circle_rounded : Icons.download_rounded,
      onPressed: c.selected == null ? null : (_added ? () {} : _add),
    );
  }
}
