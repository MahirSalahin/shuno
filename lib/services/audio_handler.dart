import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '../models/youtube_search_item.dart';
import 'playback_controller.dart';

/// Background audio handler integrating Shuno playback with the OS media session,
/// notification bar, and lock screen controls.
class ShunoAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  PlaybackController? _controller;
  bool _isStopping = false;

  /// Attaches the active [PlaybackController] to receive actions from the OS.
  void attachController(PlaybackController controller) {
    _controller = controller;
  }

  /// Detaches the [PlaybackController].
  void detachController() {
    _controller = null;
  }

  @override
  Future<void> play() async {
    final c = _controller;
    if (c == null) return;
    if (!c.isPlaying) {
      await c.togglePlayback();
    }
  }

  @override
  Future<void> pause() async {
    final c = _controller;
    if (c == null) return;
    if (c.isPlaying) {
      await c.togglePlayback();
    }
  }

  @override
  Future<void> stop() async {
    if (_isStopping) return;
    _isStopping = true;
    try {
      playbackState.add(
        PlaybackState(
          processingState: AudioProcessingState.idle,
          playing: false,
        ),
      );
      final c = _controller;
      if (c != null) {
        c.clearQueue();
      }
    } finally {
      _isStopping = false;
    }
  }

  @override
  Future<void> skipToNext() async {
    final c = _controller;
    if (c == null) return;
    await c.skipToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    final c = _controller;
    if (c == null) return;
    await c.skipToPrevious();
  }

  @override
  Future<void> seek(Duration position) async {
    final c = _controller;
    if (c == null) return;
    await c.seek(position);
  }

  @override
  Future<void> fastForward() async {
    final c = _controller;
    if (c == null) return;
    await c.seek(c.position + const Duration(seconds: 10));
  }

  @override
  Future<void> rewind() async {
    final c = _controller;
    if (c == null) return;
    final target = c.position - const Duration(seconds: 10);
    await c.seek(target < Duration.zero ? Duration.zero : target);
  }

  @override
  Future<void> setSpeed(double speed) async {
    final c = _controller;
    if (c == null) return;
    await c.setPlaybackSpeed(speed);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    final c = _controller;
    if (c == null) return;
    final q = c.queue;
    if (index >= 0 && index < q.length) {
      await c.playItem(q[index]);
    }
  }

  /// Updates the current media item shown in the notification and lock screen.
  void updateMediaItemFromSearchItem(YoutubeSearchItem? item) {
    if (item == null) {
      mediaItem.add(null);
      return;
    }

    mediaItem.add(
      MediaItem(
        id: item.id,
        album: item.channelName,
        title: item.title,
        artUri: item.thumbnailUrl.isNotEmpty ? Uri.tryParse(item.thumbnailUrl) : null,
        duration: item.duration,
      ),
    );
  }

  /// Updates the queue list broadcast to the OS media session.
  void updateQueueFromSearchItems(List<YoutubeSearchItem> items) {
    queue.add(
      items
          .map(
            (item) => MediaItem(
              id: item.id,
              album: item.channelName,
              title: item.title,
              artUri: item.thumbnailUrl.isNotEmpty
                  ? Uri.tryParse(item.thumbnailUrl)
                  : null,
              duration: item.duration,
            ),
          )
          .toList(),
    );
  }

  /// Synchronizes playback state, including notification controls and compact action indices.
  void syncPlaybackState({
    required bool isPlaying,
    required bool isLoading,
    required bool isBuffering,
    required bool isCompleted,
    required Duration position,
    required Duration bufferedPosition,
    required double speed,
    required String? error,
    required int? currentIndex,
    required bool hasPrevious,
    required bool hasNext,
  }) {
    final isIdle = currentIndex == null;
    final controls = isIdle
        ? const <MediaControl>[]
        : <MediaControl>[
            MediaControl.skipToPrevious,
            isPlaying ? MediaControl.pause : MediaControl.play,
            MediaControl.skipToNext,
            MediaControl.stop,
          ];

    final processingState = error != null
        ? AudioProcessingState.error
        : isIdle
            ? AudioProcessingState.idle
            : isBuffering
                ? AudioProcessingState.buffering
                : isCompleted
                    ? AudioProcessingState.completed
                    : isLoading
                        ? AudioProcessingState.loading
                        : AudioProcessingState.ready;

    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: isIdle
            ? const {}
            : const {
                MediaAction.seek,
                MediaAction.seekForward,
                MediaAction.seekBackward,
                MediaAction.skipToNext,
                MediaAction.skipToPrevious,
              },
        androidCompactActionIndices: isIdle ? null : const [0, 1, 2],
        processingState: processingState,
        playing: isPlaying && error == null && !isCompleted && !isIdle,
        updatePosition: position,
        bufferedPosition: bufferedPosition,
        speed: speed,
        queueIndex: currentIndex,
        errorMessage: error,
      ),
    );
  }
}
