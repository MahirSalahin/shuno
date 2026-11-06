import 'package:flutter/material.dart';

import '../services/download_service.dart';
import '../services/playback_controller.dart';
import '../services/storage_service.dart';
import 'full_player_sheet.dart';
import 'marquee_text.dart';

class PlaybackBar extends StatefulWidget {
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
  State<PlaybackBar> createState() => _PlaybackBarState();
}

class _PlaybackBarState extends State<PlaybackBar> {
  double _dragOffset = 0.0;
  bool _isDragging = false;
  int _transitionDirection = 0; // -1 for swiping left (next), 1 for swiping right (prev)
  String? _lastItemId;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final item = controller.selected;
        if (item == null) return const SizedBox.shrink();

        // Track when item changes to trigger a smooth transition
        if (_lastItemId != null && _lastItemId != item.id && _transitionDirection == 0) {
          _transitionDirection = -1;
        }
        _lastItemId = item.id;

        final theme = Theme.of(context);
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

        return RepaintBoundary(
          child: Padding(
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
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: (_) {
                  setState(() {
                    _isDragging = true;
                    _dragOffset = 0.0;
                  });
                },
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _dragOffset = (_dragOffset + (details.primaryDelta ?? 0.0))
                        .clamp(-140.0, 140.0);
                  });
                },
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0.0;
                  final shouldNext = _dragOffset < -35.0 || velocity < -200.0;
                  final shouldPrev = _dragOffset > 35.0 || velocity > 200.0;

                  if (shouldNext && controller.hasNext) {
                    _transitionDirection = -1;
                    controller.skipToNext();
                  } else if (shouldPrev) {
                    _transitionDirection = 1;
                    controller.skipToPrevious();
                  }

                  setState(() {
                    _isDragging = false;
                    _dragOffset = 0.0;
                  });
                },
                onHorizontalDragCancel: () {
                  if (_isDragging) {
                    setState(() {
                      _isDragging = false;
                      _dragOffset = 0.0;
                    });
                  }
                },
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (widget.storageService != null) {
                        FullPlayerSheet.show(
                          context,
                          playback: controller,
                          storage: widget.storageService!,
                          downloadService: widget.downloadService,
                          onOpenQueue: widget.onOpenQueue,
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
                                      cacheWidth: 140,
                                      cacheHeight: 140,
                                      fit: BoxFit.cover,
                                      excludeFromSemantics: true,
                                      errorBuilder: (context, error, stackTrace) =>
                                          Container(
                                        width: 46,
                                        height: 46,
                                        color: theme.colorScheme.surfaceContainerHighest,
                                        child: const Icon(Icons.graphic_eq, size: 22),
                                      ),
                                    )
                                  : Container(
                                      width: 46,
                                      height: 46,
                                      color: theme.colorScheme.surfaceContainerHighest,
                                      child: const Icon(Icons.graphic_eq, size: 22),
                                    ),
                            ),
                            const SizedBox(width: 12),

                            // Title & Subtitle Info with Live Interactive Horizontal Drag Offset
                            Expanded(
                              child: ClipRect(
                                child: AnimatedContainer(
                                  duration: _isDragging
                                      ? Duration.zero
                                      : const Duration(milliseconds: 240),
                                  curve: Curves.easeOutCubic,
                                  transform: Matrix4.translationValues(_dragOffset, 0, 0),
                                  child: Opacity(
                                    opacity: (1.0 - (_dragOffset.abs() / 200.0)).clamp(0.25, 1.0),
                                    child: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 220),
                                      transitionBuilder: (child, animation) {
                                        final inOffset = Tween<Offset>(
                                          begin: Offset(
                                            _transitionDirection < 0
                                                ? 0.35
                                                : (_transitionDirection > 0 ? -0.35 : 0.0),
                                            0.0,
                                          ),
                                          end: Offset.zero,
                                        ).animate(
                                          CurvedAnimation(
                                            parent: animation,
                                            curve: Curves.easeOutCubic,
                                          ),
                                        );

                                        return FadeTransition(
                                          opacity: animation,
                                          child: SlideTransition(
                                            position: inOffset,
                                            child: child,
                                          ),
                                        );
                                      },
                                      child: KeyedSubtree(
                                        key: ValueKey(item.id),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            MarqueeText(
                                              text: item.title,
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
                                    ),
                                  ),
                                ),
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
                      _PlaybackProgressBar(controller: controller),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        );
      },
    );
  }
}

class _PlaybackProgressBar extends StatelessWidget {
  const _PlaybackProgressBar({required this.controller});

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<Duration>(
      valueListenable: controller.positionNotifier,
      builder: (context, position, _) {
        final totalDuration = controller.duration.inMilliseconds > 0
            ? controller.duration.inMilliseconds.toDouble()
            : (controller.selected?.duration?.inMilliseconds.toDouble() ?? 1.0);
        final progress = (position.inMilliseconds /
                (totalDuration > 0 ? totalDuration : 1.0))
            .clamp(0.0, 1.0);

        return ClipRRect(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
          child: LinearProgressIndicator(
            value: controller.isLoading ? null : progress,
            minHeight: 2.5,
            backgroundColor: theme.colorScheme.outlineVariant.withAlpha(60),
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.primary,
            ),
          ),
        );
      },
    );
  }
}
