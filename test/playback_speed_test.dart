import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuno/models/youtube_search_item.dart';
import 'package:shuno/screens/queue_screen.dart';
import 'package:shuno/screens/settings_screen.dart';
import 'package:shuno/services/playback_controller.dart';
import 'package:shuno/services/storage_service.dart';
import 'package:shuno/services/youtube_service.dart';
import 'package:shuno/widgets/full_player_sheet.dart';

import 'helpers/fake_audio_player.dart';

class MockYoutubeService extends Fake implements YoutubeService {
  @override
  Future<Uri> resolveAudioUrl(String videoId, {bool highQuality = true}) async {
    return Uri.parse('https://example.com/audio/$videoId.mp4');
  }

  @override
  void clearCachedUrl(String videoId) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late PlaybackController controller;
  late FakeAudioPlayer player;
  late MockYoutubeService youtubeService;
  late Directory tempDir;

  const testTrack = YoutubeSearchItem(
    id: 'test_track_1',
    title: 'Podcast Episode 1',
    channelName: 'Audiobook Channel',
    thumbnailUrl: 'https://example.com/thumb.jpg',
    duration: Duration(minutes: 45),
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('speed_test_');
    final file = File('${tempDir.path}/storage.json');
    storage = StorageService();
    await storage.init(overrideFile: file);

    player = FakeAudioPlayer();
    youtubeService = MockYoutubeService();
    controller = PlaybackController(
      youtubeService: youtubeService,
      storageService: storage,
      player: player,
    );
  });

  tearDown(() async {
    controller.dispose();
    await player.dispose();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Playback Speed Feature', () {
    test('StorageService persists and loads playback speed', () async {
      expect(storage.playbackSpeed, 1.0);
      await storage.setPlaybackSpeed(1.5);
      expect(storage.playbackSpeed, 1.5);

      // Create new storage instance pointing to same file
      final storage2 = StorageService();
      await storage2.init(overrideFile: File('${tempDir.path}/storage.json'));
      expect(storage2.playbackSpeed, 1.5);
    });

    test('PlaybackController updates speed on player and storage', () async {
      expect(controller.playbackSpeed, 1.0);
      expect(player.speed, 1.0);

      var notified = false;
      controller.addListener(() => notified = true);

      await controller.setPlaybackSpeed(1.75);

      expect(controller.playbackSpeed, 1.75);
      expect(player.speed, 1.75);
      expect(storage.playbackSpeed, 1.75);
      expect(notified, isTrue);
    });

    test('PlaybackController applies speed when a new song starts playing', () async {
      await controller.setPlaybackSpeed(1.5);
      expect(player.speed, 1.5);

      await controller.playItem(testTrack);

      expect(controller.selected?.id, testTrack.id);
      expect(player.speed, 1.5);
    });

    testWidgets('FullPlayerSheet shows speed badge and opens speed picker', (tester) async {
      await controller.playItem(testTrack);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FullPlayerSheet(
              playback: controller,
              storage: storage,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the speed button badge in header
      expect(find.text('1x'), findsOneWidget);

      // Tap speed button to open speed picker modal
      await tester.tap(find.text('1x'));
      await tester.pumpAndSettle();

      expect(find.text('PLAYBACK SPEED'), findsOneWidget);
      expect(find.text('1.5x'), findsOneWidget);

      // Select 1.5x
      await tester.tap(find.text('1.5x'));
      await tester.pumpAndSettle();

      expect(controller.playbackSpeed, 1.5);
      expect(player.speed, 1.5);
    });

    testWidgets('QueueScreen shows speed chip and allows changing speed', (tester) async {
      await controller.playItem(testTrack);

      await tester.pumpWidget(
        MaterialApp(
          home: QueueScreen(
            playback: controller,
            storage: storage,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Speed chip in NOW PLAYING section
      expect(find.text('1x'), findsOneWidget);

      await tester.tap(find.text('1x'));
      await tester.pumpAndSettle();

      expect(find.text('PLAYBACK SPEED'), findsOneWidget);
      await tester.tap(find.text('2.0x'));
      await tester.pumpAndSettle();

      expect(controller.playbackSpeed, 2.0);
      expect(player.speed, 2.0);
    });

    testWidgets('SettingsScreen displays Playback Speed tile with refined typography', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            storage: storage,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Playback Speed'), findsOneWidget);
      expect(find.text('1.0x (Normal)'), findsOneWidget);

      // Change speed from dropdown
      await tester.tap(find.byType(DropdownButton<double>));
      await tester.pumpAndSettle();

      expect(find.text('1.25x').last, findsOneWidget);
      await tester.tap(find.text('1.25x').last);
      await tester.pumpAndSettle();

      expect(storage.playbackSpeed, 1.25);
    });
  });
}
