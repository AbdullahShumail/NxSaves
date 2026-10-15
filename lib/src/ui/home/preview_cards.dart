import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class MediaPreviewCard extends StatelessWidget {
  const MediaPreviewCard({super.key, required this.info});

  final MediaInfo info;

  /// Shorts, Reels and TikToks get a taller preview instead of a heavily cropped 16:9 one.
  bool get _vertical => info.formats.any((f) => (f.width ?? 0) > 0 && (f.height ?? 0) > (f.width ?? 0));

  @override
  Widget build(BuildContext context) {
    final duration = formatDuration(info.duration);
    return NxCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              MediaThumb(
                url: info.thumbnail,
                icon: Icons.movie_rounded,
                aspectRatio: _vertical ? 4 / 5 : 16 / 9,
                radius: 0,
              ),
              Positioned(
                left: 12,
                top: 12,
                child: Pill(label: siteName(info.extractor, url: info.url), icon: Icons.public_rounded, filled: true),
              ),
              if (duration.isNotEmpty)
                Positioned(right: 12, bottom: 12, child: Pill(label: duration, filled: true)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(info.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
                if (info.uploader != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    info.uploader!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyMedium?.copyWith(color: context.nx.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 350.ms)
        .scale(begin: const Offset(0.97, 0.97), curve: Curves.easeOutBack, duration: 450.ms);
  }
}

class PlaylistPreviewCard extends StatelessWidget {
  const PlaylistPreviewCard({super.key, required this.info});

  final MediaInfo info;

  @override
  Widget build(BuildContext context) {
    final thumbs = info.entries.map((e) => e.thumbnail).whereType<String>().take(3).toList();
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 92,
            child: Stack(
              children: [
                for (var i = 2; i >= 0; i--)
                  Positioned(
                    left: i * 26.0,
                    top: i * 4.0,
                    bottom: i * 4.0,
                    width: 150,
                    child: Opacity(
                      opacity: 1 - i * 0.22,
                      child: MediaThumb(
                        url: i < thumbs.length ? thumbs[i] : (thumbs.isEmpty ? info.thumbnail : null),
                        icon: Icons.playlist_play_rounded,
                        radius: 14,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Pill(label: siteName(info.extractor, url: info.url), icon: Icons.public_rounded),
              const SizedBox(width: 8),
              Pill(label: '${info.entries.length} items', icon: Icons.playlist_play_rounded, color: NxColors.pink),
            ],
          ),
          const SizedBox(height: 10),
          Text(info.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
          if (info.uploader != null)
            Text(info.uploader!, style: context.text.bodyMedium?.copyWith(color: context.nx.muted)),
          const SizedBox(height: 6),
          Text(
            'Each item is added to the queue separately with the quality you pick below.',
            style: context.text.bodySmall?.copyWith(color: context.nx.muted),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05);
  }
}

/// Shimmering placeholder while yt-dlp reads the link.
class PreviewSkeleton extends StatelessWidget {
  const PreviewSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final block = context.nx.field;
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(color: block, borderRadius: BorderRadius.circular(8)),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NxCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  decoration: BoxDecoration(
                    color: block,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [bar(260, 16), const SizedBox(height: 8), bar(160, 12)],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: bar(double.infinity, 74)),
            const SizedBox(width: 10),
            Expanded(child: bar(double.infinity, 74)),
          ],
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            'Reading the link with yt-dlp…',
            style: context.text.bodySmall?.copyWith(color: context.nx.muted),
          ),
        ),
      ],
    )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(duration: 1500.ms, color: NxColors.violet.withValues(alpha: 0.18));
  }
}
