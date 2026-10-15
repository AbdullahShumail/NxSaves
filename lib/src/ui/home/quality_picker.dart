import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/quality.dart';
import '../theme.dart';
import 'home_controller.dart';

/// Video/Audio switch plus a grid of the qualities this link actually offers.
class QualityPicker extends StatelessWidget {
  const QualityPicker({super.key, required this.controller});

  final HomeController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final hasVideo = c.videoOptions.isNotEmpty;
    final hasAudio = c.audioOptions.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasVideo && hasAudio)
          SegmentedButton<MediaKind>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: MediaKind.video, icon: Icon(Icons.movie_rounded), label: Text('Video')),
              ButtonSegment(value: MediaKind.audio, icon: Icon(Icons.music_note_rounded), label: Text('Audio')),
            ],
            selected: {c.kind},
            onSelectionChanged: (s) {
              HapticFeedback.selectionClick();
              c.setKind(s.first);
            },
          )
        else
          Text(hasVideo ? 'Video quality' : 'Audio format', style: context.text.titleSmall),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topLeft,
            children: [...previous, ?current],
          ),
          child: LayoutBuilder(
            key: ValueKey(c.kind),
            builder: (context, constraints) {
              const gap = 10.0;
              final width = (constraints.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final (i, option) in c.options.indexed)
                    SizedBox(
                      width: width,
                      child: _QualityTile(
                        option: option,
                        selected: c.selected == option,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          c.select(option);
                        },
                      ),
                    ).animate().fadeIn(delay: (30 * i).ms, duration: 260.ms).slideY(begin: 0.12, curve: Curves.easeOutCubic),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Text(
          switch (c.kind) {
            MediaKind.audio => 'MP3 plays everywhere. M4A keeps the original AAC audio without re-encoding.',
            MediaKind.video when c.services.settings.preferCompat =>
              'Sizes are estimates. H.264 MP4 is preferred so files play everywhere (change in Settings).',
            MediaKind.video => 'Sizes are estimates. The most efficient codecs (VP9/AV1) are preferred.',
          },
          style: context.text.bodySmall?.copyWith(color: context.nx.muted),
        ),
      ],
    );
  }
}

class _QualityTile extends StatelessWidget {
  const _QualityTile({required this.option, required this.selected, required this.onTap});

  final QualityOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = option.approxBytes == null ? null : '~${formatBytes(option.approxBytes)}';
    final showCompatWarning = Platform.isIOS && option.spec.kind == MediaKind.video && !option.compatible;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: selected ? NxColors.brand : null,
        color: selected ? null : context.nx.border,
      ),
      padding: EdgeInsets.all(selected ? 1.6 : 1),
      child: Material(
        color: selected ? Color.alphaBlend(NxColors.violet.withValues(alpha: 0.16), context.nx.card) : context.nx.card,
        borderRadius: BorderRadius.circular(16.5),
        child: InkWell(
          borderRadius: BorderRadius.circular(16.5),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(option.title, style: context.text.titleMedium),
                    if (option.badge != null) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: selected ? NxColors.pink.withValues(alpha: 0.18) : NxColors.violet.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            option.badge!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: selected ? NxColors.pink : context.colors.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [if (option.detail.isNotEmpty) option.detail, ?size].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(color: context.nx.muted),
                ),
                if (showCompatWarning)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'May not open in Photos',
                      style: context.text.labelSmall?.copyWith(color: NxColors.amber),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
