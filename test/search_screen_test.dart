import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuno/main.dart';
import 'package:shuno/models/youtube_search_item.dart';
import 'package:shuno/services/playback_controller.dart';
import 'package:shuno/screens/search_screen.dart';
import 'package:shuno/services/youtube_service.dart';

import 'helpers/fake_audio_player.dart';

import 'package:shuno/models/youtube_channel_item.dart';
import 'package:shuno/screens/channel_detail_screen.dart';

import 'package:shuno/models/youtube_playlist_item.dart';
import 'package:shuno/screens/youtube_playlist_detail_screen.dart';
import 'package:shuno/widgets/track_tile.dart';

class FakeYoutubeService extends YoutubeService {
  final queries = <String>[];
  Completer<List<YoutubeSearchItem>> response = Completer();
  List<YoutubeChannelItem> channelsToReturn = [];
  List<YoutubeSearchItem> channelVideosToReturn = [];
  List<YoutubePlaylistItem> channelPlaylistsToReturn = [];
  List<YoutubeSearchItem> playlistTracksToReturn = [];
  List<YoutubeSearchItem> inChannelSearchToReturn = [];
  bool hasMoreUploads = false;

  @override
  Future<Uri> resolveAudioUrl(String videoId, {bool highQuality = true}) async =>
      Uri.parse('https://example.com/audio.m4a');

  @override
  Future<List<YoutubeSearchItem>> search(String query) {
    queries.add(query);
    return response.future;
  }

  @override
  Future<List<YoutubeChannelItem>> searchChannels(String query) async =>
      channelsToReturn;

  @override
  Future<List<YoutubeSearchItem>> getChannelVideos(
    String channelId, {
    String? channelName,
    int limit = 30,
  }) async => channelVideosToReturn;

  @override
  Future<ChannelUploadsPage> getChannelUploadsPage(
    String channelId, {
    String? channelName,
    dynamic continuation,
  }) async =>
      ChannelUploadsPage(
        items: channelVideosToReturn,
        hasMore: hasMoreUploads,
        continuation: hasMoreUploads ? 'next' : null,
      );

  @override
  Future<List<YoutubePlaylistItem>> getChannelPlaylists(
    String channelName, {
    String? channelId,
  }) async =>
      channelPlaylistsToReturn;

  @override
  Future<List<YoutubeSearchItem>> getPlaylistTracks(
    String playlistId, {
    int limit = 50,
  }) async =>
      playlistTracksToReturn;

  @override
  Future<List<YoutubeSearchItem>> searchChannelTracks(
    String channelId,
    String query, {
    String? channelName,
  }) async =>
      inChannelSearchToReturn;
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

