import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../services/app_services.dart';
import '../../services/download_manager.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/common.dart';

class QueuePage extends StatelessWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context) {
    final downloads = Services.of(context).downloads;
    return GlowBackground(
      child: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: downloads,
          builder: (context, _) {
            final tasks = downloads.tasks;
            final running = tasks.where((t) => t.status == TaskStatus.running).length;
            final waiting = tasks.where((t) => t.status == TaskStatus.queued).length;
            final failed = tasks.where((t) => t.status == TaskStatus.failed).length;
            final subtitle = tasks.isEmpty
                ? 'Nothing in progress'
                : [
                    if (running > 0) '$running downloading',
                    if (waiting > 0) '$waiting waiting',
                    if (failed > 0) '$failed failed',
                    if (running + waiting + failed == 0) '${tasks.length} paused',
                  ].join(' · ');
            return Column(
              children: [
                PageHeader(
                  title: 'Queue',
                  subtitle: subtitle,
                  trailing: failed > 0
                      ? TextButton.icon(
                          onPressed: downloads.clearFailed,
                          icon: const Icon(Icons.delete_sweep_rounded, size: 20),
                          label: const Text('Clear failed'),
                        )
                      : null,
                ),
                Expanded(
                  child: tasks.isEmpty
                      ? EmptyState(
                          icon: Icons.downloading_rounded,
                          title: 'No downloads yet',
                          message: 'Paste a link on the Download tab and pick a quality. Progress shows up here.',
                          action: FilledButton.tonalIcon(
                            onPressed: () => AppShellState.of(context)?.goTo(0),
                            icon: const Icon(Icons.add_link_rounded),
                            label: const Text('Add a link'),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: tasks.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, i) => _TaskCard(
                            key: ValueKey(tasks[i].id),
                            task: tasks[i],
                            downloads: downloads,
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({super.key, required this.task, required this.downloads});

  final DownloadTask task;
  final DownloadManager downloads;

  @override
  Widget build(BuildContext context) {
    final failed = task.status == TaskStatus.failed;
    final paused = task.status == TaskStatus.paused;
    final running = task.status == TaskStatus.running;
    final statusColor = failed
        ? NxColors.red
        : paused
            ? NxColors.amber
            : running
                ? context.colors.primary
                : context.nx.muted;

    final details = <String>[
      if (running && task.downloadedBytes != null)
        task.totalBytes != null
            ? '${formatBytes(task.downloadedBytes)} of ${formatBytes(task.totalBytes)}'
            : formatBytes(task.downloadedBytes),
      if (running) formatSpeed(task.speed),
      if (running) formatEta(task.eta),
    ].where((s) => s.isNotEmpty).join(' · ');

    return NxCard(
      padding: const EdgeInsets.all(12),
      onTap: failed ? () => showErrorDetails(context, message: task.error ?? 'Failed', detail: task.errorDetail) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 84,
                height: 56,
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
                    Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Pill(label: task.spec.label, color: context.colors.primary),
                        Pill(label: siteName(task.extractor, url: task.url), color: context.nx.muted),
                        if (task.engine == EngineKind.remote)
                          const Pill(label: 'Server', icon: Icons.dns_rounded, color: NxColors.teal),
                      ],
                    ),
                  ],
                ),
              ),
              _Actions(task: task, downloads: downloads),
            ],
          ),
          const SizedBox(height: 12),
          if (!failed)
            NxProgressBar(
              value: running ? task.progress : (paused ? task.progress ?? 0 : 0),
              color: paused ? NxColors.amber : null,
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  failed ? (task.error ?? 'Failed') : task.stage,
                  maxLines: failed ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodySmall?.copyWith(color: statusColor, fontWeight: FontWeight.w600),
                ),
              ),
              if (running && task.progress != null)
                Text(
                  '${(task.progress! * 100).toStringAsFixed(0)}%',
                  style: context.text.labelMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
            ],
          ),
          if (details.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                details,
                style: context.text.bodySmall?.copyWith(
                  color: context.nx.muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          if (failed)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Tap for details', style: context.text.labelSmall?.copyWith(color: context.nx.muted)),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideX(begin: 0.04, curve: Curves.easeOutCubic);
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.task, required this.downloads});

  final DownloadTask task;
  final DownloadManager downloads;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String tooltip, VoidCallback onTap, {Color? color}) => IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: tooltip,
          icon: Icon(icon, color: color),
          onPressed: () {
            HapticFeedback.selectionClick();
            onTap();
          },
        );
    final saving = downloads.isSaving(task);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: switch (task.status) {
        TaskStatus.running || TaskStatus.queued => [
            if (downloads.canPause(task)) button(Icons.pause_rounded, 'Pause', () => downloads.pause(task)),
            if (!saving) button(Icons.close_rounded, 'Cancel', () => _confirmRemove(context)),
          ],
        TaskStatus.paused => [
            button(Icons.play_arrow_rounded, 'Resume', () => downloads.resume(task), color: context.colors.primary),
            button(Icons.close_rounded, 'Remove', () => downloads.remove(task)),
          ],
        TaskStatus.failed => [
            button(Icons.refresh_rounded, 'Retry', () => downloads.retry(task), color: context.colors.primary),
            button(Icons.close_rounded, 'Remove', () => downloads.remove(task)),
          ],
      },
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    if (task.status == TaskStatus.queued) {
      await downloads.remove(task);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel download?'),
        content: Text('“${task.title}” will be removed from the queue and its partial data deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel download')),
        ],
      ),
    );
    if (ok == true) await downloads.remove(task);
  }
}
