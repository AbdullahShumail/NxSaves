import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/quality.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'home_controller.dart';

/// Bottom sheet for one link: a shimmer while it is read, then the preview, Video/Audio,
/// the qualities it really has and the Download button. Pops `true` once queued.
class LinkSheet extends StatefulWidget {
  const LinkSheet({super.key, required this.controller, required this.onOpenSettings});

  final HomeController controller;
  final VoidCallback onOpenSettings;

  @override
  State<LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends State<LinkSheet> {
  bool _queued = false;

  Future<void> _download() async {
    final count = widget.controller.enqueue();
    if (count == 0) return;
    setState(() => _queued = true);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (mounted) Navigator.of(context).pop(true);
  }

  void _openSettings() {
    Navigator.of(context).pop();
    widget.onOpenSettings();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final Widget body = switch (c.state) {
          FetchState.idle || FetchState.loading => const _Loading(key: ValueKey('loading')),
          FetchState.failed => _Failure(
              key: ValueKey('failed-${c.error}'),
              message: c.error ?? 'Something went wrong.',
              onRetry: c.url == null ? null : c.retry,
              onSettings: c.errorNeedsSettings ? _openSettings : null,
            ),
          FetchState.loaded => _Loaded(
              key: ValueKey('loaded-${c.info!.url}'),
              controller: c,
              queued: _queued,
              onDownload: _download,
            ),
        };
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.paddingOf(context).bottom),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(animation),
                  child: child,
                ),
              ),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, ?current],
              ),
              child: body,
            ),
          ),
        );
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AspectRatio(aspectRatio: 16 / 9, child: SkeletonBlock(height: double.infinity, radius: 22)),
        const SizedBox(height: 16),
        const SkeletonBlock(width: 250, height: 18),
        const SizedBox(height: 8),
        const SkeletonBlock(width: 140, height: 14),
        const SizedBox(height: 22),
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              const Expanded(child: SkeletonBlock(height: 60, radius: 16)),
            ],
          ],
        ),
        const SizedBox(height: 20),
        const SkeletonBlock(height: 58, radius: 18),
      ],
    )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(duration: 1300.ms, color: context.nx.muted.withValues(alpha: 0.18));
  }
}

class _Failure extends StatelessWidget {
  const _Failure({super.key, required this.message, this.onRetry, this.onSettings});

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: NxColors.red.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: const Icon(Icons.priority_high_rounded, color: NxColors.red, size: 32),
          ).animate().scale(begin: const Offset(0.5, 0.5), curve: Curves.elasticOut, duration: 700.ms),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: context.text.titleMedium?.copyWith(height: 1.35),
          ).animate().shakeX(hz: 4, amount: 3, duration: 400.ms),
          const SizedBox(height: 24),
          if (onRetry != null)
            AccentButton(label: 'Try again', icon: Icons.refresh_rounded, onPressed: onRetry)
          else if (onSettings != null)
            AccentButton(label: 'Open settings', icon: Icons.tune_rounded, onPressed: onSettings),
          if (onRetry != null && onSettings != null) ...[
            const SizedBox(height: 6),
            TextButton(onPressed: onSettings, child: const Text('Open settings')),
          ],
        ],
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({super.key, required this.controller, required this.queued, required this.onDownload});

  final HomeController controller;
  final bool queued;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final info = c.info!;
    final hasVideo = c.videoOptions.isNotEmpty;
    final hasAudio = c.audioOptions.isNotEmpty;
    final label = info.isPlaylist ? 'Download all ${info.entries.length}' : 'Download';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        info.isPlaylist ? _PlaylistPreview(info: info) : _MediaPreview(info: info),
        const SizedBox(height: 20),
        if (hasVideo && hasAudio) ...[
          _KindToggle(
            kind: c.kind,
            onChanged: (kind) {
              HapticFeedback.selectionClick();
              c.setKind(kind);
            },
          ).animate().fadeIn(delay: 80.ms, duration: 300.ms),
          const SizedBox(height: 14),
        ],
        _QualityGrid(controller: c),
        const SizedBox(height: 20),
        AccentButton(
          key: const ValueKey('downloadButton'),
          label: label,
          icon: Icons.arrow_downward_rounded,
          done: queued,
          onPressed: c.selected == null ? null : onDownload,
        ).animate().fadeIn(delay: 200.ms, duration: 300.ms).slideY(begin: 0.3, curve: Curves.easeOutCubic),
      ],
    );
  }
}

class _MediaPreview extends StatelessWidget {
  const _MediaPreview({required this.info});

  final MediaInfo info;

