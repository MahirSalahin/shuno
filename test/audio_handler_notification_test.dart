import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuno/models/youtube_search_item.dart';
import 'package:shuno/services/audio_handler.dart';
import 'package:shuno/services/playback_controller.dart';
import 'package:shuno/services/youtube_service.dart';

import 'helpers/fake_audio_player.dart';

class MockAudioHandlerYoutubeService extends YoutubeService {
  @override
  Future<Uri> resolveAudioUrl(String videoId, {bool highQuality = true}) async {
    return Uri.parse('https://example.com/$videoId.m4a');
  }
}

YoutubeSearchItem track(String id, {String title = 'Title', Duration? duration}) {
  return YoutubeSearchItem(
    id: id,
    title: '$title $id',
    channelName: 'Channel $id',
    thumbnailUrl: 'https://example.com/thumb_$id.jpg',
    duration: duration ?? const Duration(minutes: 3),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ShunoAudioHandler Notification & Lock Screen Controls', () {
    late ShunoAudioHandler audioHandler;
    late MockAudioHandlerYoutubeService youtubeService;
    late FakeAudioPlayer fakePlayer;
    late PlaybackController controller;

    setUp(() {
      audioHandler = ShunoAudioHandler();
      youtubeService = MockAudioHandlerYoutubeService();
      fakePlayer = FakeAudioPlayer();
      controller = PlaybackController(
        youtubeService: youtubeService,
        player: fakePlayer,
        audioHandler: audioHandler,
      );
      audioHandler.attachController(controller);
    });

    tearDown(() {
      controller.dispose();
    });

    test('syncPlaybackState configures previous, play/pause, next, and compact indices [0, 1, 2]', () {
      audioHandler.syncPlaybackState(
        isPlaying: true,
        isLoading: false,
        isBuffering: false,
        isCompleted: false,
        position: const Duration(seconds: 45),
        bufferedPosition: const Duration(seconds: 60),
        speed: 1.0,
        error: null,
        currentIndex: 0,
        hasPrevious: true,
        hasNext: true,
      );

      final state = audioHandler.playbackState.value;
      expect(state.playing, isTrue);
      expect(state.processingState, AudioProcessingState.ready);

      // Verify controls: Previous, Pause, Next, Stop
      expect(state.controls.length, 4);
      expect(state.controls[0].action, MediaAction.skipToPrevious);
      expect(state.controls[1].action, MediaAction.pause);
      expect(state.controls[2].action, MediaAction.skipToNext);
      expect(state.controls[3].action, MediaAction.stop);

      // Verify compact action indices: [0, 1, 2] -> Previous, Play/Pause, Next
      expect(state.androidCompactActionIndices, [0, 1, 2]);
      expect(state.systemActions, contains(MediaAction.skipToPrevious));
      expect(state.systemActions, contains(MediaAction.skipToNext));
      expect(state.systemActions, contains(MediaAction.seek));
    });

    test('syncPlaybackState switches control 1 between play and pause based on isPlaying', () {
      audioHandler.syncPlaybackState(
        isPlaying: false,
        isLoading: false,
        isBuffering: false,
        isCompleted: false,
        position: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: 1.0,
        error: null,
        currentIndex: 0,
        hasPrevious: false,
        hasNext: true,
      );

      final state = audioHandler.playbackState.value;
      expect(state.playing, isFalse);
      expect(state.controls[1].action, MediaAction.play);
      expect(state.androidCompactActionIndices, [0, 1, 2]);
    });

    test('updateMediaItemFromSearchItem populates metadata for notification display', () {
      final item = track('t1', title: 'Audiobook Chapter 1');
      audioHandler.updateMediaItemFromSearchItem(item);

      final media = audioHandler.mediaItem.value;
      expect(media, isNotNull);
      expect(media!.id, 't1');
      expect(media.title, 'Audiobook Chapter 1 t1');
      expect(media.album, 'Channel t1');
      expect(media.artUri, Uri.parse('https://example.com/thumb_t1.jpg'));
      expect(media.duration, const Duration(minutes: 3));
    });

    test('updateQueueFromSearchItems broadcasts queue list to OS media session', () {
      final items = [track('t1'), track('t2'), track('t3')];
      audioHandler.updateQueueFromSearchItems(items);

      final q = audioHandler.queue.value;
      expect(q.length, 3);
      expect(q[0].id, 't1');
      expect(q[1].id, 't2');
      expect(q[2].id, 't3');
    });

    test('remote skipToNext and skipToPrevious actions navigate the queue', () async {
      final items = [track('t1'), track('t2'), track('t3')];
      await controller.playQueue(items, initialIndex: 0);

      expect(controller.currentIndex, 0);
      expect(controller.selected?.id, 't1');
      expect(audioHandler.mediaItem.value?.id, 't1');

      // Tap Next in notification bar / lock screen
      await audioHandler.skipToNext();
      expect(controller.currentIndex, 1);
      expect(controller.selected?.id, 't2');
      expect(audioHandler.mediaItem.value?.id, 't2');

      // Tap Previous in notification bar / lock screen
      await audioHandler.skipToPrevious();
      expect(controller.currentIndex, 0);
      expect(controller.selected?.id, 't1');
      expect(audioHandler.mediaItem.value?.id, 't1');
    });

    test('remote play and pause actions toggle playback state', () async {
      await controller.playItem(track('t1'));
      expect(controller.isPlaying, isTrue);

      // Tap Pause in notification
      await audioHandler.pause();
      expect(controller.isPlaying, isFalse);
      expect(audioHandler.playbackState.value.controls[1].action, MediaAction.play);

      // Tap Play in notification
      await audioHandler.play();
      expect(controller.isPlaying, isTrue);
      expect(audioHandler.playbackState.value.controls[1].action, MediaAction.pause);
    });

    test('remote seek updates position and broadcasts updated state', () async {
      await controller.playItem(track('t1'));

      await audioHandler.seek(const Duration(seconds: 42));
      expect(controller.position, const Duration(seconds: 42));
      expect(fakePlayer.seeks.last, const Duration(seconds: 42));
      expect(audioHandler.playbackState.value.updatePosition, const Duration(seconds: 42));
    });

    test('remote stop clears queue and puts audio handler in idle state', () async {
      await controller.playItem(track('t1'));
      expect(controller.queue.isNotEmpty, isTrue);

      await audioHandler.stop();
      expect(controller.queue.isEmpty, isTrue);
      expect(controller.selected, isNull);
      expect(audioHandler.playbackState.value.processingState, AudioProcessingState.idle);
      expect(audioHandler.playbackState.value.playing, isFalse);
    });
  });
}

