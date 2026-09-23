import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuno/models/download_item.dart';
import 'package:shuno/models/youtube_search_item.dart';
import 'package:shuno/screens/playlist_detail_screen.dart';
import 'package:shuno/services/playback_controller.dart';
import 'package:shuno/services/storage_service.dart';
import 'package:shuno/services/youtube_service.dart';
import 'package:shuno/widgets/add_songs_to_playlist_sheet.dart';
import 'package:shuno/widgets/playback_bar.dart';

import 'helpers/fake_audio_player.dart';

class StubYoutubeService extends YoutubeService {
  @override
  Future<Uri> resolveAudioUrl(String videoId, {bool highQuality = true}) async {
    return Uri.parse('https://example.com/$videoId.m4a');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late FakeAudioPlayer player;
  late StubYoutubeService youtube;
  late PlaybackController controller;
  late Directory tempDir;

  final sampleItem = YoutubeSearchItem(
    id: 'test_vid_1',
    title: 'Test Song 1',
    channelName: 'Test Channel',
    thumbnailUrl: '',
    duration: const Duration(minutes: 4),
  );

  final sampleItem2 = YoutubeSearchItem(
    id: 'test_vid_2',
    title: 'Test Song 2',
    channelName: 'Test Channel 2',
    thumbnailUrl: '',
    duration: const Duration(minutes: 3),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.init();

    tempDir = await Directory.systemTemp.createTemp('shuno_test_');

    player = FakeAudioPlayer();
    youtube = StubYoutubeService();
    controller = PlaybackController(
      youtubeService: youtube,
      storageService: storage,
      player: player,
    );
  });

  tearDown(() async {
    controller.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Offline Playback Progress Tracking & Resume', () {
    test('DownloadItem progress getters work correctly', () {
      final downloaded = DownloadItem(
        item: sampleItem,
        localPath: '${tempDir.path}/test.m4a',
        fileSize: 1024 * 1024 * 5,
        downloadedAt: DateTime.now(),
        lastPositionMs: 60000, // 1 minute
      );

      expect(downloaded.lastPosition, const Duration(minutes: 1));
      expect(downloaded.playbackProgress, 0.25); // 1 min / 4 min
      expect(downloaded.hasPlaybackProgress, isTrue);
      expect(downloaded.formattedLastPosition, '1:00');

      // Less than 3s -> hasPlaybackProgress is false
      final early = downloaded.copyWith(lastPositionMs: 2000);
      expect(early.hasPlaybackProgress, isFalse);

      // Within last 5s of end -> hasPlaybackProgress is false
      final nearEnd = downloaded.copyWith(lastPositionMs: 238000); // 4m is 240s
      expect(nearEnd.hasPlaybackProgress, isFalse);
    });

    test('StorageService updates and clears playback position', () async {
      final testFile = File('${tempDir.path}/test1.m4a')..writeAsStringSync('dummy');
      await storage.saveDownload(
        DownloadItem(
          item: sampleItem,
          localPath: testFile.path,
          fileSize: 100,
          downloadedAt: DateTime.now(),
        ),
      );

      expect(storage.isDownloaded(sampleItem.id), isTrue);
      expect(storage.getDownload(sampleItem.id)?.lastPositionMs, 0);

      // Update position to 45 seconds
      await storage.updatePlaybackPosition(
        sampleItem.id,
        const Duration(seconds: 45),
      );

      var download = storage.getDownload(sampleItem.id);
      expect(download?.lastPositionMs, 45000);
      expect(download?.hasPlaybackProgress, isTrue);

      // Clear position
      await storage.clearPlaybackPosition(sampleItem.id);
      download = storage.getDownload(sampleItem.id);
      expect(download?.lastPositionMs, 0);
      expect(download?.hasPlaybackProgress, isFalse);
    });

    test('PlaybackController auto-resumes offline track from lastPosition', () async {
      final testFile = File('${tempDir.path}/test_offline.m4a')..writeAsStringSync('data');
      await storage.saveDownload(
        DownloadItem(
          item: sampleItem,
          localPath: testFile.path,
          fileSize: 100,
          downloadedAt: DateTime.now(),
          lastPositionMs: 50000, // 50 seconds
        ),
      );

      await controller.playItem(sampleItem);

      // FakeAudioPlayer should receive the initialPosition
      expect(player.lastInitialPosition, const Duration(milliseconds: 50000));
      expect(controller.position, const Duration(milliseconds: 50000));
    });

    test('PlaybackController can override resume with initialPosition: Duration.zero', () async {
      final testFile = File('${tempDir.path}/test_offline2.m4a')..writeAsStringSync('data');
      await storage.saveDownload(
        DownloadItem(
          item: sampleItem,
          localPath: testFile.path,
          fileSize: 100,
          downloadedAt: DateTime.now(),
          lastPositionMs: 80000,
        ),
      );

      await controller.playItem(sampleItem, initialPosition: Duration.zero);

      expect(player.lastInitialPosition, Duration.zero);
      expect(controller.position, Duration.zero);
    });
  });

