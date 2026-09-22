import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shuno/models/youtube_search_item.dart';
import 'package:shuno/services/playback_controller.dart';
import 'package:shuno/services/youtube_service.dart';

import 'helpers/fake_audio_player.dart';

class FakeYoutubeService extends YoutubeService {
  final requests = <String>[];
  Completer<Uri>? pending;
  Object? error;

  @override
  Future<Uri> resolveAudioUrl(String videoId, {bool highQuality = true}) async {
    requests.add(videoId);
    if (error != null) throw error!;
    return pending == null ? source(videoId) : pending!.future;
  }
}

Uri source(String id) => Uri.parse('https://example.com/$id.m4a');

YoutubeSearchItem item(String id) => YoutubeSearchItem(
  id: id,
  title: 'Song $id',
  channelName: 'Channel',
  thumbnailUrl: '',
);

void main() {
  late FakeYoutubeService youtube;
  late FakeAudioPlayer player;
  late PlaybackController controller;

  setUp(() {
    youtube = FakeYoutubeService();
    player = FakeAudioPlayer();
    controller = PlaybackController(
      youtubeService: youtube,
      player: player,
      pauseOnBackground: true,
    );
  });
  tearDown(() => controller.dispose());

  test('resolves one source, starts audio, pauses and resumes', () async {
    await controller.playItem(item('one'));
    expect(player.loadedUrls, ['https://example.com/one.m4a']);
    expect(controller.isPlaying, isTrue);
    expect(controller.isLoading, isFalse);
    await controller.togglePlayback();
    expect(controller.isPlaying, isFalse);
    await controller.togglePlayback();
    expect(controller.isPlaying, isTrue);
  });

  test('switching tracks stops the previous source', () async {
    await controller.playItem(item('one'));
    await controller.playItem(item('two'));
    expect(player.stopCount, 2);
    expect(controller.selected?.id, 'two');
    expect(player.loadedUrls.last, 'https://example.com/two.m4a');
  });

  test('ignores duplicate result taps during resolution', () async {
    youtube.pending = Completer();
    final loading = controller.playItem(item('one'));
    await Future<void>.delayed(Duration.zero);
    await controller.playItem(item('two'));
    expect(controller.isLoading, isTrue);
    expect(youtube.requests, ['one']);
    youtube.pending!.complete(source('one'));
    await loading;
    expect(controller.selected?.id, 'one');
  });

  test('a resolution failure can retry with a fresh URL', () async {
    youtube.error = StateError('unavailable');
    await controller.playItem(item('one'));
    expect(controller.error, contains('Could not play'));
    expect(controller.isLoading, isFalse);
    youtube.error = null;
    await controller.togglePlayback();
    expect(youtube.requests, ['one', 'one']);
    expect(controller.error, isNull);
    expect(controller.isPlaying, isTrue);
  });

  test('native load failure is recoverable', () async {
    player.loadError = PlayerException(403, 'Forbidden', 0);
    await controller.playItem(item('one'));
    expect(controller.error, isNotNull);
    expect(controller.isPlaying, isFalse);
    player.loadError = null;
    await controller.togglePlayback();
    expect(controller.error, isNull);
    expect(controller.isPlaying, isTrue);
  });

  test('runtime errors and buffering are reflected in state', () async {
    await controller.playItem(item('one'));
    player.emit(ProcessingState.buffering);
    expect(controller.isBuffering, isTrue);
    player.errors.add(PlayerException(1, 'Network failure', 0));
    expect(controller.error, contains('Playback failed'));
    expect(controller.isPlaying, isFalse);
  });

  test(
    'completion does not autoplay; replay seeks back to the beginning',
    () async {
      await controller.playItem(item('one'));
      player.emit(ProcessingState.completed);
      expect(controller.isPlaying, isFalse);
      expect(controller.isCompleted, isTrue);
      expect(youtube.requests, ['one']);
      await controller.togglePlayback();
      expect(player.seeks, [Duration.zero]);
      expect(controller.isPlaying, isTrue);
    },
  );

  test(
    'backgrounding pauses and returning does not automatically resume',
    () async {
      await controller.playItem(item('one'));
      await controller.setForeground(false);
      expect(controller.isPlaying, isFalse);
      await controller.setForeground(true);
      expect(controller.isPlaying, isFalse);
    },
  );

  test('resolving in the background never starts audio', () async {
    youtube.pending = Completer();
    final loading = controller.playItem(item('one'));
    await Future<void>.delayed(Duration.zero);
    await controller.setForeground(false);
    youtube.pending!.complete(source('one'));
    await loading;
    expect(controller.isPlaying, isFalse);
  });

  testWidgets('load timeout cancels the player and allows retry', (
    tester,
  ) async {
    player.pendingLoad = Completer();
    final loading = controller.playItem(item('one'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 21));
    await loading;
    expect(controller.error, contains('timed out'));
    expect(controller.isLoading, isFalse);
    expect(player.stopCount, 2);
    player.pendingLoad!.complete(null);
  });

  test('disposal during resolution prevents loading or playback', () async {
    final disposable = PlaybackController(
      youtubeService: youtube,
      player: player,
    );
    youtube.pending = Completer();
    final loading = disposable.playItem(item('one'));
    await Future<void>.delayed(Duration.zero);
    disposable.dispose();
    youtube.pending!.complete(source('one'));
    await loading;
    expect(player.loadedUrls, isEmpty);
    expect(player.disposed, isTrue);
  });
}
