import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/download_item.dart';
import '../models/youtube_search_item.dart';
import 'storage_service.dart';

enum DownloadStatus {
  connecting,
  downloading,
  completed,
  failed,
}

class ActiveDownloadTask {
  ActiveDownloadTask({
    required this.item,
    this.status = DownloadStatus.connecting,
    this.progress = 0.0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.errorMessage,
  });

  final YoutubeSearchItem item;
  DownloadStatus status;
  double progress;
  int receivedBytes;
  int totalBytes;
  String? errorMessage;

  bool get isRunning =>
      status == DownloadStatus.connecting || status == DownloadStatus.downloading;

  String get statusText {
    switch (status) {
      case DownloadStatus.connecting:
        return 'Connecting to YouTube...';
      case DownloadStatus.downloading:
        final pct = (progress * 100).toInt();
        if (totalBytes > 0) {
          final recMb = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
          final totMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
          return '$pct% ($recMb / $totMb MB)';
        }
        return '$pct%';
      case DownloadStatus.completed:
        return 'Complete';
      case DownloadStatus.failed:
        return 'Failed: ${errorMessage ?? 'Unknown error'}';
    }
  }
}

class _DownloadCancelledException implements Exception {}

class DownloadService extends ChangeNotifier {
  DownloadService({
    required StorageService storageService,
    Directory? downloadDir,
  })  : _storageService = storageService,
        _overrideDownloadDir = downloadDir;

  final StorageService _storageService;
  final Directory? _overrideDownloadDir;

  final Map<String, ActiveDownloadTask> _tasks = {};
  final Set<String> _cancelledIds = {};

  List<ActiveDownloadTask> get activeTasks =>
      _tasks.values.where((t) => t.isRunning).toList();

  List<ActiveDownloadTask> get failedTasks =>
      _tasks.values.where((t) => t.status == DownloadStatus.failed).toList();

  ActiveDownloadTask? getTask(String videoId) => _tasks[videoId];

  bool isDownloading(String videoId) => _tasks[videoId]?.isRunning ?? false;

  double getProgress(String videoId) => _tasks[videoId]?.progress ?? 0.0;

