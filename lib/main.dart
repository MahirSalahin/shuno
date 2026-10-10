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

class ShunoApp extends StatefulWidget {
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
  State<ShunoApp> createState() => _ShunoAppState();
}

class _ShunoAppState extends State<ShunoApp> with WidgetsBindingObserver {
  late final StorageService _storage;
  late final YoutubeService _youtube;
  late final PlaybackController _playback;
  late final DownloadService _download;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _storage = widget.storageService ?? StorageService();
    _youtube = widget.youtubeService ?? YoutubeService();
    _playback = widget.playbackController ??
        PlaybackController(
          youtubeService: _youtube,
          storageService: _storage,
        );
    _download =
        widget.downloadService ?? DownloadService(storageService: _storage);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_storage.flushPendingSave());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(_storage.flushPendingSave());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: _storage.themeNotifier,
      builder: (context, themeKey, _) {
        final palette = AppPalette.fromId(themeKey);
        return MaterialApp(
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          title: 'Shuno',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.buildTheme(palette),
          home: HomeNavigationScreen(
            youtubeService: _youtube,
            storageService: _storage,
            playbackController: _playback,
            downloadService: _download,
          ),
        );
      },
    );
  }
}