  @override
  Widget build(BuildContext context) {
    final nx = context.nx;
    final duration = formatDuration(info.duration);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MediaThumb(url: info.thumbnail, icon: Icons.movie_rounded, radius: 22),
              if (duration.isNotEmpty) Positioned(right: 10, bottom: 10, child: ImageTag(duration)),
            ],
          ),
        ).animate().fadeIn(duration: 350.ms).scale(begin: const Offset(0.96, 0.96), curve: Curves.easeOutCubic),
        const SizedBox(height: 14),
        Text(info.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontSize: 17)),
        if (info.uploader != null) ...[
          const SizedBox(height: 3),
          Text(
            info.uploader!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: nx.muted, fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ],
      ],
    );
  }
}

class _PlaylistPreview extends StatelessWidget {
  const _PlaylistPreview({required this.info});

  final MediaInfo info;

  @override
  Widget build(BuildContext context) {
    final nx = context.nx;
    final thumbs = info.entries.map((e) => e.thumbnail).whereType<String>().take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 120,
          child: Stack(
            children: [
              for (var i = 2; i >= 0; i--)
                Positioned(
                  left: i * 34.0,
                  top: i * 6.0,
                  bottom: i * 6.0,
                  width: 190,
                  child: Opacity(
                    opacity: 1 - i * 0.25,
                    child: MediaThumb(
                      url: i < thumbs.length ? thumbs[i] : (thumbs.isEmpty ? info.thumbnail : null),
                      icon: Icons.video_library_rounded,
                      radius: 18,
                    ),
                  ),
                ).animate().fadeIn(delay: (70 * (2 - i)).ms, duration: 350.ms).slideX(begin: -0.15),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(info.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium?.copyWith(fontSize: 17)),
        const SizedBox(height: 3),
        Text(
          '${info.entries.length} videos',
          style: TextStyle(color: nx.muted, fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ],
    );
  }
}

/// Video / Audio switch with a sliding thumb.
class _KindToggle extends StatelessWidget {
  const _KindToggle({required this.kind, required this.onChanged});

  final MediaKind kind;
  final ValueChanged<MediaKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final nx = context.nx;
    Widget segment(MediaKind value, IconData icon, String label) {
      final selected = kind == value;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(value),
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: selected ? nx.text : nx.muted,
                fontFamily: DefaultTextStyle.of(context).style.fontFamily,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 19, color: selected ? nx.text : nx.muted),
                  const SizedBox(width: 7),
                  Text(label),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: nx.field, borderRadius: BorderRadius.circular(16)),
      child: Stack(
        children: [
          AnimatedAlign(
            alignment: kind == MediaKind.video ? Alignment.centerLeft : Alignment.centerRight,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: nx.card,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: context.isDark ? 0.3 : 0.08), blurRadius: 8),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              segment(MediaKind.video, Icons.movie_rounded, 'Video'),
              segment(MediaKind.audio, Icons.music_note_rounded, 'Audio'),
            ],
          ),
        ],
      ),
    );
  }
}

class _QualityGrid extends StatelessWidget {
  const _QualityGrid({required this.controller});

  final HomeController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, ?current],
      ),
      child: LayoutBuilder(
        key: ValueKey(c.kind),
        builder: (context, constraints) {
          const gap = 10.0;
          final columns = c.options.length == 2 ? 2 : 3;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final (i, option) in c.options.indexed)
                SizedBox(
                  width: width,
                  child: _QualityChip(
                    option: option,
                    selected: c.selected == option,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      c.select(option);
                    },
                  ),
                )
                    .animate()
                    .fadeIn(delay: (35 * i).ms, duration: 260.ms)
                    .slideY(begin: 0.25, curve: Curves.easeOutCubic),
            ],
          );
        },
      ),
    );
  }
}

class _QualityChip extends StatelessWidget {
  const _QualityChip({required this.option, required this.selected, required this.onTap});

  final QualityOption option;
  final bool selected;
  final VoidCallback onTap;

  String get _title {
    final h = option.spec.height;
    if (option.spec.kind == MediaKind.audio) return option.title;
    if (h == null) return 'Best';
    return h >= 2160 ? '4K' : '${h}p';
  }

  @override
  Widget build(BuildContext context) {
    final nx = context.nx;
    final fg = selected ? nx.onAccent : nx.text;
    final size = option.approxBytes == null ? null : formatBytes(option.approxBytes, decimals: 0);
    return Pressable(
      scale: 0.94,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        height: 62,
        decoration: BoxDecoration(
          color: selected ? nx.accent : nx.field,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text.rich(
              TextSpan(
                text: _title,
                children: [
                  if (option.fps != null)
                    TextSpan(text: '${option.fps}', style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.75))),
                ],
              ),
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: fg, letterSpacing: -0.3),
            ),
            if (size != null) ...[
              const SizedBox(height: 2),
              Text(
                size,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.65)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