  group('Sleep Timer Features', () {
    test('setting and cancelling sleep timer', () {
      expect(controller.hasSleepTimer, isFalse);
      expect(controller.sleepTimerRemaining, isNull);

      controller.setSleepTimer(const Duration(minutes: 15));
      expect(controller.hasSleepTimer, isTrue);
      expect(controller.isSleepAtEndOfTrack, isFalse);
      expect(controller.sleepTimerRemaining, isNotNull);

      controller.cancelSleepTimer();
      expect(controller.hasSleepTimer, isFalse);
      expect(controller.sleepTimerRemaining, isNull);
    });

    test('setting sleep at end of track', () {
      controller.setSleepTimer(null, endOfTrack: true);
      expect(controller.hasSleepTimer, isTrue);
      expect(controller.isSleepAtEndOfTrack, isTrue);
      expect(controller.sleepTimerRemainingFormatted, 'End of track');

      controller.cancelSleepTimer();
      expect(controller.hasSleepTimer, isFalse);
      expect(controller.isSleepAtEndOfTrack, isFalse);
    });
  });

  group('Recent Searches Persistence', () {
    test('adds, deduplicates, removes, and clears recent searches', () async {
      expect(storage.recentSearches, isEmpty);

      await storage.addRecentSearch('Taylor Swift');
      await storage.addRecentSearch('Coldplay');
      expect(storage.recentSearches, ['Coldplay', 'Taylor Swift']);

      // Adding duplicate brings it to the top
      await storage.addRecentSearch('Taylor Swift');
      expect(storage.recentSearches, ['Taylor Swift', 'Coldplay']);

      // Remove single search
      await storage.removeRecentSearch('Coldplay');
      expect(storage.recentSearches, ['Taylor Swift']);

      // Clear all
      await storage.clearRecentSearches();
      expect(storage.recentSearches, isEmpty);
    });
  });

  group('Playlist Enhancements & Running Playlists', () {
    test('batch addTracksToPlaylist adds multiple tracks and avoids duplicates', () async {
      final playlist = await storage.createPlaylist('Chill Vibes');
      expect(playlist.items, isEmpty);

      await storage.addTracksToPlaylist(playlist.id, [sampleItem, sampleItem2]);
      final updated = storage.playlists.firstWhere((p) => p.id == playlist.id);
      expect(updated.items.length, 2);

      // Re-adding same items should not create duplicates
      await storage.addTracksToPlaylist(playlist.id, [sampleItem]);
      final updated2 = storage.playlists.firstWhere((p) => p.id == playlist.id);
      expect(updated2.items.length, 2);
    });

    testWidgets('PlaylistDetailScreen shows PlaybackBar when music is playing', (tester) async {
      final playlist = await storage.createPlaylist('Favorites 2026');
      await storage.addTracksToPlaylist(playlist.id, [sampleItem]);

      await tester.pumpWidget(
        MaterialApp(
          home: PlaylistDetailScreen(
            playlist: playlist,
            playback: controller,
            storage: storage,
          ),
        ),
      );

      // Initially no song selected -> no PlaybackBar
      expect(find.byType(PlaybackBar), findsNothing);

      // Play the song
      await controller.playItem(sampleItem);
      await tester.pump();

      // PlaybackBar is now visible in PlaylistDetailScreen
      expect(find.byType(PlaybackBar), findsOneWidget);
      expect(find.text('Test Song 1'), findsWidgets);
    });

    testWidgets('AddSongsToPlaylistSheet displays downloaded tracks and allows adding', (tester) async {
      final testFile = File('${tempDir.path}/dl.m4a')..writeAsStringSync('audio');
      await storage.saveDownload(
        DownloadItem(
          item: sampleItem,
          localPath: testFile.path,
          fileSize: 1024,
          downloadedAt: DateTime.now(),
        ),
      );

      final playlist = await storage.createPlaylist('My Roadtrip');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddSongsToPlaylistSheet(
              playlist: playlist,
              storage: storage,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check that downloaded track appears
      expect(find.text('Test Song 1'), findsOneWidget);
      expect(find.text('0 selected'), findsOneWidget);

      // Tap checkbox list tile to select
      await tester.tap(find.text('Test Song 1'));
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('Add (1)'), findsOneWidget);

      // Tap Add button
      await tester.tap(find.text('Add (1)'));
      await tester.pumpAndSettle();

      // Playlist in storage now contains the song
      final updated = storage.playlists.firstWhere((p) => p.id == playlist.id);
      expect(updated.items.length, 1);
      expect(updated.items.first.id, sampleItem.id);
    });

    testWidgets('PlaylistDetailScreen shows drag handles and prompts before removing track', (tester) async {
      final playlist = await storage.createPlaylist('Favorites Reorder');
      await storage.addTracksToPlaylist(playlist.id, [sampleItem, sampleItem2]);

      await tester.pumpWidget(
        MaterialApp(
          home: PlaylistDetailScreen(
            playlist: playlist,
            playback: controller,
            storage: storage,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check ReorderableListView is used
      expect(find.byType(ReorderableListView), findsOneWidget);

      // Check drag indicator icons exist for tracks
      expect(find.byIcon(Icons.drag_indicator), findsNWidgets(2));

      // Tap remove track button
      final removeButtons = find.byTooltip('Remove from playlist');
      expect(removeButtons, findsNWidgets(2));
      await tester.tap(removeButtons.first);
      await tester.pumpAndSettle();

      // Verify confirmation dialog appeared
      expect(find.text('Remove Song?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);

      // Tap Cancel -> track remains
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(storage.playlists.first.items.length, 2);

      // Tap Remove button again and confirm
      await tester.tap(removeButtons.first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      // Track is now removed
      expect(storage.playlists.first.items.length, 1);
    });
  });
}
