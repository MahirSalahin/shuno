import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuno/models/youtube_search_item.dart';
import 'package:shuno/screens/home_navigation_screen.dart';
import 'package:shuno/services/download_service.dart';
import 'package:shuno/services/playback_controller.dart';
import 'package:shuno/services/storage_service.dart';
import 'package:shuno/services/youtube_service.dart';
import 'package:shuno/widgets/track_tile.dart';

import 'helpers/fake_audio_player.dart';

class FakeService extends YoutubeService {}

void main() {
  testWidgets('HomeNavigationScreen switches tabs and shows destinations', (
    tester,
  ) async {
    final storage = StorageService();
    final youtube = FakeService();
    final playback = PlaybackController(
      youtubeService: youtube,
      player: FakeAudioPlayer(),
      storageService: storage,
    );
    final download = DownloadService(storageService: storage);

    addTearDown(playback.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeNavigationScreen(
          youtubeService: youtube,
          storageService: storage,
          playbackController: playback,
          downloadService: download,
        ),
      ),
    );

    expect(find.text('Search'), findsWidgets);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Queue'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);

    // Switch to Library
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(find.text('Playlists (0)'), findsOneWidget);
    expect(find.text('Favorites (0)'), findsOneWidget);

    // Switch to Queue
    await tester.tap(find.text('Queue'));
    await tester.pumpAndSettle();
    expect(find.text('Your queue is empty'), findsOneWidget);

    // Switch to Settings
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Autoplay'), findsOneWidget);
    expect(find.text('Audio Quality'), findsOneWidget);
  });

  testWidgets('TrackTile renders with 2-line title and ultra-compact actions', (
    tester,
  ) async {
    final storage = StorageService();
    final youtube = FakeService();
    final playback = PlaybackController(
      youtubeService: youtube,
      player: FakeAudioPlayer(),
      storageService: storage,
    );
    final download = DownloadService(storageService: storage);

    addTearDown(playback.dispose);

    const testItem = YoutubeSearchItem(
      id: 'test_vid',
      title: 'একটি নদীর নাম 1/2 | Humayun Ahmed | Golpokothon Special Edition',
      channelName: 'গল্পকথন by কল্লোল',
      thumbnailUrl: '',
      duration: Duration(minutes: 44, seconds: 6),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrackTile(
            item: testItem,
            playback: playback,
            storage: storage,
            downloadService: download,
          ),
        ),
      ),
    );

    // Verify title is rendered with maxLines == 2
    final titleWidget = tester.widget<Text>(find.text(testItem.title));
    expect(titleWidget.maxLines, 2);

    // Verify all 3 action icons are present
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);

    // Verify tapping favorite toggles favorite in storage
    await tester.tap(find.byIcon(Icons.favorite_border));
    expect(storage.isFavorite(testItem.id), isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TrackTile(
            item: testItem,
            playback: playback,
            storage: storage,
            downloadService: download,
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.favorite), findsOneWidget);

    // Verify popup menu can be opened and contains menu options
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Add to Queue'), findsOneWidget);
    expect(find.text('Download for Offline'), findsOneWidget);
    expect(find.text('Remove from favorites'), findsOneWidget);
  });
}