  Future<String> _getDownloadsDirPath() async {
    if (_overrideDownloadDir != null) {
      if (!await _overrideDownloadDir.exists()) {
        await _overrideDownloadDir.create(recursive: true);
      }
      return _overrideDownloadDir.path;
    }
    final dir = await getApplicationDocumentsDirectory();
    final downloadsDir = Directory('${dir.path}/downloads');
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }
    return downloadsDir.path;
  }

  Future<void> downloadTrack(YoutubeSearchItem item) async {
    if (isDownloading(item.id)) return;

    _cancelledIds.remove(item.id);
    final task = ActiveDownloadTask(
      item: item,
      status: DownloadStatus.connecting,
    );
    _tasks[item.id] = task;
    notifyListeners();

    final yt = YoutubeExplode();
    IOSink? sink;
    File? targetFile;

    try {
      StreamManifest manifest;
      try {
        manifest = await yt.videos.streamsClient
            .getManifest(
              item.id,
              ytClients: [
                YoutubeApiClient.androidSdkless,
                YoutubeApiClient.ios,
                YoutubeApiClient.androidMusic,
              ],
              requireWatchPage: false,
            )
            .timeout(const Duration(seconds: 25));
      } catch (_) {
        manifest = await yt.videos.streamsClient
            .getManifest(item.id)
            .timeout(const Duration(seconds: 30));
      }

      if (_cancelledIds.contains(item.id)) {
        throw _DownloadCancelledException();
      }

      // Prioritize Stream 18 (universal 360p MP4 with AAC audio, unthrottled with ratebypass=yes)
      // Fall back to pure audio-only streams if itag 18 is not available.
      final stream18 = manifest.muxed.where((s) => s.tag == 18).firstOrNull;
      final audioStreams = manifest.audioOnly;
      final StreamInfo streamInfo;
      final String fileExt;

      if (stream18 != null) {
        streamInfo = stream18;
        fileExt = 'mp4';
      } else if (audioStreams.isNotEmpty) {
        final mp4Streams = audioStreams.where(
          (s) => s.container == StreamContainer.mp4,
        );
        streamInfo = (mp4Streams.isNotEmpty ? mp4Streams : audioStreams)
            .withHighestBitrate();
        fileExt = streamInfo.container == StreamContainer.mp4 ? 'm4a' : streamInfo.container.name;
      } else if (manifest.muxed.isNotEmpty) {
        streamInfo = manifest.muxed.first;
        fileExt = 'mp4';
      } else {
        throw StateError('No playable stream found for this track.');
      }

      final downloadsDir = await _getDownloadsDirPath();
      final filePath = '$downloadsDir/${item.id}.$fileExt';
      targetFile = File(filePath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      task.status = DownloadStatus.downloading;
      final totalBytes = streamInfo.size.totalBytes;
      task.totalBytes = totalBytes;
      task.receivedBytes = 0;
      task.progress = 0.0;
      notifyListeners();

      sink = targetFile.openWrite(mode: FileMode.append);

      final httpClient = HttpClient();
      httpClient.connectionTimeout = const Duration(seconds: 15);
      const chunkSize = 512 * 1024; // 512 KB
      var bytesWritten = 0;

      try {
        if (totalBytes > 0) {
          for (var start = 0; start < totalBytes; start += chunkSize) {
            if (_cancelledIds.contains(item.id)) {
              throw _DownloadCancelledException();
            }

            final end = (start + chunkSize - 1 < totalBytes)
                ? start + chunkSize - 1
                : totalBytes - 1;

            var chunkSuccess = false;
            Object? lastChunkError;

            for (var attempt = 1; attempt <= 4; attempt++) {
              if (_cancelledIds.contains(item.id)) {
                throw _DownloadCancelledException();
              }

              try {
                final req = await httpClient
                    .getUrl(streamInfo.url)
                    .timeout(const Duration(seconds: 25));
                req.headers.set('Range', 'bytes=$start-$end');
                final res = await req.close().timeout(const Duration(seconds: 25));

                if (res.statusCode == 206 || res.statusCode == 200) {
                  final chunk = await res.fold<List<int>>(
                    [],
                    (prev, element) => prev..addAll(element),
                  );
                  sink.add(chunk);
                  bytesWritten += chunk.length;
                  task.receivedBytes = bytesWritten;
                  task.progress = (bytesWritten / totalBytes).clamp(0.0, 1.0);
                  notifyListeners();
                  chunkSuccess = true;
                  break;
                } else {
                  lastChunkError = HttpException('Server returned status ${res.statusCode}');
                  await res.drain();
                }
              } catch (e) {
                lastChunkError = e;
                if (attempt < 4) {
                  await Future.delayed(Duration(milliseconds: 500 * attempt));
                }
              }
            }

            if (!chunkSuccess) {
              throw lastChunkError ?? Exception('Failed to download chunk $start-$end');
            }
          }
        } else {
          // Fallback if totalBytes is unknown
          final req = await httpClient.getUrl(streamInfo.url);
          final res = await req.close();
          await for (final chunk in res) {
            if (_cancelledIds.contains(item.id)) {
              throw _DownloadCancelledException();
            }
            sink.add(chunk);
            bytesWritten += chunk.length;
            task.receivedBytes = bytesWritten;
            notifyListeners();
          }
        }
      } finally {
        httpClient.close();
      }

      await sink.flush();
      await sink.close();
      sink = null;

      task.status = DownloadStatus.completed;
      task.progress = 1.0;
      task.receivedBytes = bytesWritten;
      _tasks.remove(item.id);

      final downloadItem = DownloadItem(
        item: item,
        localPath: filePath,
        fileSize: bytesWritten,
        downloadedAt: DateTime.now(),
      );
      await _storageService.saveDownload(downloadItem);
      notifyListeners();
    } on _DownloadCancelledException {
      if (kDebugMode) debugPrint('Download cancelled for ${item.id}');
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      if (targetFile != null && await targetFile.exists()) {
        try {
          await targetFile.delete();
        } catch (_) {}
      }
      _tasks.remove(item.id);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('Download failed for ${item.id}: $e');
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      if (targetFile != null && await targetFile.exists()) {
        try {
          await targetFile.delete();
        } catch (_) {}
      }
      task.status = DownloadStatus.failed;
      task.errorMessage = _cleanErrorMessage(e);
      notifyListeners();
    } finally {
      yt.close();
      _cancelledIds.remove(item.id);
    }
  }

  void cancelDownload(String videoId) {
    _cancelledIds.add(videoId);
    _tasks.remove(videoId);
    notifyListeners();
  }

  void dismissFailedTask(String videoId) {
    _tasks.remove(videoId);
    notifyListeners();
  }

  @visibleForTesting
  void addTaskForTesting(ActiveDownloadTask task) {
    _tasks[task.item.id] = task;
    notifyListeners();
  }

  Future<void> deleteDownload(String videoId) async {
    final download = _storageService.getDownload(videoId);
    if (download != null) {
      final file = File(download.localPath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (e) {
          if (kDebugMode) debugPrint('Could not delete file: $e');
        }
      }
      await _storageService.removeDownload(videoId);
      notifyListeners();
    }
  }

  Future<void> clearAllDownloads() async {
    for (final download in List.of(_storageService.downloads)) {
      await deleteDownload(download.item.id);
    }
  }

  String _cleanErrorMessage(Object error) {
    if (error is TimeoutException) {
      return 'Connection timed out. Check your network.';
    }
    if (error is SocketException) {
      return 'Network error: could not connect to server.';
    }
    final str = error.toString();
    if (str.contains('403')) {
      return 'Access restricted by YouTube (403 Forbidden).';
    }
    if (str.contains('No audio stream')) {
      return 'No playable audio stream available.';
    }
    return str.replaceFirst('Exception: ', '').replaceFirst('StateError: ', '');
  }
}
