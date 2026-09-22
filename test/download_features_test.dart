import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuno/models/youtube_search_item.dart';
import 'package:shuno/screens/library_screen.dart';
import 'package:shuno/services/download_service.dart';
import 'package:shuno/services/playback_controller.dart';
import 'package:shuno/services/storage_service.dart';
import 'package:shuno/services/youtube_service.dart';

import 'helpers/fake_audio_player.dart';

class FakeService extends YoutubeService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StorageService storage;
  late DownloadService downloadService;
  late PlaybackController playback;

  const testItem = YoutubeSearchItem(
    id: 'dQw4w9WgXcQ',
    title: 'Never Gonna Give You Up',
    channelName: 'Rick Astley',
    thumbnailUrl: '',
    duration: Duration(minutes: 3, seconds: 32),
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dl_test_');
    storage = StorageService();
    await storage.init(overrideFile: File('${tempDir.path}/storage.json'));
    downloadService = DownloadService(
      storageService: storage,
      downloadDir: Directory('${tempDir.path}/downloads'),
    );
    playback = PlaybackController(
      youtubeService: FakeService(),
      player: FakeAudioPlayer(),
      storageService: storage,
    );
  });

  tearDown(() async {
    playback.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('ActiveDownloadTask formats status text and progress correctly', () {
    final task = ActiveDownloadTask(
      item: testItem,
      status: DownloadStatus.connecting,
    );
    expect(task.isRunning, isTrue);
    expect(task.statusText, contains('Connecting'));

    task.status = DownloadStatus.downloading;
    task.receivedBytes = 1024 * 1024;
    task.totalBytes = 2 * 1024 * 1024;
    task.progress = 0.5;
    expect(task.isRunning, isTrue);
    expect(task.statusText, contains('50%'));
    expect(task.statusText, contains('1.0 / 2.0 MB'));

    task.status = DownloadStatus.failed;
    task.errorMessage = 'Network error';
    expect(task.isRunning, isFalse);
    expect(task.statusText, contains('Failed: Network error'));
  });

  test('DownloadService tracks active task, cancels, and dismisses failed task', () {
    expect(downloadService.activeTasks, isEmpty);
    expect(downloadService.isDownloading(testItem.id), isFalse);

    final task = ActiveDownloadTask(
      item: testItem,
      status: DownloadStatus.connecting,
    );
    downloadService.addTaskForTesting(task);
    expect(downloadService.isDownloading(testItem.id), isTrue);
    expect(downloadService.activeTasks.length, 1);

    // Cancel while connecting
    downloadService.cancelDownload(testItem.id);
    expect(downloadService.activeTasks, isEmpty);

    // Add failed task
    final failedTask = ActiveDownloadTask(
      item: testItem,
      status: DownloadStatus.failed,
      errorMessage: 'Test error',
    );
    downloadService.addTaskForTesting(failedTask);
    expect(downloadService.failedTasks.length, 1);

    // Dismiss failed task
    downloadService.dismissFailedTask(testItem.id);
    expect(downloadService.failedTasks, isEmpty);
  });

  testWidgets('LibraryScreen shows active download progress bar and cancel button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          playback: playback,
          storage: storage,
          downloadService: downloadService,
        ),
      ),
    );

    // Tap Downloads tab
    await tester.tap(find.text('Downloads (0)'));
    await tester.pumpAndSettle();

    // Initially shows empty state
    expect(find.text('No downloaded songs'), findsOneWidget);

    // Simulate an active download with 50% progress
    final task = ActiveDownloadTask(
      item: testItem,
      status: DownloadStatus.downloading,
      progress: 0.5,
      receivedBytes: 1024 * 1024,
      totalBytes: 2 * 1024 * 1024,
    );
    downloadService.addTaskForTesting(task);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Verify TabBar label updates to show active count
    expect(find.text('Downloads (0 • 1 active)'), findsOneWidget);

    // Verify "DOWNLOADING (1)" section appears
    expect(find.text('DOWNLOADING (1)'), findsOneWidget);
    expect(find.text('Never Gonna Give You Up'), findsOneWidget);
    expect(find.text('Rick Astley'), findsOneWidget);
    expect(find.text('50% (1.0 / 2.0 MB)'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);

    // Verify progress bar is rendered with 0.5 value
    final progressFinder = find.byType(LinearProgressIndicator);
    expect(progressFinder, findsOneWidget);
    final progressWidget = tester.widget<LinearProgressIndicator>(progressFinder);
    expect(progressWidget.value, 0.5);

    // Verify cancel button is present and works
    final cancelBtn = find.byTooltip('Cancel download');
    expect(cancelBtn, findsOneWidget);
    await tester.tap(cancelBtn);
    await tester.pump();

    expect(downloadService.isDownloading(testItem.id), isFalse);
  });

  testWidgets('LibraryScreen shows failed download section with retry and dismiss', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          playback: playback,
          storage: storage,
          downloadService: downloadService,
        ),
      ),
    );

    await tester.tap(find.text('Downloads (0)'));
    await tester.pumpAndSettle();

    // Add a failed task
    final failedTask = ActiveDownloadTask(
      item: testItem,
      status: DownloadStatus.failed,
      errorMessage: 'Network error: could not connect to server.',
    );
    downloadService.addTaskForTesting(failedTask);
    await tester.pumpAndSettle();

    expect(find.text('FAILED DOWNLOADS (1)'), findsOneWidget);
    expect(find.text('Never Gonna Give You Up'), findsOneWidget);
    expect(find.text('Network error: could not connect to server.'), findsOneWidget);

    // Test dismiss
    final dismissBtn = find.byTooltip('Dismiss');
    expect(dismissBtn, findsOneWidget);
    await tester.tap(dismissBtn);
    await tester.pumpAndSettle();

    expect(find.text('FAILED DOWNLOADS (1)'), findsNothing);
    expect(find.text('No downloaded songs'), findsOneWidget);
  });
}
