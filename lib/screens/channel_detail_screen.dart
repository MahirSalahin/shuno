import 'package:flutter/material.dart';

import '../models/youtube_channel_item.dart';
import '../models/youtube_search_item.dart';
import '../services/download_service.dart';
import '../services/playback_controller.dart';
import '../services/storage_service.dart';
import '../services/youtube_service.dart';
import '../widgets/playback_bar.dart';
import '../widgets/track_tile.dart';

class ChannelDetailScreen extends StatefulWidget {
  const ChannelDetailScreen({
    super.key,
    required this.channel,
    required this.youtubeService,
    required this.playback,
    required this.storage,
    this.downloadService,
  });

  final YoutubeChannelItem channel;
  final YoutubeService youtubeService;
  final PlaybackController playback;
  final StorageService storage;
  final DownloadService? downloadService;

  @override
  State<ChannelDetailScreen> createState() => _ChannelDetailScreenState();
}

class _ChannelDetailScreenState extends State<ChannelDetailScreen> {
  late YoutubeChannelItem _channel;
  List<YoutubeSearchItem> _videos = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _channel = widget.channel;
    widget.playback.addListener(_onUpdate);
    widget.storage.addListener(_onUpdate);
    widget.downloadService?.addListener(_onUpdate);
    _loadChannelData();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.playback.removeListener(_onUpdate);
    widget.storage.removeListener(_onUpdate);
    widget.downloadService?.removeListener(_onUpdate);
    super.dispose();
  }

  Future<void> _loadChannelData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final videosFuture = widget.youtubeService.getChannelVideos(
        _channel.id,
        channelName: _channel.title,
      );
      final detailsFuture = _channel.subscriberCount == null
          ? widget.youtubeService.getChannel(_channel.id)
          : Future.value(null);

      final results = await Future.wait([videosFuture, detailsFuture]);
      if (!mounted) return;

      final videos = results[0] as List<YoutubeSearchItem>;
      final details = results[1] as YoutubeChannelItem?;

      setState(() {
        _videos = videos;
        if (details != null) {
          _channel = YoutubeChannelItem(
            id: _channel.id,
            title: details.title.isNotEmpty ? details.title : _channel.title,
            thumbnailUrl: details.thumbnailUrl.isNotEmpty
                ? details.thumbnailUrl
                : _channel.thumbnailUrl,
            subscriberCount: details.subscriberCount ?? _channel.subscriberCount,
            videoCount: details.videoCount ?? _channel.videoCount,
            description: details.description ?? _channel.description,
          );
        }
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load channel tracks. Please try again.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subs = _channel.formattedSubscribers;
    final videoCount = _channel.formattedVideoCount;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _channel.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      bottomNavigationBar: widget.playback.selected != null
          ? SafeArea(
              top: false,
              child: PlaybackBar(
                controller: widget.playback,
                storageService: widget.storage,
                downloadService: widget.downloadService,
              ),
            )
          : null,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(semanticsLabel: 'Loading channel tracks'),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 48,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.tonal(
                          onPressed: _loadChannelData,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    // Channel Header
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Column(
                          children: [
                            // Circular Avatar
                            Container(
                              width: 84,
                              height: 84,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.colorScheme.primary.withAlpha(120),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.colorScheme.primary.withAlpha(40),
                                    blurRadius: 16,
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: _channel.thumbnailUrl.isNotEmpty
                                    ? Image.network(
                                        _channel.thumbnailUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) =>
                                            Container(
                                          color: theme.colorScheme.surfaceContainerHighest,
                                          child: const Icon(Icons.person, size: 40),
                                        ),
                                      )
                                    : Container(
                                        color: theme.colorScheme.surfaceContainerHighest,
                                        child: const Icon(Icons.person, size: 40),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Channel Title
                            Text(
                              _channel.title,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 4),

                            // Subtitle info
                            if (subs != null || videoCount != null)
                              Text(
                                [subs, videoCount].whereType<String>().join(' • '),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            const SizedBox(height: 14),

                            // Action buttons: Play All / Shuffle
                            if (_videos.isNotEmpty)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  FilledButton.icon(
                                    icon: const Icon(Icons.play_arrow, size: 20),
                                    label: const Text('Play All'),
                                    onPressed: () => widget.playback.playQueue(_videos),
                                  ),
                                  const SizedBox(width: 10),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.shuffle, size: 18),
                                    label: const Text('Shuffle'),
                                    onPressed: () {
                                      final shuffled = List<YoutubeSearchItem>.from(_videos)..shuffle();
                                      widget.playback.playQueue(shuffled);
                                    },
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),

                    // Section Title
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'TRACKS (${_videos.length})',
                              style: theme.textTheme.labelMedium?.copyWith(
                                letterSpacing: 1.2,
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Tracks List
                    if (_videos.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text('No tracks available from this channel.'),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.only(bottom: 100),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final item = _videos[index];
                              return TrackTile(
                                item: item,
                                playback: widget.playback,
                                storage: widget.storage,
                                downloadService: widget.downloadService,
                              );
                            },
                            childCount: _videos.length,
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
