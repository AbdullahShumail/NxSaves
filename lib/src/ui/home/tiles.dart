import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../services/download_manager.dart';
import '../../services/library.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// A download in progress, waiting, paused or failed.
class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.task, required this.downloads});

  final DownloadTask task;
  final DownloadManager downloads;

  @override
  Widget build(BuildContext context) {
    final nx = context.nx;
    final failed = task.status == TaskStatus.failed;
    final paused = task.status == TaskStatus.paused;
    final running = task.status == TaskStatus.running;
    final percent = task.progress == null ? null : '${(task.progress! * 100).clamp(0, 100).toStringAsFixed(0)}%';

    final String status;
    if (failed) {
      status = task.error ?? "Couldn't download";
    } else if (paused) {
      status = percent == null ? 'Paused' : 'Paused · $percent';
    } else if (!running) {
      status = 'Waiting';
    } else if (task.stage.startsWith('Downloading') && percent != null) {
      status = percent;
    } else {
      status = task.stage;
    }
    final meta = running
        ? [formatSpeed(task.speed), formatEta(task.eta)].where((s) => s.isNotEmpty).join(' · ')
        : '';

    return NxCard(
      padding: const EdgeInsets.all(12),
      radius: 20,
      child: Row(
        children: [
          SizedBox(
            width: 74,
            height: 52,
            child: MediaThumb(
              url: task.thumbnail,
              icon: task.spec.kind == MediaKind.audio ? Icons.music_note_rounded : Icons.movie_rounded,
              radius: 12,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (!failed) ...[
                  ProgressLine(
                    value: running ? task.progress : (paused ? task.progress ?? 0 : 0),
                    color: paused ? NxColors.amber : null,
                  ),
                  const SizedBox(height: 7),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.centerLeft,
                          children: [...previous, ?current],
                        ),
                        child: Text(
                          status,
                          key: ValueKey(failed ? 'failed' : status.endsWith('%') ? 'pct' : status),
                          maxLines: failed ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: failed ? NxColors.red : (paused ? NxColors.amber : nx.text),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                    if (meta.isNotEmpty)
                      Text(
                        meta,
                        style: TextStyle(
                          fontSize: 12,
                          color: nx.muted,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ..._actions(context),
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    final saving = downloads.isSaving(task);
    const gap = SizedBox(width: 6);
    switch (task.status) {
      case TaskStatus.running || TaskStatus.queued:
        return [
          if (downloads.canPause(task)) ...[
            RoundIconButton(icon: Icons.pause_rounded, size: 36, tooltip: 'Pause', onTap: () => downloads.pause(task)),
            gap,
          ],
          if (!saving)
            RoundIconButton(icon: Icons.close_rounded, size: 36, tooltip: 'Cancel', onTap: () => _confirmCancel(context)),
        ];
      case TaskStatus.paused:
        return [
          RoundIconButton(
            icon: Icons.play_arrow_rounded,
            size: 36,
            filled: true,
            tooltip: 'Resume',
            onTap: () => downloads.resume(task),
          ),
          gap,
          RoundIconButton(icon: Icons.close_rounded, size: 36, tooltip: 'Remove', onTap: () => downloads.remove(task)),
        ];
      case TaskStatus.failed:
        return [
          RoundIconButton(
            icon: Icons.refresh_rounded,
            size: 36,
            filled: true,
            tooltip: 'Try again',
            onTap: () => downloads.retry(task),
          ),
          gap,
          RoundIconButton(icon: Icons.close_rounded, size: 36, tooltip: 'Remove', onTap: () => downloads.remove(task)),
        ];
    }
  }

  Future<void> _confirmCancel(BuildContext context) async {
    if (task.status == TaskStatus.queued) {
      await downloads.remove(task);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this download?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel it')),
        ],
      ),
    );
    if (ok == true) await downloads.remove(task);
  }
}

/// A finished download. Tap opens it; the dots open Share, Copy link and Delete.
class SavedTile extends StatelessWidget {
  const SavedTile({super.key, required this.item, required this.library});

  final LibraryItem item;
  final Library library;

  Future<void> _open(BuildContext context) async {
    if (item.missing) {
      await _showActions(context);
      return;
    }
    final error = await library.open(item);
    if (error != null && context.mounted) showSnack(context, error);
  }

  @override
  Widget build(BuildContext context) {
    final nx = context.nx;
    final audio = item.kind == MediaKind.audio;
    final duration = formatDuration(item.duration);
    final meta = [
      audio ? 'Audio' : 'Video',
      formatBytes(item.sizeBytes),
      formatDate(item.createdAt),
    ].join('  ·  ');
    return Pressable(
      scale: 0.98,
      onTap: () => _open(context),
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _showActions(context);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 68,
              height: 68,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(
                    opacity: item.missing ? 0.4 : 1,
                    child: MediaThumb(
                      file: library.thumbnailOf(item),
                      icon: audio ? Icons.music_note_rounded : Icons.movie_rounded,
                      radius: 16,
                    ),
                  ),
                  if (audio && library.thumbnailOf(item) != null)
                    const Positioned(right: 5, bottom: 5, child: _GlyphBadge(icon: Icons.music_note_rounded)),
                  if (!audio && duration.isNotEmpty) Positioned(right: 5, bottom: 5, child: ImageTag(duration)),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      color: item.missing ? nx.muted : nx.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.missing ? 'File missing' : meta,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: item.missing ? NxColors.amber : nx.muted,
                    ),
                  ),
                ],
              ),
            ),
            Builder(
              builder: (anchor) => IconButton(
                tooltip: 'More',
                icon: Icon(Icons.more_horiz_rounded, color: nx.muted),
                onPressed: () => _showActions(anchor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showActions(BuildContext anchorContext) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    // Captured up front: the tile is gone after a delete, but the messenger isn't.
    final messenger = ScaffoldMessenger.of(anchorContext);
    final canPhotos = Platform.isIOS && item.kind == MediaKind.video && !item.missing && !item.savedToPhotos;
    final action = await showModalBottomSheet<String>(
      context: anchorContext,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Text(
                  item.title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleMedium,
                ),
              ),
              if (!item.missing) _SheetAction(icon: Icons.ios_share_rounded, label: 'Share', value: 'share'),
              if (canPhotos) const _SheetAction(icon: Icons.photo_library_rounded, label: 'Save to Photos', value: 'photos'),
              const _SheetAction(icon: Icons.link_rounded, label: 'Copy link', value: 'copy'),
              _SheetAction(
                icon: Icons.delete_outline_rounded,
                label: item.missing ? 'Remove' : 'Delete',
                value: 'delete',
                destructive: true,
              ),
            ]
                .animate(interval: 40.ms)
                .fadeIn(duration: 250.ms)
                .slideY(begin: 0.3, curve: Curves.easeOutCubic),
          ),
        ),
      ),
    );
    if (action == null || !anchorContext.mounted) return;
    String? message;
    switch (action) {
      case 'share':
        message = await library.share(item, origin: origin);
      case 'photos':
        message = await library.saveToPhotos(item) ?? 'Added to Photos';
      case 'copy':
        await Clipboard.setData(ClipboardData(text: item.sourceUrl));
        message = 'Link copied';
      case 'delete':
        if (item.missing) {
          message = await library.remove(item, deleteFile: false);
          break;
        }
        if (!anchorContext.mounted) return;
        final ok = await showDialog<bool>(
          context: anchorContext,
          builder: (context) => AlertDialog(
            title: const Text('Delete this file?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: NxColors.red, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (ok == true) message = await library.remove(item, deleteFile: true);
    }
    if (message != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message), persist: false, duration: const Duration(seconds: 3)));
    }
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({required this.icon, required this.label, required this.value, this.destructive = false});

  final IconData icon;
  final String label;
  final String value;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final nx = context.nx;
    final color = destructive ? NxColors.red : nx.text;
    return Pressable(
      scale: 0.98,
      onTap: () => Navigator.pop(context, value),
      child: Container(
        height: 56,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(color: nx.field, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Text(label, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _GlyphBadge extends StatelessWidget {
  const _GlyphBadge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(7)),
      child: Icon(icon, size: 13, color: Colors.white),
    );
  }
}
