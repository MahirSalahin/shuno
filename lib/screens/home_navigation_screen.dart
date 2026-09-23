import 'package:flutter/material.dart';

import '../services/download_service.dart';
import '../services/playback_controller.dart';
import '../services/storage_service.dart';
import '../services/youtube_service.dart';
import '../widgets/playback_bar.dart';
import 'library_screen.dart';
import 'queue_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class HomeNavigationScreen extends StatefulWidget {
  const HomeNavigationScreen({
    super.key,
    required this.youtubeService,
    required this.storageService,
    required this.playbackController,
    required this.downloadService,
  });

  final YoutubeService youtubeService;
  final StorageService storageService;
  final PlaybackController playbackController;
  final DownloadService downloadService;

  @override
  State<HomeNavigationScreen> createState() => _HomeNavigationScreenState();
}

class _HomeNavigationScreenState extends State<HomeNavigationScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.playbackController.addListener(_onUpdate);
    widget.storageService.addListener(_onUpdate);
    widget.downloadService.addListener(_onUpdate);
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.playbackController.removeListener(_onUpdate);
    widget.storageService.removeListener(_onUpdate);
    widget.downloadService.removeListener(_onUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final upcomingCount = widget.playbackController.upNext.length;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          SearchScreen(
            youtubeService: widget.youtubeService,
            playbackController: widget.playbackController,
            storageService: widget.storageService,
            downloadService: widget.downloadService,
            showBottomPlayer: false,
          ),
          LibraryScreen(
            playback: widget.playbackController,
            storage: widget.storageService,
            downloadService: widget.downloadService,
          ),
          QueueScreen(
            playback: widget.playbackController,
            storage: widget.storageService,
            downloadService: widget.downloadService,
          ),
          SettingsScreen(
            storage: widget.storageService,
            downloadService: widget.downloadService,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.playbackController.selected != null)
              PlaybackBar(
                controller: widget.playbackController,
                storageService: widget.storageService,
                downloadService: widget.downloadService,
                onOpenQueue: () => setState(() => _currentIndex = 2),
              ),
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant.withAlpha(80),
                    width: 1,
                  ),
                ),
              ),
              child: NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: (index) =>
                    setState(() => _currentIndex = index),
                destinations: [
                  const NavigationDestination(
                    icon: Icon(Icons.search),
                    selectedIcon: Icon(Icons.search),
                    label: 'Search',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.library_music_outlined),
                    selectedIcon: Icon(Icons.library_music),
                    label: 'Library',
                  ),
                  NavigationDestination(
                    icon: Badge(
                      isLabelVisible: upcomingCount > 0,
                      label: Text('$upcomingCount'),
                      child: const Icon(Icons.queue_music_outlined),
                    ),
                    selectedIcon: Badge(
                      isLabelVisible: upcomingCount > 0,
                      label: Text('$upcomingCount'),
                      child: const Icon(Icons.queue_music),
                    ),
                    label: 'Queue',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: 'Settings',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
