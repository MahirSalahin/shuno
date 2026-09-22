import 'package:flutter/material.dart';

import '../services/download_service.dart';
import '../services/playback_controller.dart';
import '../services/storage_service.dart';
import 'add_to_playlist_dialog.dart';

class FullPlayerSheet extends StatelessWidget {
  const FullPlayerSheet({
    super.key,
    required this.playback,
    required this.storage,
    this.downloadService,
    this.onOpenQueue,
  });

  final PlaybackController playback;
  final StorageService storage;
  final DownloadService? downloadService;
  final VoidCallback? onOpenQueue;

  static void show(
    BuildContext context, {
    required PlaybackController playback,
    required StorageService storage,
    DownloadService? downloadService,
    VoidCallback? onOpenQueue,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => AnimatedBuilder(
        animation: Listenable.merge([
          playback,
          storage,
          ?downloadService,
        ]),
        builder: (context, _) => FullPlayerSheet(
          playback: playback,
          storage: storage,
          downloadService: downloadService,
          onOpenQueue: onOpenQueue,
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      final hours = duration.inHours;
      final remainingMins = (minutes % 60).toString().padLeft(2, '0');
      return '$hours:$remainingMins:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final item = playback.selected;
    if (item == null) {
      return const SizedBox(
        height: 300,
        child: Center(child: Text('No song selected')),
      );
    }

    final theme = Theme.of(context);
    final isFav = storage.isFavorite(item.id);
    final isDownloaded = storage.isDownloaded(item.id);
    final isDownloading = downloadService?.isDownloading(item.id) ?? false;
    final duration = playback.duration > Duration.zero
        ? playback.duration
        : (item.duration ?? Duration.zero);
    final position = playback.position;
    final maxSeconds = duration.inSeconds.toDouble();
    final currentSeconds = position.inSeconds.toDouble().clamp(
      0.0,
      maxSeconds > 0 ? maxSeconds : 1.0,
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down),
                  tooltip: 'Minimize',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Text(
                  'NOW PLAYING',
                  style: theme.textTheme.labelMedium?.copyWith(
                    letterSpacing: 1.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.playlist_add),
                  tooltip: 'Add to playlist',
                  onPressed: () => AddToPlaylistDialog.show(
                    context,
                    item: item,
                    storageService: storage,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Artwork
            Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 320),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: item.thumbnailUrl.isNotEmpty
                        ? Image.network(
                            item.thumbnailUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  child: const Icon(Icons.music_note, size: 80),
                                ),
                          )
                        : Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.music_note, size: 80),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Title, Channel & Favorite
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.channelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  iconSize: 28,
                  icon: Icon(
                    isFav ? Icons.favorite : Icons.favorite_border,
                    color: isFav ? Colors.redAccent : null,
                  ),
                  tooltip: isFav ? 'Remove from favorites' : 'Add to favorites',
                  onPressed: () => storage.toggleFavorite(item),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Scrub Bar
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                trackHeight: 4,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: currentSeconds,
                min: 0.0,
                max: maxSeconds > 0 ? maxSeconds : 1.0,
                onChanged: maxSeconds > 0
                    ? (val) => playback.seek(Duration(seconds: val.toInt()))
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(position),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  Text(
                    _formatDuration(duration),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Playback Controls Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Shuffle
                IconButton(
                  icon: Icon(
                    Icons.shuffle,
                    color: playback.isShuffle ? theme.colorScheme.primary : null,
                  ),
                  tooltip: playback.isShuffle
                      ? 'Shuffle is on'
                      : 'Shuffle is off',
                  onPressed: playback.toggleShuffle,
                ),
                // Previous
                IconButton(
                  iconSize: 36,
                  icon: const Icon(Icons.skip_previous),
                  tooltip: 'Previous',
                  onPressed: playback.skipToPrevious,
                ),
                // Play / Pause / Replay
                if (playback.isLoading)
                  const SizedBox(
                    width: 64,
                    height: 64,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  )
                else
                  IconButton.filled(
                    iconSize: 40,
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(12),
                    ),
                    tooltip: playback.error != null
                        ? 'Retry'
                        : playback.isCompleted
                        ? 'Replay'
                        : playback.isPlaying
                        ? 'Pause'
                        : 'Play',
                    onPressed: playback.togglePlayback,
                    icon: Icon(
                      playback.error != null
                          ? Icons.refresh
                          : playback.isCompleted
                          ? Icons.replay
                          : playback.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                    ),
                  ),
                // Next
                IconButton(
                  iconSize: 36,
                  icon: const Icon(Icons.skip_next),
                  tooltip: 'Next',
                  onPressed: playback.skipToNext,
                ),
                // Repeat
                IconButton(
                  icon: Icon(
                    playback.loopMode == PlaybackLoopMode.one
                        ? Icons.repeat_one
                        : playback.loopMode == PlaybackLoopMode.all
                        ? Icons.repeat
                        : Icons.repeat,
                    color: playback.loopMode != PlaybackLoopMode.off
                        ? theme.colorScheme.primary
                        : null,
                  ),
                  tooltip: playback.loopMode == PlaybackLoopMode.one
                      ? 'Repeat One'
                      : playback.loopMode == PlaybackLoopMode.all
                      ? 'Repeat All'
                      : 'Repeat Off',
                  onPressed: playback.toggleLoopMode,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Bottom Actions: Download and Queue
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Download
                if (isDownloading)
                  TextButton.icon(
                    icon: const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    label: Text(
                      'Downloading ${((downloadService?.getProgress(item.id) ?? 0) * 100).toInt()}%',
                    ),
                    onPressed: () {
                      downloadService?.cancelDownload(item.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Download cancelled')),
                      );
                    },
                  )
                else if (isDownloaded)
                  TextButton.icon(
                    icon: const Icon(Icons.offline_pin, color: Colors.green),
                    label: const Text('Downloaded'),
                    onPressed: () {
                      downloadService?.deleteDownload(item.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Download deleted')),
                      );
                    },
                  )
                else
                  TextButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('Download'),
                    onPressed: () {
                      if (downloadService != null) {
                        downloadService!.downloadTrack(item);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Downloading "${item.title}"...'),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    },
                  ),
                // Queue Shortcut
                TextButton.icon(
                  icon: const Icon(Icons.queue_music),
                  label: Text('Queue (${playback.queue.length})'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    onOpenQueue?.call();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
