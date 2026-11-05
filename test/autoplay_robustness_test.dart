import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shuno/models/youtube_search_item.dart';
import 'package:shuno/services/playback_controller.dart';
import 'package:shuno/services/storage_service.dart';
import 'package:shuno/services/youtube_service.dart';

import 'helpers/fake_audio_player.dart';

class MockAutoplayYoutubeService extends YoutubeService {
  final List<String> resolvedIds = [];
  final Set<String> failingIds = {};
  List<YoutubeSearchItem> relatedItemsToReturn = [];

  @override
  Future<Uri> resolveAudioUrl(String videoId, {bool highQuality = true}) async {
    resolvedIds.add(videoId);
    if (failingIds.contains(videoId)) {
      throw Exception('403 Forbidden: Video restricted');
    }
    return Uri.parse('https://example.com/$videoId.m4a');
  }

  @override
  Future<List<YoutubeSearchItem>> getRelatedVideos(
    YoutubeSearchItem currentItem,
  ) async {
    return relatedItemsToReturn;
  }
}

YoutubeSearchItem testTrack(String id, {String title = 'Test Track'}) {
  return YoutubeSearchItem(
    id: id,
    title: title,
    channelName: 'Channel',
    thumbnailUrl: 'https://example.com/$id.jpg',
    duration: const Duration(minutes: 5),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YoutubeService Series Heuristic', () {
    test('increments Part number preserving formatting', () {
      final next = YoutubeService.getNextSeriesQuery('The Hobbit Part 1', 'Tolkien');
      expect(next, 'The Hobbit Part 2 Tolkien');

      final nextPadded = YoutubeService.getNextSeriesQuery('Story Part 01', 'Author');
      expect(nextPadded, 'Story Part 02 Author');
    });

    test('increments Chapter and Episode notation', () {
      final nextCh = YoutubeService.getNextSeriesQuery('Atomic Habits Chapter 3', 'James');
      expect(nextCh, 'Atomic Habits Chapter 4 James');

      final nextEp = YoutubeService.getNextSeriesQuery('History Podcast Ep 09', 'Host');
      expect(nextEp, 'History Podcast Ep 10 Host');
    });

    test('increments fraction series like 1/6', () {
      final next = YoutubeService.getNextSeriesQuery('Byomkesh Bakshi 1/6', 'Ray');
      expect(next, 'Byomkesh Bakshi 2/6 Ray');

      final nextPadded = YoutubeService.getNextSeriesQuery('Audiobook 01/12', 'Studio');
      expect(nextPadded, 'Audiobook 02/12 Studio');
    });

    test('increments hash notation like #1', () {
      final next = YoutubeService.getNextSeriesQuery('Daily News #5', 'News');
      expect(next, 'Daily News #6 News');
    });

    test('returns null for non-series standalone titles', () {
      final next = YoutubeService.getNextSeriesQuery('Peaceful Piano Ambient Music', 'Artist');
      expect(next, isNull);
    });
  });

  group('Autoplay Proactive Queue Staging & Seamless Transition', () {
    late Directory tempDir;
    late StorageService storage;
    late MockAutoplayYoutubeService youtube;
    late FakeAudioPlayer player;
    late PlaybackController controller;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('autoplay_test_');
      storage = StorageService();
      await storage.init(overrideFile: File('${tempDir.path}/storage.json'));
      await storage.setAutoplay(true);

      youtube = MockAutoplayYoutubeService();
      player = FakeAudioPlayer();
      controller = PlaybackController(
        youtubeService: youtube,
        storageService: storage,
        player: player,
      );
    });

    tearDown(() async {
      controller.dispose();
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    test('proactively stages next track in queue and pre-warms audio URL while playing', () async {
      final track1 = testTrack('track_1', title: 'Part 1');
      final track2 = testTrack('track_2', title: 'Part 2');
      youtube.relatedItemsToReturn = [track2];

      await controller.playItem(track1);

      // Allow background staging future to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // The queue should now have 2 tracks (track1 playing, track2 staged)
      expect(controller.queue.length, 2);
      expect(controller.queue[0].id, 'track_1');
      expect(controller.queue[1].id, 'track_2');
      expect(controller.currentIndex, 0);

      // Pre-warming was triggered for track2
      expect(youtube.resolvedIds, contains('track_2'));

      // Up Next displays the staged track
      expect(controller.upNext.length, 1);
      expect(controller.upNext.first.id, 'track_2');
    });

    test('track completion seamlessly transitions to staged track without silence gap', () async {
      final track1 = testTrack('track_1');
      final track2 = testTrack('track_2');
      youtube.relatedItemsToReturn = [track2];

      await controller.playItem(track1);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.currentIndex, 0);
      expect(controller.selected?.id, 'track_1');

      // Simulate track completion
      player.emit(ProcessingState.completed);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // PlaybackController smoothly moved to track_2
      expect(controller.currentIndex, 1);
      expect(controller.selected?.id, 'track_2');
      expect(player.loadedUrls.last, 'https://example.com/track_2.m4a');
      expect(controller.isPlaying, isTrue);
    });

    test('candidate fallback: tries subsequent candidate if candidate 1 fails with 403', () async {
      final track1 = testTrack('track_1');
      final badCandidate = testTrack('bad_track');
      final goodCandidate = testTrack('good_track');

      // Both candidates in related items, badCandidate fails with 403
      youtube.relatedItemsToReturn = [badCandidate, goodCandidate];
      youtube.failingIds.add('bad_track');

      await controller.playItem(track1);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // When track 1 completes, skipToNext catches badCandidate failure and plays goodCandidate
      player.emit(ProcessingState.completed);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(controller.selected?.id, 'good_track');
      expect(controller.isPlaying, isTrue);
      expect(controller.error, isNull);
    });

    test('re-entrancy guard prevents duplicate skip execution from multiple completion events', () async {
      final track1 = testTrack('track_1');
      final track2 = testTrack('track_2');
      final track3 = testTrack('track_3');
      youtube.relatedItemsToReturn = [track2, track3];

      await controller.playItem(track1);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Rapidly fire completed events back to back
      player.emit(ProcessingState.completed);
      player.emit(ProcessingState.completed);
      player.emit(ProcessingState.completed);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      // Should be on track 2, not skipped ahead to track 3
      expect(controller.selected?.id, 'track_2');
    });

    test('does not stage autoplay tracks when autoplay is disabled in settings', () async {
      await storage.setAutoplay(false);
      final track1 = testTrack('track_1');
      final track2 = testTrack('track_2');
      youtube.relatedItemsToReturn = [track2];

      await controller.playItem(track1);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.queue.length, 1);
      expect(controller.upNext, isEmpty);
    });

    test('does not stage autoplay tracks when loop mode is active', () async {
      controller.setLoopMode(PlaybackLoopMode.all);
      final track1 = testTrack('track_1');
      final track2 = testTrack('track_2');
      youtube.relatedItemsToReturn = [track2];

      await controller.playItem(track1);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.queue.length, 1);
      expect(controller.upNext, isEmpty);
    });
  });
}

