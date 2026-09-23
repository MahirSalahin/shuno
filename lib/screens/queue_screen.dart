import 'package:flutter/material.dart';

import '../services/download_service.dart';
import '../services/playback_controller.dart';
import '../services/storage_service.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/full_player_sheet.dart';
import '../widgets/track_tile.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({
    super.key,
    required this.playback,
    required this.storage,
    this.downloadService,
  });

  final PlaybackController playback;
  final StorageService storage;
  final DownloadService? downloadService;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        playback,
        storage,
        ?downloadService,
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final currentItem = playback.selected;
        final currentIndex = playback.currentIndex;
        final upNext = playback.upNext;
        final previous = playback.previousTracks;

        return Scaffold(
      appBar: AppBar(
        title: const Text('Playing Queue'),
        actions: [
          if (upNext.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.clear_all, size: 18),
              label: const Text('Clear Up Next'),
              onPressed: () async {
                final confirm = await showConfirmDialog(
                  context,
                  title: 'Clear Up Next?',
                  message:
                      'Are you sure you want to remove all upcoming tracks from the queue?',
                  confirmLabel: 'Clear',
                );
                if (confirm && context.mounted) {
                  playback.clearUpNext();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Upcoming queue cleared')),
                  );
                }
              },
            )
          else if (playback.queue.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.delete_sweep, size: 18),
              label: const Text('Clear Queue'),
              onPressed: () async {
                final confirm = await showConfirmDialog(
                  context,
                  title: 'Clear Queue?',
                  message:
                      'Are you sure you want to clear the entire playback queue?',
                  confirmLabel: 'Clear',
                );
                if (confirm && context.mounted) {
                  playback.clearQueue();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Queue cleared')),
                  );
                }
              },
            ),
        ],
      ),
      body: currentItem == null && playback.queue.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.queue_music,
                    size: 64,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your queue is empty',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Search for music and tap play or add to queue',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. NOW PLAYING SECTION (Only the current track)
                if (currentItem != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'NOW PLAYING',
                          style: theme.textTheme.labelMedium?.copyWith(
                            letterSpacing: 1.2,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => showSpeedPickerSheet(context, playback),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: playback.playbackSpeed != 1.0
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.outlineVariant.withAlpha(120),
                                    width: 1,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                  color: playback.playbackSpeed != 1.0
                                      ? theme.colorScheme.primary.withAlpha(30)
                                      : Colors.transparent,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.speed,
                                      size: 13,
                                      color: playback.playbackSpeed != 1.0
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      playback.playbackSpeed == 1.0
                                          ? '1x'
                                          : '${playback.playbackSpeed}x',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: playback.playbackSpeed != 1.0
                                            ? theme.colorScheme.primary
                                            : theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (playback.loopMode != PlaybackLoopMode.off) ...[
                              const SizedBox(width: 8),
                              Text(
                                playback.loopMode == PlaybackLoopMode.one
                                    ? 'Repeat One'
                                    : 'Repeat All',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  TrackTile(
                    item: currentItem,
                    playback: playback,
                    storage: storage,
                    downloadService: downloadService,
                  ),
                  const Divider(height: 20),
                ],

                // 2. PREVIOUSLY PLAYED (Collapsible, only if there are prior tracks)
                if (previous.isNotEmpty)
                  Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      dense: true,
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                      leading: const Icon(Icons.history, size: 18),
                      title: Text(
                        'Previously Played (${previous.length})',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      children: [
                        for (final prev in previous)
                          ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: prev.thumbnailUrl.isNotEmpty
                                  ? Image.network(
                                      prev.thumbnailUrl,
                                      width: 44,
                                      height: 32,
                                      cacheWidth: 132,
                                      cacheHeight: 96,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const Icon(Icons.music_note),
                                    )
                                  : const Icon(Icons.music_note),
                            ),
                            title: Text(
                              prev.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            subtitle: Text(
                              prev.channelName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.replay, size: 18),
                              tooltip: 'Play again',
                              onPressed: () => playback.playItem(prev),
                            ),
                            onTap: () => playback.playItem(prev),
                          ),
                      ],
                    ),
                  ),

                // 3. UP NEXT SECTION (Strictly upcoming tracks)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    'UP NEXT (${upNext.length})',
                    style: theme.textTheme.labelMedium?.copyWith(
                      letterSpacing: 1.2,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                Expanded(
                  child: upNext.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.playlist_play,
                                  size: 48,
                                  color: theme.colorScheme.outline,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No upcoming tracks',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Tracks added with "Play Next" or "Add to Queue" will appear here.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.only(bottom: 100),
                          itemCount: upNext.length,
                          onReorder: (oldIndex, newIndex) {
                            final actualOld = currentIndex + 1 + oldIndex;
                            final actualNew = currentIndex + 1 + newIndex;
                            playback.reorder(actualOld, actualNew);
                          },
                          itemBuilder: (context, index) {
                            final item = upNext[index];
                            final actualIndex = currentIndex + 1 + index;

                            return Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant
                                      .withAlpha(50),
                                  width: 0.8,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Dismissible(
                                key: ValueKey('upnext_${item.id}_$actualIndex'),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  color: theme.colorScheme.error,
                                  child: const Icon(
                                    Icons.delete,
                                    color: Colors.white,
                                  ),
                                ),
                                confirmDismiss: (_) async {
                                  return await showConfirmDialog(
                                    context,
                                    title: 'Remove from Queue?',
                                    message:
                                        'Remove "${item.title}" from queue?',
                                    confirmLabel: 'Remove',
                                  );
                                },
                                onDismissed: (_) =>
                                    playback.removeAt(actualIndex),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 0,
                                  ),
                                  leading: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ReorderableDragStartListener(
                                        index: index,
                                        child: Icon(
                                          Icons.drag_indicator,
                                          color: theme.colorScheme.outline,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: item.thumbnailUrl.isNotEmpty
                                            ? Image.network(
                                                item.thumbnailUrl,
                                                width: 40,
                                                height: 40,
                                                cacheWidth: 120,
                                                cacheHeight: 120,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error,
                                                        stackTrace) =>
                                                    Container(
                                                  width: 40,
                                                  height: 40,
                                                  color: theme.colorScheme.surfaceContainerHighest,
                                                  child: const Icon(Icons.music_note, size: 20),
                                                ),
                                              )
                                            : Container(
                                                width: 40,
                                                height: 40,
                                                color: theme.colorScheme.surfaceContainerHighest,
                                                child: const Icon(Icons.music_note, size: 20),
                                              ),
                                      ),
                                    ],
                                  ),
                                  title: Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  subtitle: Text(
                                    item.channelName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    tooltip: 'Remove from queue',
                                    onPressed: () async {
                                      final confirm = await showConfirmDialog(
                                        context,
                                        title: 'Remove from Queue?',
                                        message:
                                            'Remove "${item.title}" from queue?',
                                        confirmLabel: 'Remove',
                                      );
                                      if (confirm) {
                                        playback.removeAt(actualIndex);
                                      }
                                    },
                                  ),
                                  onTap: () => playback.playItem(item),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
        );
      },
    );
  }
}
