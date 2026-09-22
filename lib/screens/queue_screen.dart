import 'package:flutter/material.dart';

import '../services/download_service.dart';
import '../services/playback_controller.dart';
import '../services/storage_service.dart';
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
    final theme = Theme.of(context);
    final queue = playback.queue;
    final currentIndex = playback.currentIndex;
    final currentItem = playback.selected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Playing Queue'),
        actions: [
          if (queue.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear'),
              onPressed: () {
                playback.clearQueue();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Queue cleared')),
                );
              },
            ),
        ],
      ),
      body: queue.isEmpty
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
                    'Search for music and add songs to the queue',
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
                if (currentItem != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      'NOW PLAYING',
                      style: theme.textTheme.labelMedium?.copyWith(
                        letterSpacing: 1.2,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TrackTile(
                    item: currentItem,
                    playback: playback,
                    storage: storage,
                    downloadService: downloadService,
                  ),
                  const Divider(height: 24),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'UP NEXT (${queue.length})',
                        style: theme.textTheme.labelMedium?.copyWith(
                          letterSpacing: 1.2,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (playback.loopMode != PlaybackLoopMode.off)
                        Text(
                          playback.loopMode == PlaybackLoopMode.one
                              ? 'Repeat One'
                              : 'Repeat All',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: queue.length,
                    onReorder: playback.reorder,
                    itemBuilder: (context, index) {
                      final item = queue[index];
                      final isCurrent = index == currentIndex;

                      return Dismissible(
                        key: ValueKey('queue_${item.id}_$index'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: theme.colorScheme.error,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => playback.removeAt(index),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ReorderableDragStartListener(
                                index: index,
                                child: const Icon(Icons.drag_handle),
                              ),
                              const SizedBox(width: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: item.thumbnailUrl.isNotEmpty
                                    ? Image.network(
                                        item.thumbnailUrl,
                                        width: 44,
                                        height: 32,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) =>
                                            const Icon(Icons.music_note),
                                      )
                                    : const Icon(Icons.music_note),
                              ),
                            ],
                          ),
                          title: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isCurrent
                                  ? theme.colorScheme.primary
                                  : null,
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            item.channelName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: 'Remove from queue',
                            onPressed: () => playback.removeAt(index),
                          ),
                          onTap: () => playback.playItem(item),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
