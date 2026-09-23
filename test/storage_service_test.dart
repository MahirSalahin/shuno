import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shuno/models/download_item.dart';
import 'package:shuno/models/youtube_search_item.dart';
import 'package:shuno/services/storage_service.dart';

void main() {
  late Directory tempDir;
  late File testFile;
  late StorageService storage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('shuno_test_');
    testFile = File('${tempDir.path}/test_storage.json');
    storage = StorageService();
    await storage.init(overrideFile: testFile);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  final testItem = const YoutubeSearchItem(
    id: 'abc1234',
    title: 'Test Song',
    channelName: 'Test Channel',
    thumbnailUrl: 'https://example.com/thumb.jpg',
    duration: Duration(minutes: 3, seconds: 45),
  );

  test('toggle favorites adds and removes items', () async {
    expect(storage.isFavorite('abc1234'), isFalse);

    await storage.toggleFavorite(testItem);
    expect(storage.isFavorite('abc1234'), isTrue);
    expect(storage.favorites.length, 1);

    await storage.toggleFavorite(testItem);
    expect(storage.isFavorite('abc1234'), isFalse);
    expect(storage.favorites, isEmpty);
  });

  test('history manages recent items and preserves order', () async {
    final item2 = const YoutubeSearchItem(
      id: 'second_song',
      title: 'Second Song',
      channelName: 'Channel',
      thumbnailUrl: '',
    );

    await storage.addToHistory(testItem);
    await storage.addToHistory(item2);

    expect(storage.history.length, 2);
    expect(storage.history.first.id, 'second_song');

    await storage.clearHistory();
    expect(storage.history, isEmpty);
  });

  test('playlists can be created, updated, and deleted', () async {
    final playlist = await storage.createPlaylist('Chill Vibes');
    expect(storage.playlists.length, 1);
    expect(playlist.title, 'Chill Vibes');

    final added = await storage.addTrackToPlaylist(playlist.id, testItem);
    expect(added, isTrue);
    expect(storage.playlists.first.items.length, 1);

    await storage.renamePlaylist(playlist.id, 'Super Chill');
    expect(storage.playlists.first.title, 'Super Chill');

    await storage.removeTrackFromPlaylist(playlist.id, testItem.id);
    expect(storage.playlists.first.items, isEmpty);

    await storage.deletePlaylist(playlist.id);
    expect(storage.playlists, isEmpty);
  });

  test('playlists tracks can be reordered and persisted', () async {
    final playlist = await storage.createPlaylist('Reorder Test');
    const item2 = YoutubeSearchItem(
      id: 'song2',
      title: 'Song 2',
      channelName: 'Channel',
      thumbnailUrl: '',
    );
    const item3 = YoutubeSearchItem(
      id: 'song3',
      title: 'Song 3',
      channelName: 'Channel',
      thumbnailUrl: '',
    );

    await storage.addTracksToPlaylist(playlist.id, [testItem, item2, item3]);
    expect(storage.playlists.first.items.map((e) => e.id).toList(), [
      'abc1234',
      'song2',
      'song3',
    ]);

    // Move first item (index 0) to end (index 3 in Flutter reorder semantics)
    await storage.reorderPlaylistTracks(playlist.id, 0, 3);
    expect(storage.playlists.first.items.map((e) => e.id).toList(), [
      'song2',
      'song3',
      'abc1234',
    ]);

    // Move last item (index 2) to first (index 0)
    await storage.reorderPlaylistTracks(playlist.id, 2, 0);
    expect(storage.playlists.first.items.map((e) => e.id).toList(), [
      'abc1234',
      'song2',
      'song3',
    ]);
  });

  test('download metadata can be saved and retrieved', () async {
    final download = DownloadItem(
      item: testItem,
      localPath: '/local/path/song.m4a',
      fileSize: 1024 * 1024 * 5,
      downloadedAt: DateTime.now(),
    );

    await storage.saveDownload(download);
    expect(storage.isDownloaded(testItem.id), isTrue);
    expect(storage.getDownload(testItem.id)?.fileSize, download.fileSize);

    await storage.removeDownload(testItem.id);
    expect(storage.isDownloaded(testItem.id), isFalse);
  });

  test('persists state across reloads', () async {
    await storage.toggleFavorite(testItem);
    await storage.setAutoplay(false);
    await storage.setAudioQuality('saver');

    // Create a new instance pointing to same file
    final reloadedStorage = StorageService();
    await reloadedStorage.init(overrideFile: testFile);

    expect(reloadedStorage.isFavorite(testItem.id), isTrue);
    expect(reloadedStorage.autoplay, isFalse);
    expect(reloadedStorage.audioQuality, 'saver');
  });
}
