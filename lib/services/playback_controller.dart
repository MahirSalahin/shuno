import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/youtube_search_item.dart';
import 'youtube_service.dart';

/// Owns a single foreground player. No queue or persistent playback state.
class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required YoutubeService youtubeService,
    AudioPlayer? player,
  }) : _youtubeService = youtubeService,
       _player = player;

  final YoutubeService _youtubeService;
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<PlayerException>? _errorSubscription;
  YoutubeSearchItem? _selected;
  String? _error;
  bool _loading = false;
  bool _disposed = false;
  bool _foreground = true;
  int _request = 0;

  YoutubeSearchItem? get selected => _selected;
  String? get error => _error;
  bool get isLoading => _loading;
  bool get isBuffering => _player?.processingState == ProcessingState.buffering;
  bool get isCompleted => _player?.processingState == ProcessingState.completed;
  bool get isPlaying =>
      (_player?.playing ?? false) && !isCompleted && _error == null;

  AudioPlayer _preparePlayer() {
    final player = _player ??= AudioPlayer();
    _stateSubscription ??= player.playerStateStream.listen((_) {
      if (!_disposed) notifyListeners();
    });
    _errorSubscription ??= player.errorStream.listen((_) {
      if (!_disposed) {
        _error = 'Playback failed. Check your connection or try another video.';
        notifyListeners();
      }
    });
    return player;
  }

  Future<void> playItem(YoutubeSearchItem item) async {
    // Keep stream resolution serial; result taps are disabled while loading.
    if (_disposed || _loading) return;
    final request = ++_request;
    _selected = item;
    _error = null;
    _loading = true;
    notifyListeners();

    try {
      final player = _preparePlayer();
      await player.stop();
      if (_disposed) return;
      final url = await _youtubeService.resolveAudioUrl(item.id);
      if (_disposed) return;
      await player.setUrl(url.toString()).timeout(const Duration(seconds: 20));
      if (_disposed) return;
      _loading = false;
      notifyListeners();
      if (_foreground && _error == null) unawaited(_play(request));
    } catch (error) {
      if (_disposed || request != _request) return;
      if (kDebugMode) debugPrint('Audio load failed: $error');
      _error = error is TimeoutException
          ? 'Audio loading timed out. Check your connection and retry.'
          : 'Could not play this video. Check your connection or try another video.';
      // Also cancels an audio load that continued after its timeout.
      try {
        await _player?.stop();
      } catch (_) {
        // Preserve the original load error.
      }
      if (!_disposed) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> togglePlayback() async {
    if (_disposed || _loading || _selected == null) return;
    if (_error != null) {
      await playItem(_selected!);
      return;
    }
    final player = _player;
    if (player == null) return;
    try {
      if (isPlaying) {
        await player.pause();
      } else {
        if (isCompleted) await player.seek(Duration.zero);
        if (!_disposed && _foreground) unawaited(_play(_request));
      }
    } catch (_) {
      if (!_disposed) {
        _error = 'Playback failed. Tap retry to reload this video.';
        notifyListeners();
      }
    }
  }

  Future<void> _play(int request) async {
    try {
      // play() completes when paused, stopped, or finished, not when started.
      await _player!.play();
    } catch (_) {
      if (!_disposed && request == _request) {
        _error = 'Playback failed. Tap retry to reload this video.';
        notifyListeners();
      }
    }
  }

  Future<void> setForeground(bool foreground) async {
    _foreground = foreground;
    if (!_disposed && !foreground) {
      try {
        await _player?.pause();
      } catch (_) {
        // A player may already be stopping after a load failure.
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    unawaited(_stateSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    unawaited(_player?.dispose());
    super.dispose();
  }
}
