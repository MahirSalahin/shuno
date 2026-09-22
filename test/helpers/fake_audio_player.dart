import 'dart:async';

import 'package:just_audio/just_audio.dart';

class FakeAudioPlayer implements AudioPlayer {
  final states = StreamController<PlayerState>.broadcast(sync: true);
  final errors = StreamController<PlayerException>.broadcast(sync: true);
  final loadedUrls = <String>[];
  final seeks = <Duration?>[];
  bool disposed = false;
  Object? loadError;
  Completer<Duration?>? pendingLoad;
  int stopCount = 0;

  @override
  bool playing = false;

  @override
  ProcessingState processingState = ProcessingState.idle;

  @override
  Stream<PlayerState> get playerStateStream => states.stream;

  @override
  Stream<PlayerException> get errorStream => errors.stream;

  void emit(ProcessingState state, {bool? isPlaying}) {
    processingState = state;
    playing = isPlaying ?? playing;
    states.add(PlayerState(playing, processingState));
  }

  @override
  Future<Duration?> setUrl(
    String url, {
    Map<String, String>? headers,
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    loadedUrls.add(url);
    if (loadError != null) throw loadError!;
    if (pendingLoad != null) return pendingLoad!.future;
    emit(ProcessingState.ready);
    return const Duration(minutes: 3);
  }

  @override
  Future<void> play() async => emit(processingState, isPlaying: true);

  @override
  Future<void> pause() async => emit(processingState, isPlaying: false);

  @override
  Future<void> stop() async {
    stopCount++;
    emit(ProcessingState.idle, isPlaying: false);
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    seeks.add(position);
    emit(ProcessingState.ready);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await states.close();
    await errors.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
