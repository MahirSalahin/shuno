import 'package:flutter/material.dart';

import '../models/youtube_search_item.dart';
import '../services/download_service.dart';
import '../services/playback_controller.dart';
import '../services/storage_service.dart';
import 'add_to_playlist_dialog.dart';

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.item,
    required this.playback,
    required this.storage,
    this.downloadService,
    this.onTap,
    this.trailingAction,
    this.trailingActionTooltip,
    this.onTrailingAction,
  });

  final YoutubeSearchItem item;
  final PlaybackController playback;
  final StorageService storage;
  final DownloadService? downloadService;
  final VoidCallback? onTap;
  final IconData? trailingAction;
  final String? trailingActionTooltip;
  final VoidCallback? onTrailingAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = playback.selected?.id == item.id;
    final isFav = storage.isFavorite(item.id);
    final isDownloaded = storage.isDownloaded(item.id);
    final isDownloading = downloadService?.isDownloading(item.id) ?? false;
    final duration = item.durationLabel;

    return Card(
      elevation: isSelected ? 2 : 0,
      color: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
          : theme.colorScheme.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ?? (playback.isLoading ? null : () => playback.playItem(item)),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              // Thumbnail
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: item.thumbnailUrl.isNotEmpty
                        ? Image.network(
                            item.thumbnailUrl,
                            width: 72,
                            height: 52,
                            fit: BoxFit.cover,
                            excludeFromSemantics: true,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  width: 72,
                                  height: 52,
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  child: const Icon(Icons.image_not_supported_outlined),
                                ),
                          )
                        : Container(
                            width: 72,
                            height: 52,
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.music_note),
                          ),
                  ),
                  if (isSelected)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          playback.isPlaying
                              ? Icons.graphic_eq
                              : Icons.pause_circle_outline,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              // Track Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: isSelected ? theme.colorScheme.primary : null,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.channelName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (isDownloaded) ...[
                          Icon(
                            Icons.offline_pin,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (isDownloading) ...[
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${((downloadService?.getProgress(item.id) ?? 0) * 100).toInt()}%',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (duration != null)
                          Text(
                            duration,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // Favorite button
              IconButton(
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border,
                  color: isFav ? Colors.redAccent : null,
                ),
                tooltip: isFav ? 'Remove from favorites' : 'Add to favorites',
                onPressed: () => storage.toggleFavorite(item),
              ),
              // Optional Trailing Action or Popup Menu
              if (trailingAction != null && onTrailingAction != null)
                IconButton(
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(trailingAction),
                  tooltip: trailingActionTooltip,
                  onPressed: onTrailingAction,
                )
              else
                PopupMenuButton<String>(
                  iconSize: 20,
                  tooltip: 'More options',
                  onSelected: (value) async {
                    switch (value) {
                      case 'play':
                        playback.playItem(item);
                        break;
                      case 'play_next':
                        playback.playNext(item);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Playing next')),
                        );
                        break;
                      case 'add_queue':
                        playback.addToQueue(item);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Added to queue')),
                        );
                        break;
                      case 'add_playlist':
                        AddToPlaylistDialog.show(
                          context,
                          item: item,
                          storageService: storage,
                        );
                        break;
                      case 'download':
                        if (downloadService != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Downloading "${item.title}"...'),
                              duration: const Duration(seconds: 3),
                            ),
                          );
                          downloadService!.downloadTrack(item);
                        }
                        break;
                      case 'delete_download':
                        if (downloadService != null) {
                          await downloadService!.deleteDownload(item.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Download deleted')),
                            );
                          }
                        }
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'play',
                      child: ListTile(
                        leading: Icon(Icons.play_arrow),
                        title: Text('Play'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'play_next',
                      child: ListTile(
                        leading: Icon(Icons.playlist_play),
                        title: Text('Play Next'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'add_queue',
                      child: ListTile(
                        leading: Icon(Icons.queue_music),
                        title: Text('Add to Queue'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'add_playlist',
                      child: ListTile(
                        leading: Icon(Icons.playlist_add),
                        title: Text('Add to Playlist'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    if (isDownloaded)
                      const PopupMenuItem(
                        value: 'delete_download',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('Remove Download'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      )
                    else
                      const PopupMenuItem(
                        value: 'download',
                        child: ListTile(
                          leading: Icon(Icons.download),
                          title: Text('Download for Offline'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
