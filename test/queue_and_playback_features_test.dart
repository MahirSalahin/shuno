import 'package:flutter_test/flutter_test.dart';
import 'package:shuno/models/youtube_search_item.dart';
import 'package:shuno/services/playback_controller.dart';
import 'package:shuno/services/youtube_service.dart';

import 'helpers/fake_audio_player.dart';

class TestYoutubeService extends YoutubeService {
  final loadedIds = <String>[];

  @override
  Future<Uri> resolveAudioUrl(String videoId, {bool highQuality = true}) async {
    loadedIds.add(videoId);
    return Uri.parse('https://example.com/$videoId.m4a');
  }

  @override
  Future<List<YoutubeSearchItem>> getRelatedVideos(
    YoutubeSearchItem currentItem,
  ) async {
    return [
      YoutubeSearchItem(
        id: 'related_to_${currentItem.id}',
        title: 'Related Song',
        channelName: 'Channel',
        thumbnailUrl: '',
      ),
    ];
  }
}

YoutubeSearchItem testItem(String id) => YoutubeSearchItem(
  id: id,
  title: 'Track $id',
  channelName: 'Artist',
  thumbnailUrl: '',
  duration: const Duration(minutes: 3),
);

void main() {
  late TestYoutubeService yt;
  late FakeAudioPlayer player;
  late PlaybackController controller;

  setUp(() {
    yt = TestYoutubeService();
    player = FakeAudioPlayer();
    controller = PlaybackController(youtubeService: yt, player: player);
  });

  tearDown(() => controller.dispose());

  test('playQueue loads initial index and sets queue', () async {
    final items = [testItem('1'), testItem('2'), testItem('3')];
    await controller.playQueue(items, initialIndex: 1);

    expect(controller.queue.length, 3);
    expect(controller.currentIndex, 1);
    expect(controller.selected?.id, '2');
    expect(yt.loadedIds.last, '2');
  });

  test('skipToNext advances index and plays next track', () async {
    final items = [testItem('1'), testItem('2'), testItem('3')];
    await controller.playQueue(items, initialIndex: 0);
    expect(controller.currentIndex, 0);

    await controller.skipToNext();
    expect(controller.currentIndex, 1);
    expect(controller.selected?.id, '2');
  });

  test('skipToPrevious returns to previous track', () async {
    final items = [testItem('1'), testItem('2')];
    await controller.playQueue(items, initialIndex: 1);

    await controller.skipToPrevious();
    expect(controller.currentIndex, 0);
    expect(controller.selected?.id, '1');
  });

  test('playNext inserts item immediately after current index', () async {
    final items = [testItem('1'), testItem('2')];
    await controller.playQueue(items, initialIndex: 0);

    controller.playNext(testItem('next'));
    expect(controller.queue[1].id, 'next');
    expect(controller.queue.length, 3);
  });

  test('removeAt removes item and updates index', () async {
    final items = [testItem('1'), testItem('2'), testItem('3')];
    await controller.playQueue(items, initialIndex: 1);

    controller.removeAt(2);
    expect(controller.queue.length, 2);
    expect(controller.currentIndex, 1);
  });

  test('loop mode all wraps to first track on next', () async {
    final items = [testItem('1'), testItem('2')];
    await controller.playQueue(items, initialIndex: 1);
    controller.setLoopMode(PlaybackLoopMode.all);

    await controller.skipToNext();
    expect(controller.currentIndex, 0);
    expect(controller.selected?.id, '1');
  });

  test('shuffle reorders queue and keeps selected at top', () async {
    final items = [testItem('1'), testItem('2'), testItem('3'), testItem('4')];
    await controller.playQueue(items, initialIndex: 0);

    controller.toggleShuffle();
    expect(controller.isShuffle, isTrue);
    expect(controller.selected?.id, '1');
    expect(controller.queue.first.id, '1');

    controller.toggleShuffle();
    expect(controller.isShuffle, isFalse);
    expect(controller.queue.map((e) => e.id).toList(), ['1', '2', '3', '4']);
  });
}
