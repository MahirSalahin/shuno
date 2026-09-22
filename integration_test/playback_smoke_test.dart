import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shuno/screens/search_screen.dart';
import 'package:shuno/services/playback_controller.dart';
import 'package:shuno/services/youtube_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Requires Android + internet. This is separate from deterministic unit tests.
  testWidgets(
    'real YouTube audio advances on Android and pauses',
    (tester) async {
      final youtube = YoutubeService();
      final player = AudioPlayer();
      final playback = PlaybackController(
        youtubeService: youtube,
        player: player,
      );
      addTearDown(playback.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SearchScreen(
            youtubeService: youtube,
            playbackController: playback,
          ),
        ),
      );

      await tester.runAsync(() async {
        final results = await youtube.search('jNQXAC9IVRw');
        final video = results.firstWhere((item) => item.id == 'jNQXAC9IVRw');
        await playback.playItem(video);
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (player.position < const Duration(seconds: 1) &&
            playback.error == null &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        expect(playback.error, isNull);
        expect(
          player.position,
          greaterThanOrEqualTo(const Duration(seconds: 1)),
        );
        expect(playback.isPlaying, isTrue);
      });
      await tester.pumpAndSettle();
      expect(find.text('Playing'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause'));
      await tester.pumpAndSettle();
      expect(player.playing, isFalse);
      expect(find.text('Paused'), findsOneWidget);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
