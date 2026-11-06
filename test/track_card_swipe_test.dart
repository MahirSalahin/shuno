import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuno/models/youtube_search_item.dart';
import 'package:shuno/services/playback_controller.dart';
import 'package:shuno/services/storage_service.dart';
import 'package:shuno/services/youtube_service.dart';
import 'package:shuno/widgets/full_player_sheet.dart';
import 'package:shuno/widgets/playback_bar.dart';

import 'helpers/fake_audio_player.dart';

class MockSwipeYoutubeService extends YoutubeService {
  @override
  Future<Uri> resolveAudioUrl(String videoId, {bool highQuality = true}) async {
    return Uri.parse('https://example.com/$videoId.m4a');
  }

  @override
  Future<List<YoutubeSearchItem>> getRelatedVideos(YoutubeSearchItem item) async {
    return [];
  }
}

YoutubeSearchItem sampleTrack(String id) {
  return YoutubeSearchItem(
    id: id,
    title: 'Audio Track $id',
    channelName: 'Channel $id',
    thumbnailUrl: '',
    duration: const Duration(minutes: 4),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Track Card & Mini-Player Swipe Navigation', () {
    late StorageService storage;
    late MockSwipeYoutubeService youtube;
    late FakeAudioPlayer player;
    late PlaybackController controller;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();
      await storage.init();
      youtube = MockSwipeYoutubeService();
      player = FakeAudioPlayer();
      controller = PlaybackController(
        youtubeService: youtube,
        player: player,
        storageService: storage,
      );
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets('FullPlayerSheet control buttons are rendered with refined compact dimensions', (tester) async {
      await controller.playQueue([sampleTrack('1'), sampleTrack('2')]);

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

      final prevFinder = find.widgetWithIcon(IconButton, Icons.skip_previous);
      expect(prevFinder, findsOneWidget);
      final prevBtn = tester.widget<IconButton>(prevFinder);
      expect(prevBtn.iconSize, 34);

      final nextFinder = find.widgetWithIcon(IconButton, Icons.skip_next);
      expect(nextFinder, findsOneWidget);
      final nextBtn = tester.widget<IconButton>(nextFinder);
      expect(nextBtn.iconSize, 34);

      // Hero Play/Pause button rendered with enlarged 38px icon
      final playFinder = find.widgetWithIcon(IconButton, Icons.pause);
      expect(playFinder, findsOneWidget);
      final playBtn = tester.widget<IconButton>(playFinder);
      expect(playBtn.iconSize, 38);

      // Icons distributed cleanly across layout tiers
      // Top bar: sleep timer & add to playlist
      expect(find.byIcon(Icons.bedtime_outlined), findsOneWidget);
      expect(find.byIcon(Icons.playlist_add), findsOneWidget);

      // Title row: download & favorite
      expect(find.byIcon(Icons.arrow_circle_down_outlined), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);

      // Bottom bar: speed badge (1x), book reader & queue (non-music, badge-free)
      expect(find.text('1x'), findsOneWidget);
      expect(find.byIcon(Icons.auto_stories_outlined), findsOneWidget);
      expect(find.byIcon(Icons.playlist_play), findsOneWidget);
      expect(find.byType(Badge), findsNothing);
    });

    testWidgets('Swiping left on track card in FullPlayerSheet skips to next track', (tester) async {
      await controller.playQueue([sampleTrack('1'), sampleTrack('2'), sampleTrack('3')], initialIndex: 0);

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
      expect(controller.currentIndex, 0);

      // Find the artwork track card by its key
      final cardFinder = find.byKey(const ValueKey('full_player_track_card'));
      expect(cardFinder, findsOneWidget);

      // Swipe Left (drag towards left with negative dx and velocity)
      await tester.drag(cardFinder, const Offset(-120, 0));
      await tester.pumpAndSettle();

      expect(controller.currentIndex, 1);
      expect(controller.selected?.id, '2');
    });

    testWidgets('Swiping right on track card in FullPlayerSheet skips to previous track', (tester) async {
      await controller.playQueue([sampleTrack('1'), sampleTrack('2'), sampleTrack('3')], initialIndex: 1);

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
      expect(controller.currentIndex, 1);

      final cardFinder = find.byKey(const ValueKey('full_player_track_card'));
      expect(cardFinder, findsOneWidget);

      // Swipe Right (drag towards right with positive dx and velocity)
      await tester.drag(cardFinder, const Offset(120, 0));
      await tester.pumpAndSettle();

      expect(controller.currentIndex, 0);
      expect(controller.selected?.id, '1');
    });

    testWidgets('Swiping left on PlaybackBar skips to next track', (tester) async {
      await controller.playQueue([sampleTrack('1'), sampleTrack('2')], initialIndex: 0);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: PlaybackBar(
              controller: controller,
              storageService: storage,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.currentIndex, 0);

      // Swipe left on PlaybackBar
      await tester.drag(find.byType(PlaybackBar), const Offset(-150, 0));
      await tester.pumpAndSettle();

      expect(controller.currentIndex, 1);
      expect(controller.selected?.id, '2');
    });

    testWidgets('Swiping right on PlaybackBar skips to previous track', (tester) async {
      await controller.playQueue([sampleTrack('1'), sampleTrack('2')], initialIndex: 1);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: PlaybackBar(
              controller: controller,
              storageService: storage,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.currentIndex, 1);

      // Swipe right on PlaybackBar
      await tester.drag(find.byType(PlaybackBar), const Offset(150, 0));
      await tester.pumpAndSettle();

      expect(controller.currentIndex, 0);
      expect(controller.selected?.id, '1');
    });
  });
}
