import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuno/screens/home_navigation_screen.dart';
import 'package:shuno/services/download_service.dart';
import 'package:shuno/services/playback_controller.dart';
import 'package:shuno/services/storage_service.dart';
import 'package:shuno/services/youtube_service.dart';

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
}
