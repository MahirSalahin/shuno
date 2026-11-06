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

  test('upNext excludes current track and previous tracks', () async {
    final items = [testItem('1'), testItem('2'), testItem('3')];
    await controller.playQueue(items, initialIndex: 1);

    // Current is '2'
    expect(controller.selected?.id, '2');
    // upNext must ONLY contain '3', never '2' or '1'
    expect(controller.upNext.length, 1);
    expect(controller.upNext.first.id, '3');
    // previousTracks must ONLY contain '1'
    expect(controller.previousTracks.length, 1);
    expect(controller.previousTracks.first.id, '1');
  });

  test('clearUpNext clears upcoming tracks without altering current or previous tracks', () async {
    final items = [testItem('1'), testItem('2'), testItem('3'), testItem('4')];
    await controller.playQueue(items, initialIndex: 1);

    expect(controller.upNext.length, 2);
    controller.clearUpNext();
    expect(controller.upNext, isEmpty);
    expect(controller.selected?.id, '2');
    expect(controller.previousTracks.length, 1);
    expect(controller.previousTracks.first.id, '1');
  });

  test('playItem inserts after current track and maintains upcoming queue order', () async {
    final items = [testItem('1'), testItem('2')];
    await controller.playQueue(items, initialIndex: 0);

    // Currently playing '1', upNext has '2'
    expect(controller.selected?.id, '1');
    expect(controller.upNext.map((e) => e.id).toList(), ['2']);

    // Play a new track 'new'
    await controller.playItem(testItem('new'));

    // 'new' is now playing
    expect(controller.selected?.id, 'new');
    // '1' is in previousTracks
    expect(controller.previousTracks.map((e) => e.id).toList(), ['1']);
    // '2' remains in upNext
    expect(controller.upNext.map((e) => e.id).toList(), ['2']);
    // Total queue order: ['1', 'new', '2']
    expect(controller.queue.map((e) => e.id).toList(), ['1', 'new', '2']);
  });

  test('Spotify queue model: user queue has top priority and survives playing a new track from search', () async {
    // 1. Play an initial track
    await controller.playItem(testItem('song_a'));
    expect(controller.selected?.id, 'song_a');

    // 2. User explicitly adds a song to queue
    controller.addToQueue(testItem('user_queued_1'));
    expect(controller.isUserQueued('user_queued_1'), isTrue);
    expect(controller.userQueue.length, 1);
    expect(controller.upNext.first.id, 'user_queued_1');

    // 3. User searches and plays a new track directly
    await controller.playItem(testItem('song_b'));
    expect(controller.selected?.id, 'song_b');
    expect(controller.previousTracks.map((e) => e.id).toList(), ['song_a']);

    // 4. User-queued track is preserved and plays next
    expect(controller.isUserQueued('user_queued_1'), isTrue);
    expect(controller.upNext.first.id, 'user_queued_1');

    // 5. Playing next track naturally advances to the user-queued track
    await controller.skipToNext();
    expect(controller.selected?.id, 'user_queued_1');
    expect(controller.previousTracks.map((e) => e.id).toList(), ['song_a', 'song_b']);
  });

  test('Spotify queue model: clearUserQueue clears only user queue', () async {
    await controller.playQueue([testItem('c1'), testItem('c2')], initialIndex: 0);
    controller.addToQueue(testItem('u1'));

    expect(controller.userQueue.length, 1);
    expect(controller.upNext.length, 2);
    expect(controller.upNext[0].id, 'u1');
    expect(controller.upNext[1].id, 'c2');

    controller.clearUserQueue();
    expect(controller.userQueue, isEmpty);
    expect(controller.upNext.length, 1);
    expect(controller.upNext.first.id, 'c2');
  });
}
