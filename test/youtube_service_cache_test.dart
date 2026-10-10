import 'package:flutter_test/flutter_test.dart';
import 'package:shuno/models/youtube_search_item.dart';
import 'package:shuno/services/playback_controller.dart';
import 'package:shuno/services/youtube_service.dart';

import 'helpers/fake_audio_player.dart';

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
  });
}
