import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'screens/home_navigation_screen.dart';
import 'services/download_service.dart';
import 'services/playback_controller.dart';
import 'services/storage_service.dart';
import 'services/youtube_service.dart';
import 'theme/app_theme.dart';

final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storageService = StorageService();

  // Initialize background audio and storage in parallel before runApp
  await Future.wait([
    JustAudioBackground.init(
      androidNotificationChannelId: 'com.example.shuno.audio',
      androidNotificationChannelName: 'Shuno Audio Playback',
      androidNotificationOngoing: true,
      androidNotificationIcon: 'drawable/splash_icon',
    ).catchError((e) {
      if (kDebugMode) debugPrint('JustAudioBackground init skipped or failed: $e');
    }),
    storageService.init(),
  ]);

  final youtubeService = YoutubeService();
  final playbackController = PlaybackController(
    youtubeService: youtubeService,
    storageService: storageService,
  );
  final downloadService = DownloadService(storageService: storageService);

  runApp(
    ShunoApp(
      youtubeService: youtubeService,
      storageService: storageService,
      playbackController: playbackController,
      downloadService: downloadService,
    ),
  );
}

class ShunoApp extends StatelessWidget {
  const ShunoApp({
    super.key,
    this.youtubeService,
    this.storageService,
    this.playbackController,
    this.downloadService,
  });

  final YoutubeService? youtubeService;
  final StorageService? storageService;
  final PlaybackController? playbackController;
  final DownloadService? downloadService;

  @override
  Widget build(BuildContext context) {
    final storage = storageService ?? StorageService();
    final youtube = youtubeService ?? YoutubeService();
    final playback =
        playbackController ??
        PlaybackController(
          youtubeService: youtube,
          storageService: storage,
        );
    final download = downloadService ?? DownloadService(storageService: storage);

    return ValueListenableBuilder<String>(
      valueListenable: storage.themeNotifier,
      builder: (context, themeKey, _) {
        final palette = AppPalette.fromId(themeKey);
        return MaterialApp(
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          title: 'Shuno',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.buildTheme(palette),
          home: HomeNavigationScreen(
            youtubeService: youtube,
            storageService: storage,
            playbackController: playback,
            downloadService: download,
          ),
        );
      },
    );
  }
}

