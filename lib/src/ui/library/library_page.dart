import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../services/app_services.dart';
import '../../services/library.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/common.dart';

enum _Filter { all, video, audio }

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> with WidgetsBindingObserver {
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Files may have been deleted from the gallery / Files app while we were away.
    if (state == AppLifecycleState.resumed) Services.of(context).library.refreshAvailability();
  }

  @override
  Widget build(BuildContext context) {
    final library = Services.of(context).library;
    return GlowBackground(
      child: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: library,
          builder: (context, _) {
            final all = library.items;
            final items = switch (_filter) {
              _Filter.all => all,
              _Filter.video => all.where((i) => i.kind == MediaKind.video).toList(),
              _Filter.audio => all.where((i) => i.kind == MediaKind.audio).toList(),
            };
            final totalBytes = all.fold<int>(0, (sum, i) => sum + i.sizeBytes);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeader(
                  title: 'Library',
                  subtitle: all.isEmpty
                      ? 'Your saved files'
                      : '${all.length} ${all.length == 1 ? 'file' : 'files'} · ${formatBytes(totalBytes)}',
                ),
                if (all.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Row(
                      children: [
                        for (final f in _Filter.values) ...[
                          ChoiceChip(
                            label: Text(switch (f) {
                              _Filter.all => 'All',
                              _Filter.video => 'Videos',
                              _Filter.audio => 'Audio',
                            }),
                            selected: _filter == f,
                            showCheckmark: false,
                            onSelected: (_) => setState(() => _filter = f),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                Expanded(
                  child: all.isEmpty
                      ? EmptyState(
                          icon: Icons.video_library_rounded,
                          title: 'Nothing saved yet',
                          message: Platform.isIOS
                              ? 'Finished downloads appear here and in Files › On My iPhone › NxSaves.'
                              : 'Finished downloads appear here and in your gallery (Movies/NxSaves, Music/NxSaves).',
                          action: FilledButton.tonalIcon(
                            onPressed: () => AppShellState.of(context)?.goTo(0),
                            icon: const Icon(Icons.add_link_rounded),
                            label: const Text('Download something'),
                          ),
                        )
                      : items.isEmpty
                          ? Center(
                              child: Text('No ${_filter.name} files yet', style: TextStyle(color: context.nx.muted)),
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 260,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 0.82,
                              ),
                              itemCount: items.length,
                              itemBuilder: (context, i) => _LibraryTile(
                                key: ValueKey(items[i].id),
                                item: items[i],
                                library: library,
                                index: i,
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

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({super.key, required this.item, required this.library, required this.index});

  final LibraryItem item;
  final Library library;
  final int index;

  Future<void> _open(BuildContext context) async {
    final error = await library.open(item);
    if (error != null && context.mounted) showSnack(context, error);
  }

  @override
  Widget build(BuildContext context) {
    final audio = item.kind == MediaKind.audio;
    final duration = formatDuration(item.duration);
    return NxCard(
      padding: EdgeInsets.zero,
      onTap: item.missing ? () => _showActions(context) : () => _open(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MediaThumb(
                  file: library.thumbnailOf(item),
                  icon: audio ? Icons.music_note_rounded : Icons.movie_rounded,
                  radius: 0,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.45)],
                      stops: const [0.5, 1],
                    ),
                  ),
                ),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), shape: BoxShape.circle),
                    child: Icon(
                      item.missing ? Icons.link_off_rounded : (audio ? Icons.music_note_rounded : Icons.play_arrow_rounded),
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
                if (duration.isNotEmpty) Positioned(right: 8, bottom: 8, child: Pill(label: duration, filled: true)),
                if (item.missing)
                  const Positioned(left: 8, top: 8, child: Pill(label: 'File missing', color: NxColors.amber, filled: true)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.labelLarge),
                      const SizedBox(height: 3),
                      Text(
                        '${formatBytes(item.sizeBytes)} · ${formatDate(item.createdAt)}',
                        style: context.text.bodySmall?.copyWith(color: context.nx.muted),
                      ),
                    ],
                  ),
                ),
                Builder(
                  builder: (buttonContext) => IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.more_vert_rounded),
                    onPressed: () => _showActions(buttonContext),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: (25 * (index % 12)).ms, duration: 300.ms).scale(begin: const Offset(0.96, 0.96));
  }

  Future<void> _showActions(BuildContext anchorContext) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final messengerContext = anchorContext;
    // Captured up front: the tile is gone after a delete, but the messenger isn't.
    final messenger = ScaffoldMessenger.of(anchorContext);
    final action = await showModalBottomSheet<String>(
      context: anchorContext,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(item.title, maxLines: 2, textAlign: TextAlign.center, style: context.text.titleMedium),
            ),
            if (!item.missing) ...[
              ListTile(leading: const Icon(Icons.open_in_new_rounded), title: const Text('Open'), onTap: () => Navigator.pop(context, 'open')),
              ListTile(leading: const Icon(Icons.ios_share_rounded), title: const Text('Share'), onTap: () => Navigator.pop(context, 'share')),
              if (Platform.isIOS && item.kind == MediaKind.video)
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded),
                  title: Text(item.savedToPhotos ? 'Save to Photos again' : 'Save to Photos'),
                  onTap: () => Navigator.pop(context, 'photos'),
                ),
            ],
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('Copy original link'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            if (!item.missing)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: NxColors.red),
                title: const Text('Delete file', style: TextStyle(color: NxColors.red)),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ListTile(
              leading: const Icon(Icons.playlist_remove_rounded),
              title: const Text('Remove from library'),
              subtitle: item.missing ? null : const Text('Keeps the file on your device'),
              onTap: () => Navigator.pop(context, 'forget'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !messengerContext.mounted) return;
    String? message;
    switch (action) {
      case 'open':
        message = await library.open(item);
      case 'share':
        message = await library.share(item, origin: origin);
      case 'photos':
        message = await library.saveToPhotos(item) ?? 'Added to Photos';
      case 'copy':
        await Clipboard.setData(ClipboardData(text: item.sourceUrl));
        message = 'Link copied';
      case 'delete':
        if (!messengerContext.mounted) return;
        final ok = await showDialog<bool>(
          context: messengerContext,
          builder: (context) => AlertDialog(
            title: const Text('Delete file?'),
            content: Text('“${item.title}” will be deleted from your device.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: NxColors.red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (ok == true) message = await library.remove(item, deleteFile: true) ?? 'Deleted';
      case 'forget':
        message = await library.remove(item, deleteFile: false);
    }
    if (message != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
