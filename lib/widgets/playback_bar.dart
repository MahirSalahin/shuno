import 'package:flutter/material.dart';

import '../services/download_service.dart';
import '../services/playback_controller.dart';
import '../services/storage_service.dart';
import 'full_player_sheet.dart';

class PlaybackBar extends StatelessWidget {
  const PlaybackBar({
    super.key,
    required this.controller,
    this.storageService,
    this.downloadService,
    this.onOpenQueue,
  });

  final PlaybackController controller;
  final StorageService? storageService;
  final DownloadService? downloadService;
  final VoidCallback? onOpenQueue;

  @override
  Widget build(BuildContext context) {
    final item = controller.selected;
    if (item == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final duration = controller.duration.inMilliseconds > 0
        ? controller.duration.inMilliseconds.toDouble()
        : (item.duration?.inMilliseconds.toDouble() ?? 1.0);
    final position = controller.position.inMilliseconds.toDouble();
    final progress = (position / (duration > 0 ? duration : 1.0)).clamp(
      0.0,
      1.0,
    );

    final error = controller.error;
    final status =
        error ??
        (controller.isLoading
            ? 'Loading audio…'
            : controller.isBuffering
            ? 'Buffering…'
            : controller.isCompleted
            ? 'Finished'
            : controller.isPlaying
            ? 'Playing'
            : 'Paused');

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      elevation: 6,
      child: InkWell(
        onTap: () {
          if (storageService != null) {
            FullPlayerSheet.show(
              context,
              playback: controller,
              storage: storageService!,
              downloadService: downloadService,
              onOpenQueue: onOpenQueue,
            );
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thin progress indicator along top of bar
            LinearProgressIndicator(
              value: controller.isLoading ? null : progress,
              minHeight: 2.5,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  // Thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: item.thumbnailUrl.isNotEmpty
                        ? Image.network(
                            item.thumbnailUrl,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            excludeFromSemantics: true,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  width: 48,
                                  height: 48,
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  child: const Icon(Icons.music_note, size: 24),
                                ),
                          )
                        : Container(
                            width: 48,
                            height: 48,
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.music_note, size: 24),
                          ),
                  ),
                  const SizedBox(width: 12),
                  // Title & Channel
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
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
                        const SizedBox(height: 2),
                        Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: error != null
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Play/Pause button
                  if (controller.isLoading)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          semanticsLabel: 'Loading audio',
                        ),
                      ),
                    )
                  else
                    IconButton(
                      tooltip: controller.error != null
                          ? 'Retry playback'
                          : controller.isCompleted
                          ? 'Replay'
                          : controller.isPlaying
                          ? 'Pause'
                          : 'Play',
                      onPressed: controller.togglePlayback,
                      icon: Icon(
                        controller.error != null
                            ? Icons.refresh
                            : controller.isCompleted
                            ? Icons.replay
                            : controller.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                      ),
                    ),
                  // Skip Next button
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    tooltip: 'Next',
                    onPressed: controller.hasNext ? controller.skipToNext : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
