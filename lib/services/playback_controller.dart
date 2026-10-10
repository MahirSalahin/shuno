import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models/youtube_search_item.dart';
import 'storage_service.dart';
import 'youtube_service.dart';

enum PlaybackLoopMode { off, all, one }

class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required YoutubeService youtubeService,
    StorageService? storageService,
    AudioPlayer? player,
    bool pauseOnBackground = false,
  }) : _youtubeService = youtubeService,
       _storageService = storageService,
       _player = player,
       _pauseOnBackground = pauseOnBackground,
       _playbackSpeed = storageService?.playbackSpeed ?? 1.0;

  final YoutubeService _youtubeService;
  final StorageService? _storageService;
  final bool _pauseOnBackground;
  AudioPlayer? _player;
  double _playbackSpeed;

  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<PlayerException>? _errorSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<Duration>? _bufferedSubscription;

  final List<YoutubeSearchItem> _queue = [];
  int _currentIndex = -1;

  YoutubeSearchItem? _selected;
  String? _error;
  bool _loading = false;
  bool _disposed = false;
  bool _foreground = true;
  int _request = 0;

  PlaybackLoopMode _loopMode = PlaybackLoopMode.off;
  bool _isShuffle = false;
  List<YoutubeSearchItem> _originalQueueOrder = [];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _bufferedPosition = Duration.zero;

  Timer? _sleepTimer;
  Timer? _sleepTimerTicker;
  DateTime? _sleepTimerEndTime;
  bool _sleepAtEndOfTrack = false;
  DateTime _lastPositionSave = DateTime.fromMillisecondsSinceEpoch(0);

  List<YoutubeSearchItem> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  YoutubeSearchItem? get selected => _selected;
  String? get error => _error;
  bool get isLoading => _loading;
  bool get isBuffering => _player?.processingState == ProcessingState.buffering;
  bool get isCompleted => _player?.processingState == ProcessingState.completed;
  bool get isPlaying =>
      (_player?.playing ?? false) && !isCompleted && _error == null;

  PlaybackLoopMode get loopMode => _loopMode;
  bool get isShuffle => _isShuffle;
  Duration get position => _position;
  Duration get duration => _duration;
  Duration get bufferedPosition => _bufferedPosition;
  bool get hasNext =>
      _loopMode == PlaybackLoopMode.all ||
      _currentIndex + 1 < _queue.length ||
      (_storageService != null && _storageService.autoplay);
  bool get hasPrevious => _currentIndex > 0 || _position.inSeconds > 3;

  bool get hasSleepTimer => _sleepTimer != null || _sleepAtEndOfTrack;
  bool get isSleepAtEndOfTrack => _sleepAtEndOfTrack;
  Duration? get sleepTimerRemaining {
    if (_sleepTimerEndTime == null) return null;
    final diff = _sleepTimerEndTime!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  String? get sleepTimerRemainingFormatted {
    if (_sleepAtEndOfTrack) return 'End of track';
    final rem = sleepTimerRemaining;
    if (rem == null) return null;
    final minutes = rem.inMinutes;
    final seconds = rem.inSeconds % 60;
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  void setSleepTimer(Duration? duration, {bool endOfTrack = false}) {
    cancelSleepTimer();
    if (endOfTrack) {
      _sleepAtEndOfTrack = true;
      notifyListeners();
      return;
    }
    if (duration != null && duration > Duration.zero) {
      _sleepTimerEndTime = DateTime.now().add(duration);
      _sleepTimer = Timer(duration, () {
        cancelSleepTimer();
        _player?.pause();
        notifyListeners();
      });
      _sleepTimerTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_disposed) {
          notifyListeners();
        }
      });
      notifyListeners();
    }
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerTicker?.cancel();
    _sleepTimerTicker = null;
    _sleepTimerEndTime = null;
    _sleepAtEndOfTrack = false;
    notifyListeners();
  }

  double get playbackSpeed => _playbackSpeed;

  Future<void> setPlaybackSpeed(double speed) async {
    if (speed <= 0 || _playbackSpeed == speed) return;
    _playbackSpeed = speed;
    if (_player != null) {
      await _player!.setSpeed(speed);
    }
    await _storageService?.setPlaybackSpeed(speed);
    notifyListeners();
  }

  void _saveOfflinePositionIfNeeded(Duration pos, {bool force = false}) {
    final sel = _selected;
    if (sel == null || _storageService == null) return;
    if (!_storageService.isDownloaded(sel.id)) return;

    final now = DateTime.now();
    if (force || now.difference(_lastPositionSave).inSeconds >= 3) {
      _lastPositionSave = now;
      _storageService.updatePlaybackPosition(sel.id, pos);
    }
  }

  AudioPlayer _preparePlayer() {
    final player = _player ??= AudioPlayer();
    if (_playbackSpeed != 1.0) {
      player.setSpeed(_playbackSpeed);
    }
    _stateSubscription ??= player.playerStateStream.listen((state) {
      if (_disposed) return;
      if (state.processingState == ProcessingState.completed) {
        _onTrackCompleted();
      }
      notifyListeners();
    });

    _errorSubscription ??= player.errorStream.listen((_) {
      if (!_disposed) {
        _error = 'Playback failed. Check your connection or try another video.';
        notifyListeners();
      }
    });

    _positionSubscription ??= player.positionStream.listen((pos) {
      if (!_disposed) {
        _position = pos;
        _saveOfflinePositionIfNeeded(pos);
        notifyListeners();
      }
    });

    _durationSubscription ??= player.durationStream.listen((dur) {
      if (!_disposed && dur != null) {
        _duration = dur;
        notifyListeners();
      }
    });

    _bufferedSubscription ??= player.bufferedPositionStream.listen((buf) {
      if (!_disposed) {
        _bufferedPosition = buf;
        notifyListeners();
      }
    });

    return player;
  }

  List<YoutubeSearchItem> get upNext {
    if (_currentIndex < 0 || _currentIndex + 1 >= _queue.length) {
      return const [];
    }
    return List.unmodifiable(_queue.sublist(_currentIndex + 1));
  }

  List<YoutubeSearchItem> get previousTracks {
    if (_currentIndex <= 0) {
      return const [];
    }
    return List.unmodifiable(_queue.sublist(0, _currentIndex));
  }

  void clearUpNext() {
    if (_queue.isEmpty || _currentIndex < 0) return;
    if (_currentIndex + 1 < _queue.length) {
      _queue.removeRange(_currentIndex + 1, _queue.length);
      notifyListeners();
    }
  }

  Future<void> playItem(YoutubeSearchItem item, {Duration? initialPosition}) async {
    if (_disposed || _loading) return;
    // If item is already in queue, jump to it. Otherwise, insert after current track.
    final existingIndex = _queue.indexWhere((e) => e.id == item.id);
    if (existingIndex >= 0) {
      _currentIndex = existingIndex;
    } else if (_queue.isEmpty || _currentIndex < 0) {
      _queue.add(item);
      _currentIndex = 0;
    } else {
      _currentIndex++;
      _queue.insert(_currentIndex, item);
    }
    await _loadAndPlay(item, initialPosition: initialPosition);
  }

  Future<void> playQueue(
    List<YoutubeSearchItem> items, {
    int initialIndex = 0,
  }) async {
    if (items.isEmpty) return;
    _queue.clear();
    _queue.addAll(items);
    _originalQueueOrder = List.of(items);
    _currentIndex = initialIndex.clamp(0, _queue.length - 1);
    await _loadAndPlay(_queue[_currentIndex]);
  }

  void addToQueue(YoutubeSearchItem item) {
    if (!_queue.any((e) => e.id == item.id)) {
      _queue.add(item);
      notifyListeners();
      if (_selected == null && !_loading) {
        playItem(item);
      }
    }
  }

  void playNext(YoutubeSearchItem item) {
    if (_queue.isEmpty || _currentIndex < 0) {
      playItem(item);
      return;
    }
    _queue.removeWhere((e) => e.id == item.id);
    final insertIndex = (_currentIndex + 1).clamp(0, _queue.length);
    _queue.insert(insertIndex, item);
    notifyListeners();
  }

  void removeAt(int index) {
    if (index < 0 || index >= _queue.length) return;
    final isCurrent = index == _currentIndex;
    _queue.removeAt(index);
    if (_currentIndex > index) {
      _currentIndex--;
    } else if (isCurrent) {
      if (_queue.isEmpty) {
        _currentIndex = -1;
        _selected = null;
        _player?.stop();
      } else {
        _currentIndex = _currentIndex.clamp(0, _queue.length - 1);
        _loadAndPlay(_queue[_currentIndex]);
      }
    }
    notifyListeners();
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex > oldIndex) newIndex--;
    final item = _queue.removeAt(oldIndex);
    final clampedNewIndex = newIndex.clamp(0, _queue.length);
    _queue.insert(clampedNewIndex, item);
    if (_selected != null) {
      _currentIndex = _queue.indexOf(_selected!);
    }
    notifyListeners();
  }

  void clearQueue() {
    _queue.clear();
    _currentIndex = -1;
    _selected = null;
    _player?.stop();
    notifyListeners();
  }

  Future<void> _loadAndPlay(
    YoutubeSearchItem item, {
    Duration? initialPosition,
  }) async {
    if (_disposed) return;
    final request = ++_request;

    // Save playback position of outgoing offline track if any
    if (_selected != null && _storageService != null && _position > Duration.zero) {
      _saveOfflinePositionIfNeeded(_position, force: true);
    }

    _selected = item;
    _error = null;
    _loading = true;
    _position = initialPosition ?? Duration.zero;
    _duration = item.duration ?? Duration.zero;
    notifyListeners();

    try {
      final player = _preparePlayer();
      await player.stop();
      if (_disposed) return;

      AudioSource audioSource;
      final isOffline = _storageService?.isDownloaded(item.id) ?? false;
      final downloadItem = _storageService?.getDownload(item.id);

      // Determine initial seek position: explicit or stored progress
      Duration? startPos = initialPosition;
      if (startPos == null &&
          isOffline &&
          downloadItem != null &&
          downloadItem.hasPlaybackProgress) {
        startPos = downloadItem.lastPosition;
      }
      if (startPos != null) {
        _position = startPos;
      }

      final mediaItem = MediaItem(
        id: item.id,
        album: item.channelName,
        title: item.title,
        artUri: item.thumbnailUrl.isNotEmpty
            ? Uri.tryParse(item.thumbnailUrl)
            : null,
        duration: item.duration,
      );

      if (isOffline &&
          downloadItem != null &&
          File(downloadItem.localPath).existsSync()) {
        audioSource = AudioSource.file(downloadItem.localPath, tag: mediaItem);
        await player.setAudioSource(
          audioSource,
          initialPosition: startPos,
        ).timeout(
          const Duration(seconds: 20),
        );
      } else {
        final highQuality = (_storageService?.audioQuality ?? 'high') == 'high';
        final url = await _youtubeService.resolveAudioUrl(
          item.id,
          highQuality: highQuality,
        );
        if (_disposed) return;

        audioSource = AudioSource.uri(
          url,
          tag: mediaItem,
        );
        await player.setAudioSource(
          audioSource,
          initialPosition: startPos,
        ).timeout(
          const Duration(seconds: 20),
        );
      }
      if (_playbackSpeed != 1.0) {
        await player.setSpeed(_playbackSpeed);
      }

      if (_disposed || request != _request) return;
      _loading = false;
      notifyListeners();

      // Record in play history
      unawaited(_storageService?.addToHistory(item));

      if ((_foreground || !_pauseOnBackground) && _error == null) {
        unawaited(_play(request));
      }
    } catch (error, stack) {
      if (_disposed || request != _request) return;
      debugPrint('Audio load failed: $error\n$stack');
      final errStr = error.toString();
      _error = errStr.contains('403')
          ? 'YouTube restricted playback for this video (403). Try another video.'
          : (errStr.contains('429') || errStr.contains('RequestLimitExceededException'))
          ? 'YouTube is temporarily rate-limiting requests. Please wait a moment.'
          : error is TimeoutException
          ? 'Audio loading timed out. Check your connection and retry.'
          : 'Could not play this video. Check your connection or try another video.';
      try {
        await _player?.stop();
      } catch (_) {}
      if (!_disposed) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> togglePlayback() async {
    if (_disposed || _loading || _selected == null) return;
    if (_error != null) {
      await _loadAndPlay(_selected!);
      return;
    }
    final player = _player;
    if (player == null) return;
    try {
      if (isPlaying) {
        _saveOfflinePositionIfNeeded(_position, force: true);
        await player.pause();
      } else {
        if (isCompleted) await player.seek(Duration.zero);
        if (!_disposed && (_foreground || !_pauseOnBackground)) {
          unawaited(_play(_request));
        }
      }
    } catch (_) {
      if (!_disposed) {
        _error = 'Playback failed. Tap retry to reload this video.';
        notifyListeners();
      }
    }
  }

  Future<void> skipToNext() async {
    if (_disposed || _loading) return;

    if (_currentIndex + 1 < _queue.length) {
      _currentIndex++;
      await _loadAndPlay(_queue[_currentIndex]);
      return;
    }

    if (_loopMode == PlaybackLoopMode.all && _queue.isNotEmpty) {
      _currentIndex = 0;
      await _loadAndPlay(_queue[0]);
      return;
    }

    // Autoplay: fetch related videos if enabled
    if ((_storageService != null && _storageService.autoplay) && _selected != null) {
      try {
        final related = await _youtubeService.getRelatedVideos(_selected!);
        if (_disposed) return;
        final unplayed = related.where((r) => !_queue.any((q) => q.id == r.id));
        if (unplayed.isNotEmpty) {
          final nextItem = unplayed.first;
          _queue.add(nextItem);
          _currentIndex = _queue.length - 1;
          await _loadAndPlay(nextItem);
          return;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Autoplay fetch failed: $e');
      }
    }

    // Otherwise stop playback
    await _player?.stop();
  }

  Future<void> skipToPrevious() async {
    if (_disposed || _loading) return;

    if (_position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    if (_currentIndex > 0) {
      _currentIndex--;
      await _loadAndPlay(_queue[_currentIndex]);
    } else {
      await seek(Duration.zero);
    }
  }

  Future<void> seek(Duration position) async {
    if (_disposed || _player == null) return;
    try {
      await _player!.seek(position);
      _position = position;
      _saveOfflinePositionIfNeeded(position, force: true);
      notifyListeners();
    } catch (_) {}
  }

  void setLoopMode(PlaybackLoopMode mode) {
    _loopMode = mode;
    notifyListeners();
  }

  void toggleLoopMode() {
    switch (_loopMode) {
      case PlaybackLoopMode.off:
        setLoopMode(PlaybackLoopMode.all);
        break;
      case PlaybackLoopMode.all:
        setLoopMode(PlaybackLoopMode.one);
        break;
      case PlaybackLoopMode.one:
        setLoopMode(PlaybackLoopMode.off);
        break;
    }
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    if (_isShuffle) {
      _originalQueueOrder = List.of(_queue);
      if (_selected != null) {
        final remaining = _queue.where((e) => e.id != _selected!.id).toList()
          ..shuffle();
        _queue.clear();
        _queue.add(_selected!);
        _queue.addAll(remaining);
        _currentIndex = 0;
      } else {
        _queue.shuffle();
      }
    } else {
      if (_originalQueueOrder.isNotEmpty) {
        _queue.clear();
        _queue.addAll(_originalQueueOrder);
        if (_selected != null) {
          _currentIndex = _queue.indexOf(_selected!);
        }
      }
    }
    notifyListeners();
  }

  Future<void> _onTrackCompleted() async {
    if (_disposed) return;

    // Reset offline progress for completed track
    if (_selected != null && _storageService != null) {
      _storageService.clearPlaybackPosition(_selected!.id);
    }

    // Check sleep at end of track
    if (_sleepAtEndOfTrack) {
      cancelSleepTimer();
      await _player?.pause();
      return;
    }

    if (_loopMode == PlaybackLoopMode.one) {
      await seek(Duration.zero);
      unawaited(_play(_request));
      return;
    }
    if (_currentIndex + 1 < _queue.length ||
        (_loopMode == PlaybackLoopMode.all && _queue.isNotEmpty) ||
        (_storageService != null && _storageService.autoplay)) {
      await skipToNext();
    }
  }

  Future<void> _play(int request) async {
    try {
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
    if (_pauseOnBackground && !_disposed && !foreground) {
      try {
        await _player?.pause();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    if (_selected != null && _position > Duration.zero) {
      _saveOfflinePositionIfNeeded(_position, force: true);
    }
    cancelSleepTimer();
    unawaited(_stateSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    unawaited(_positionSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    unawaited(_bufferedSubscription?.cancel());
    unawaited(_player?.dispose());
    super.dispose();
  }
}
