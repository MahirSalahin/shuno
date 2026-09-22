import 'package:flutter/material.dart';

import '../services/playback_controller.dart';

class PlaybackBar extends StatelessWidget {
  const PlaybackBar({super.key, required this.controller});

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    final item = controller.selected;
    if (item == null) return const SizedBox.shrink();

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
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    item.channelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    status,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: error == null
                          ? null
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
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
              IconButton.filledTonal(
                tooltip: error != null
                    ? 'Retry playback'
                    : controller.isCompleted
                    ? 'Replay'
                    : controller.isPlaying
                    ? 'Pause'
                    : 'Play',
                onPressed: controller.togglePlayback,
                icon: Icon(
                  error != null
                      ? Icons.refresh
                      : controller.isCompleted
                      ? Icons.replay
                      : controller.isPlaying
                      ? Icons.pause
                      : Icons.play_arrow,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
