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

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withAlpha(16),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(120),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                  child: Row(
                    children: [
                      // Rounded Thumbnail
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: item.thumbnailUrl.isNotEmpty
                            ? Image.network(
                                item.thumbnailUrl,
                                width: 46,
                                height: 46,
                                fit: BoxFit.cover,
                                excludeFromSemantics: true,
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(
                                  width: 46,
                                  height: 46,
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  child: const Icon(Icons.music_note, size: 22),
                                ),
                              )
                            : Container(
                                width: 46,
                                height: 46,
                                color: theme.colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.music_note, size: 22),
                              ),
                      ),
                      const SizedBox(width: 12),

                      // Title & Subtitle Info
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
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                if (controller.isLoading || controller.isBuffering) ...[
                                  Container(
                                    width: 6,
                                    height: 6,
                                    margin: const EdgeInsets.only(right: 6),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                                Expanded(
                                  child: Text(
                                    error ?? status,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: error != null
                                          ? theme.colorScheme.error
                                          : theme.colorScheme.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),

                      // Play/Pause circular accent button
                      if (controller.isLoading)
                        const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              semanticsLabel: 'Loading audio',
                            ),
                          ),
                        )
                      else
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withAlpha(35),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            iconSize: 22,
                            padding: EdgeInsets.zero,
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
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),

                      // Skip Next button
                      IconButton(
                        iconSize: 22,
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        icon: const Icon(Icons.skip_next),
                        tooltip: 'Next',
                        onPressed: controller.hasNext ? controller.skipToNext : null,
                      ),
                    ],
                  ),
                ),

                // Bottom-pinned curved progress bar
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                  child: LinearProgressIndicator(
                    value: controller.isLoading ? null : progress,
                    minHeight: 2.5,
                    backgroundColor: theme.colorScheme.outlineVariant.withAlpha(60),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.colorScheme.primary,
                    ),
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
