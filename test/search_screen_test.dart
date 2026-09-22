import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuno/main.dart';
import 'package:shuno/models/youtube_search_item.dart';
import 'package:shuno/services/playback_controller.dart';
import 'package:shuno/screens/search_screen.dart';
import 'package:shuno/services/youtube_service.dart';

import 'helpers/fake_audio_player.dart';

class FakeYoutubeService extends YoutubeService {
  final queries = <String>[];
  Completer<List<YoutubeSearchItem>> response = Completer();

  @override
  Future<Uri> resolveAudioUrl(String videoId, {bool highQuality = true}) async =>
      Uri.parse('https://example.com/audio.m4a');

  @override
  Future<List<YoutubeSearchItem>> search(String query) {
    queries.add(query);
    return response.future;
  }
}

const sample = YoutubeSearchItem(
  id: 'example-id',
  title: 'Example song',
  channelName: 'Example channel',
  thumbnailUrl: 'https://example.com/thumbnail.jpg',
  duration: Duration(minutes: 3, seconds: 5),
);

Future<void> openSearch(WidgetTester tester, FakeYoutubeService service) async {
  final playback = PlaybackController(
    youtubeService: service,
    player: FakeAudioPlayer(),
  );
  addTearDown(playback.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: SearchScreen(youtubeService: service, playbackController: playback),
    ),
  );
}

Future<void> submit(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.tap(find.widgetWithText(FilledButton, 'Search'));
  await tester.pump();
}

void main() {
  testWidgets('starts in dark mode with a search hint', (tester) async {
    await tester.pumpWidget(const ShunoApp());
    expect(find.text('Shuno'), findsOneWidget);
    expect(find.text('Search YouTube to get started.'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(SearchScreen))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('blank input is rejected without making a request', (
    tester,
  ) async {
    final service = FakeYoutubeService();
    await openSearch(tester, service);
    await submit(tester, '   ');
    expect(find.text('Enter something to search for.'), findsOneWidget);
    expect(service.queries, isEmpty);
  });

  testWidgets('shows loading, results, thumbnail fallback and selection', (
    tester,
  ) async {
    final service = FakeYoutubeService();
    await openSearch(tester, service);
    await submit(tester, '  example  ');
    expect(service.queries, ['example']);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    service.response.complete([sample]);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Example song'), findsOneWidget);
    expect(find.text('Example channel'), findsOneWidget);
    expect(find.text('3:05'), findsOneWidget);
    // Flutter widget tests reject network images, exercising the fallback.
    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    await tester.tap(find.text('Example song'));
    await tester.pumpAndSettle();
    expect(find.text('Playing'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    expect(find.text('Paused'), findsOneWidget);
    expect(find.byTooltip('Play'), findsOneWidget);
  });

  testWidgets('empty response shows no-results message', (tester) async {
    final service = FakeYoutubeService();
    await openSearch(tester, service);
    await submit(tester, 'no match');
    service.response.complete([]);
    await tester.pumpAndSettle();
    expect(
      find.text('No videos found. Try a different search.'),
      findsOneWidget,
    );
  });

  testWidgets('failure allows a new search using the keyboard', (tester) async {
    final service = FakeYoutubeService();
    await openSearch(tester, service);
    await submit(tester, 'first');
    service.response.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not search YouTube.'), findsOneWidget);
    service.response = Completer();
    await tester.enterText(find.byType(TextField), 'second');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.textContaining('Could not search YouTube.'), findsNothing);
    service.response.complete([sample]);
    await tester.pumpAndSettle();
    expect(service.queries, ['first', 'second']);
    expect(find.text('Example song'), findsOneWidget);
  });

  testWidgets('timeout shows a recoverable error', (tester) async {
    final service = FakeYoutubeService();
    await openSearch(tester, service);
    await submit(tester, 'example');
    service.response.completeError(TimeoutException('timeout'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Search timed out.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('finishing a search after disposal does not update the screen', (
    tester,
  ) async {
    final service = FakeYoutubeService();
    await openSearch(tester, service);
    await submit(tester, 'example');
    await tester.pumpWidget(const SizedBox());
    service.response.complete([sample]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('duration supports hours and missing metadata', () {
    expect(sample.durationLabel, '3:05');
    expect(
      const YoutubeSearchItem(
        id: 'long',
        title: 'Long',
        channelName: 'Channel',
        thumbnailUrl: '',
        duration: Duration(hours: 2, minutes: 4, seconds: 9),
      ).durationLabel,
      '2:04:09',
    );
    expect(
      const YoutubeSearchItem(
        id: 'live',
        title: 'Live',
        channelName: 'Channel',
        thumbnailUrl: '',
      ).durationLabel,
      isNull,
    );
  });
}
