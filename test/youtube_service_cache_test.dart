import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shuno/models/youtube_search_item.dart';
import 'package:shuno/services/playback_controller.dart';
import 'package:shuno/services/youtube_service.dart';

import 'helpers/fake_audio_player.dart';

class MockDeduplicatingYoutubeService extends YoutubeService {
  int internalCallCount = 0;
  Completer<Uri>? pendingCompleter;

  @override
  Future<Uri> resolveAudioUrlInternal(
    String videoId, {
    required bool highQuality,
    required String cacheKey,
  }) async {
    internalCallCount++;
    if (pendingCompleter != null) {
      return pendingCompleter!.future;
    }
    return cacheResolvedUrl(
      cacheKey,
      Uri.parse('https://example.com/audio.m4a?expire=1710000000&id=$videoId'),
    );
  }
}

class TestableYoutubeService extends YoutubeService {
  final clearedIds = <String>[];

  @override
  void clearCachedUrl(String videoId) {
    clearedIds.add(videoId);
    super.clearCachedUrl(videoId);
  }

  @override
  Future<Uri> resolveAudioUrl(String videoId, {bool highQuality = true}) async {
    return Uri.parse('https://rr1---sn-abc.googlevideo.com/videoplayback?expire=1710000000&id=$videoId');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YoutubeService caching and eviction', () {
    test('clearCachedUrl removes entries from cache', () {
      final service = YoutubeService();
      expect(service.hasCachedUrl('test_video_1'), isFalse);

      service.clearCachedUrl('test_video_1');
      expect(service.hasCachedUrl('test_video_1'), isFalse);
      service.dispose();
    });

    test('dispose clears cache and handles repeated disposal gracefully', () {
      final service = YoutubeService();
      service.dispose();
      // Second dispose should not throw
      service.dispose();
      expect(service.hasCachedUrl('any_id'), isFalse);
    });

    test('PlaybackController calls clearCachedUrl when audio loading fails', () async {
      final youtube = TestableYoutubeService();
      final player = FakeAudioPlayer();
      player.loadError = Exception('403 Forbidden: stream expired or restricted');

      final controller = PlaybackController(
        youtubeService: youtube,
        player: player,
      );

      const track = YoutubeSearchItem(
        id: 'expired_vid_123',
        title: 'Title',
        channelName: 'Channel',
        thumbnailUrl: '',
      );

      // Play track which will fail on player.setAudioSource
      await controller.playItem(track);

      expect(controller.error, contains('403'));
      expect(youtube.clearedIds, contains('expired_vid_123'));

      controller.dispose();
      youtube.dispose();
    });

    test('concurrent calls to resolveAudioUrl deduplicate in-flight and only fetch once', () async {
      final youtube = MockDeduplicatingYoutubeService();
      final completer = Completer<Uri>();
      youtube.pendingCompleter = completer;

      // Start 2 concurrent resolutions for the same video ID
      final f1 = youtube.resolveAudioUrl('video_concurrent');
      final f2 = youtube.resolveAudioUrl('video_concurrent');

      expect(youtube.internalCallCount, 1);

      final expectedUri = Uri.parse('https://example.com/audio.m4a?expire=1710000000&id=video_concurrent');
      completer.complete(expectedUri);

      final r1 = await f1;
      final r2 = await f2;

      expect(r1, expectedUri);
      expect(r2, expectedUri);
      expect(youtube.internalCallCount, 1);
      youtube.dispose();
    });

    test('preWarmTrack initiates resolution and populates cache in background', () async {
      final youtube = MockDeduplicatingYoutubeService();
      final player = FakeAudioPlayer();
      final controller = PlaybackController(
        youtubeService: youtube,
        player: player,
      );

      expect(youtube.hasCachedUrl('prewarm_target'), isFalse);

      controller.preWarmTrack('prewarm_target');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(youtube.hasCachedUrl('prewarm_target'), isTrue);
      expect(youtube.internalCallCount, 1);

      // Subsequent call hits cache and does not increment call count
      final cachedUri = await youtube.resolveAudioUrl('prewarm_target');
      expect(cachedUri.toString(), contains('prewarm_target'));
      expect(youtube.internalCallCount, 1);

      controller.dispose();
      youtube.dispose();
    });
  });
}