  testWidgets('only has one search bar on search screen', (tester) async {
    final service = FakeYoutubeService();
    await openSearch(tester, service);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('shows Tracks and Channels filter chips and switches between them', (
    tester,
  ) async {
    final service = FakeYoutubeService();
    service.channelsToReturn = [
      const YoutubeChannelItem(
        id: 'c-1',
        title: 'Coldplay Official',
        thumbnailUrl: 'https://example.com/coldplay.jpg',
        subscriberCount: 25000000,
        videoCount: 120,
      ),
    ];
    await openSearch(tester, service);
    await submit(tester, 'coldplay');
    service.response.complete([sample]);
    await tester.pumpAndSettle();

    // Verify filter chips are present
    expect(find.widgetWithText(ChoiceChip, 'Tracks'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Channels'), findsOneWidget);

    // Initial tab is Tracks: sample track is visible
    expect(find.text('Example song'), findsOneWidget);
    expect(find.text('Coldplay Official'), findsNothing);

    // Switch to Channels tab
    await tester.tap(find.widgetWithText(ChoiceChip, 'Channels'));
    await tester.pumpAndSettle();

    // Now channel is visible, track is not
    expect(find.text('Coldplay Official'), findsOneWidget);
    expect(find.text('Example song'), findsNothing);
  });

  testWidgets('tapping channel navigates to ChannelDetailScreen and loads tracks', (
    tester,
  ) async {
    final service = FakeYoutubeService();
    service.channelsToReturn = [
      const YoutubeChannelItem(
        id: 'c-1',
        title: 'Coldplay Official',
        thumbnailUrl: 'https://example.com/coldplay.jpg',
        subscriberCount: 25000000,
        videoCount: 120,
      ),
    ];
    service.channelVideosToReturn = [
      const YoutubeSearchItem(
        id: 'track-c1',
        title: 'Yellow',
        channelName: 'Coldplay Official',
        thumbnailUrl: 'https://example.com/yellow.jpg',
        duration: Duration(minutes: 4, seconds: 29),
      ),
    ];

    await openSearch(tester, service);
    await submit(tester, 'coldplay');
    service.response.complete([sample]);
    await tester.pumpAndSettle();

    // Switch to Channels
    await tester.tap(find.widgetWithText(ChoiceChip, 'Channels'));
    await tester.pumpAndSettle();

    // Tap on channel tile
    await tester.tap(find.text('Coldplay Official'));
    await tester.pumpAndSettle();

    // ChannelDetailScreen is now pushed
    expect(find.byType(ChannelDetailScreen), findsOneWidget);
    expect(find.text('Coldplay Official'), findsWidgets);
    expect(find.text('Yellow'), findsOneWidget);
    expect(find.text('Play All'), findsOneWidget);
  });

  testWidgets('filter chips do not overflow on narrow screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = FakeYoutubeService();
    service.channelsToReturn = [
      const YoutubeChannelItem(
        id: 'c-1',
        title: 'Channel',
        thumbnailUrl: '',
      ),
    ];
    await openSearch(tester, service);
    await submit(tester, 'query');
    service.response.complete([sample]);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'Tracks'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Channels'), findsOneWidget);
    expect(find.text('Play All'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('channel exploration allows searching tracks within a channel', (
    tester,
  ) async {
    final service = FakeYoutubeService();
    service.channelsToReturn = [
      const YoutubeChannelItem(
        id: 'c-1',
        title: 'Coldplay',
        thumbnailUrl: '',
      ),
    ];
    service.channelVideosToReturn = [
      const YoutubeSearchItem(
        id: 't-1',
        title: 'Yellow',
        channelName: 'Coldplay',
        thumbnailUrl: '',
      ),
      const YoutubeSearchItem(
        id: 't-2',
        title: 'Fix You',
        channelName: 'Coldplay',
        thumbnailUrl: '',
      ),
    ];
    service.inChannelSearchToReturn = [
      const YoutubeSearchItem(
        id: 't-3',
        title: 'Yellow (Live)',
        channelName: 'Coldplay',
        thumbnailUrl: '',
      ),
    ];

    await openSearch(tester, service);
    await submit(tester, 'coldplay');
    service.response.complete([sample]);
    await tester.pumpAndSettle();

    // Switch to Channels
    await tester.tap(find.widgetWithText(ChoiceChip, 'Channels'));
    await tester.pumpAndSettle();

    // Tap on Coldplay channel
    await tester.tap(find.text('Coldplay'));
    await tester.pumpAndSettle();

    // Both tracks initially visible
    expect(find.text('Yellow'), findsOneWidget);
    expect(find.text('Fix You'), findsOneWidget);

    // Search in channel
    final inChannelInput = find.widgetWithText(TextField, 'Search in Coldplay…');
    expect(inChannelInput, findsOneWidget);

    await tester.enterText(inChannelInput, 'Yellow');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    // Yellow is visible, Fix You is not
    expect(find.widgetWithText(TrackTile, 'Yellow'), findsOneWidget);
    expect(find.widgetWithText(TrackTile, 'Fix You'), findsNothing);
    expect(find.widgetWithText(TrackTile, 'Yellow (Live)'), findsOneWidget);

    // Tap Show All to clear search
    await tester.tap(find.text('Show All'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TrackTile, 'Yellow'), findsOneWidget);
    expect(find.widgetWithText(TrackTile, 'Fix You'), findsOneWidget);
  });

  testWidgets('channel exploration explores channel playlists and views playlist tracks', (
    tester,
  ) async {
    final service = FakeYoutubeService();
    service.channelsToReturn = [
      const YoutubeChannelItem(
        id: 'c-1',
        title: 'Coldplay',
        thumbnailUrl: '',
      ),
    ];
    service.channelVideosToReturn = [
      const YoutubeSearchItem(
        id: 't-1',
        title: 'Yellow',
        channelName: 'Coldplay',
        thumbnailUrl: '',
      ),
    ];
    service.channelPlaylistsToReturn = [
      const YoutubePlaylistItem(
        id: 'pl-1',
        title: 'Parachutes Album',
        thumbnailUrl: '',
        videoCount: 10,
        author: 'Coldplay',
      ),
    ];
    service.playlistTracksToReturn = [
      const YoutubeSearchItem(
        id: 'pl-t1',
        title: 'Don\'t Panic',
        channelName: 'Coldplay',
        thumbnailUrl: '',
      ),
      const YoutubeSearchItem(
        id: 'pl-t2',
        title: 'Shiver',
        channelName: 'Coldplay',
        thumbnailUrl: '',
      ),
    ];

    await openSearch(tester, service);
    await submit(tester, 'coldplay');
    service.response.complete([sample]);
    await tester.pumpAndSettle();

    // Switch to Channels
    await tester.tap(find.widgetWithText(ChoiceChip, 'Channels'));
    await tester.pumpAndSettle();

    // Tap on Coldplay channel
    await tester.tap(find.text('Coldplay'));
    await tester.pumpAndSettle();

    // Check Playlists tab chip is visible
    expect(find.text('Playlists (1)'), findsOneWidget);

    // Switch to Playlists tab
    await tester.tap(find.text('Playlists (1)'));
    await tester.pumpAndSettle();

    // Verify playlist card
    expect(find.text('Parachutes Album'), findsOneWidget);
    expect(find.text('10 tracks'), findsOneWidget);

    // Tap on playlist card to open YoutubePlaylistDetailScreen
    await tester.tap(find.text('Parachutes Album'));
    await tester.pumpAndSettle();

    // Verify playlist detail screen is opened
    expect(find.byType(YoutubePlaylistDetailScreen), findsOneWidget);
    expect(find.text('Don\'t Panic'), findsOneWidget);
    expect(find.text('Shiver'), findsOneWidget);
  });

  testWidgets('channel exploration shows load more tracks button when hasMoreUploads is true', (
    tester,
  ) async {
    final service = FakeYoutubeService();
    service.channelsToReturn = [
      const YoutubeChannelItem(
        id: 'c-1',
        title: 'Coldplay',
        thumbnailUrl: '',
      ),
    ];
    service.hasMoreUploads = true;
    service.channelVideosToReturn = [
      const YoutubeSearchItem(
        id: 't-1',
        title: 'Yellow',
        channelName: 'Coldplay',
        thumbnailUrl: '',
      ),
    ];

    await openSearch(tester, service);
    await submit(tester, 'coldplay');
    service.response.complete([sample]);
    await tester.pumpAndSettle();

    // Switch to Channels
    await tester.tap(find.widgetWithText(ChoiceChip, 'Channels'));
    await tester.pumpAndSettle();

    // Tap on Coldplay channel
    await tester.tap(find.text('Coldplay'));
    await tester.pumpAndSettle();

    // Verify Load More Tracks button is visible
    expect(find.text('Load More Tracks'), findsOneWidget);
  });

  testWidgets('channel exploration strictly passes channel id to scoped services', (
    tester,
  ) async {
    final service = FakeYoutubeService();
    service.channelsToReturn = [
      const YoutubeChannelItem(
        id: 'UC-ANAS-12345',
        title: 'Anas Lahebouk',
        thumbnailUrl: '',
      ),
    ];
    service.channelVideosToReturn = [
      const YoutubeSearchItem(
        id: 'anas-t1',
        title: 'Surah Al-Mulk',
        channelName: 'Anas Lahebouk',
        thumbnailUrl: '',
      ),
    ];
    service.channelPlaylistsToReturn = [
      const YoutubePlaylistItem(
        id: 'PL-ANAS-PL1',
        title: 'Official Full Quran',
        thumbnailUrl: '',
        videoCount: 114,
        author: 'Anas Lahebouk',
      ),
    ];
    service.inChannelSearchToReturn = [
      const YoutubeSearchItem(
        id: 'anas-t2',
        title: 'Surah Rahman',
        channelName: 'Anas Lahebouk',
        thumbnailUrl: '',
      ),
    ];

    await openSearch(tester, service);
    await submit(tester, 'anas');
    service.response.complete([sample]);
    await tester.pumpAndSettle();

    // Switch to Channels
    await tester.tap(find.widgetWithText(ChoiceChip, 'Channels'));
    await tester.pumpAndSettle();

    // Tap on Anas Lahebouk channel
    await tester.tap(find.text('Anas Lahebouk'));
    await tester.pumpAndSettle();

    // Verify channel tracks display only Anas Lahebouk's track
    expect(find.text('Surah Al-Mulk'), findsOneWidget);

    // Switch to Playlists tab
    await tester.tap(find.text('Playlists (1)'));
    await tester.pumpAndSettle();

    // Verify official playlist
    expect(find.text('Official Full Quran'), findsOneWidget);

    // Switch back to Tracks and search
    await tester.tap(find.text('Tracks (1)'));
    await tester.pumpAndSettle();

    final searchField = find.widgetWithText(TextField, 'Search in Anas Lahebouk…');
    await tester.enterText(searchField, 'Rahman');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Surah Rahman'), findsOneWidget);
  });
}

