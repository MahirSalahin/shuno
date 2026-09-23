import 'package:flutter/material.dart';

import '../models/youtube_channel_item.dart';
import '../models/youtube_playlist_item.dart';
import '../models/youtube_search_item.dart';
import '../services/download_service.dart';
import '../services/playback_controller.dart';
import '../services/storage_service.dart';
import '../services/youtube_service.dart';
import '../widgets/channel_playlist_tile.dart';
import '../widgets/playback_bar.dart';
import '../widgets/track_tile.dart';
import 'youtube_playlist_detail_screen.dart';

enum ChannelTab { tracks, playlists }

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
  final _searchController = TextEditingController();
  final _playlistSearchController = TextEditingController();

  List<YoutubeSearchItem> _videos = [];
  List<YoutubePlaylistItem> _playlists = [];
  ChannelTab _currentTab = ChannelTab.tracks;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreUploads = false;
  dynamic _uploadContinuation;

  bool _isLoadingMorePlaylists = false;
  bool _hasMorePlaylists = false;
  String? _playlistContinuation;

  List<YoutubeSearchItem>? _inChannelSearchResults;
  List<YoutubePlaylistItem>? _inPlaylistSearchResults;
  bool _isSearchingInChannel = false;
  String? _error;

  String? _lastPlayingId;
  bool _lastIsPlaying = false;
  bool _lastIsBuffering = false;
  bool _lastIsLoading = false;

  @override
  void initState() {
    super.initState();
    _channel = widget.channel;
    _lastPlayingId = widget.playback.selected?.id;
    _lastIsPlaying = widget.playback.isPlaying;
    _lastIsBuffering = widget.playback.isBuffering;
    _lastIsLoading = widget.playback.isLoading;
    widget.playback.addListener(_onPlaybackUpdate);
    widget.storage.addListener(_onServiceUpdate);
    widget.downloadService?.addListener(_onServiceUpdate);
    _loadChannelData();
  }

  void _onPlaybackUpdate() {
    final curId = widget.playback.selected?.id;
    final curPlaying = widget.playback.isPlaying;
    final curBuffering = widget.playback.isBuffering;
    final curLoading = widget.playback.isLoading;
    if (curId != _lastPlayingId ||
        curPlaying != _lastIsPlaying ||
        curBuffering != _lastIsBuffering ||
        curLoading != _lastIsLoading) {
      _lastPlayingId = curId;
      _lastIsPlaying = curPlaying;
      _lastIsBuffering = curBuffering;
      _lastIsLoading = curLoading;
      if (mounted) setState(() {});
    }
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.playback.removeListener(_onPlaybackUpdate);
    widget.storage.removeListener(_onServiceUpdate);
    widget.downloadService?.removeListener(_onServiceUpdate);
    _searchController.dispose();
    _playlistSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadChannelData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      ChannelUploadsPage pageResult;
      try {
        pageResult = await widget.youtubeService.getChannelUploadsPage(
          _channel.id,
          channelName: _channel.title,
        );
      } catch (_) {
        final videos = await widget.youtubeService.getChannelVideos(
          _channel.id,
          channelName: _channel.title,
        );
        pageResult = ChannelUploadsPage(items: videos, hasMore: false);
      }

      if (pageResult.items.isEmpty) {
        final videos = await widget.youtubeService.getChannelVideos(
          _channel.id,
          channelName: _channel.title,
        );
        if (videos.isNotEmpty) {
          pageResult = ChannelUploadsPage(items: videos, hasMore: false);
        }
      }

      final detailsFuture = _channel.subscriberCount == null
          ? widget.youtubeService.getChannel(_channel.id)
          : Future.value(null);

      final playlistsFuture = () async {
        try {
          return await widget.youtubeService.getChannelPlaylistsPage(
            _channel.title,
            channelId: _channel.id,
          );
        } catch (_) {
          return const ChannelPlaylistsPage(items: []);
        }
      }();

      final results = await Future.wait([detailsFuture, playlistsFuture]);
      if (!mounted) return;

      final details = results[0] as YoutubeChannelItem?;
      final playlistsPage = results[1] as ChannelPlaylistsPage;

      setState(() {
        _videos = pageResult.items;
        _hasMoreUploads = pageResult.hasMore;
        _uploadContinuation = pageResult.continuation;
        _playlists = playlistsPage.items;
        _hasMorePlaylists = playlistsPage.hasMore;
        _playlistContinuation = playlistsPage.continuation;

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

  Future<void> _loadMoreUploads() async {
    if (_isLoadingMore || !_hasMoreUploads) return;
    setState(() => _isLoadingMore = true);

    try {
      final nextPage = await widget.youtubeService.getChannelUploadsPage(
        _channel.id,
        channelName: _channel.title,
        continuation: _uploadContinuation,
      );
      if (!mounted) return;
      setState(() {
        _videos.addAll(nextPage.items);
        _hasMoreUploads = nextPage.hasMore;
        _uploadContinuation = nextPage.continuation;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _searchInChannel(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _inChannelSearchResults = null;
        _isSearchingInChannel = false;
      });
      return;
    }

    setState(() => _isSearchingInChannel = true);

    try {
      final deepResults = await widget.youtubeService.searchChannelTracks(
        _channel.id,
        trimmed,
        channelName: _channel.title,
      );
      if (!mounted) return;

      // Filter locally loaded tracks as well
      final localMatches = _videos
          .where(
            (v) =>
                v.title.toLowerCase().contains(trimmed.toLowerCase()) ||
                v.channelName.toLowerCase().contains(trimmed.toLowerCase()),
          )
          .toList();

      // Combine and deduplicate
      final seenIds = <String>{};
      final combined = <YoutubeSearchItem>[];
      for (final item in [...localMatches, ...deepResults]) {
        if (seenIds.add(item.id)) combined.add(item);
      }

      setState(() {
        _inChannelSearchResults = combined;
        _isSearchingInChannel = false;
      });
    } catch (_) {
      if (mounted) {
        // Fallback to local filtering
        final localMatches = _videos
            .where(
              (v) =>
                  v.title.toLowerCase().contains(trimmed.toLowerCase()) ||
                  v.channelName.toLowerCase().contains(trimmed.toLowerCase()),
            )
            .toList();
        setState(() {
          _inChannelSearchResults = localMatches;
          _isSearchingInChannel = false;
        });
      }
    }
  }

  Future<void> _loadMorePlaylists() async {
    if (_isLoadingMorePlaylists || !_hasMorePlaylists) return;
    setState(() => _isLoadingMorePlaylists = true);

    try {
      final nextPage = await widget.youtubeService.getChannelPlaylistsPage(
        _channel.title,
        channelId: _channel.id,
        continuation: _playlistContinuation,
      );
      if (!mounted) return;
      setState(() {
        _playlists.addAll(nextPage.items);
        _hasMorePlaylists = nextPage.hasMore;
        _playlistContinuation = nextPage.continuation;
        _isLoadingMorePlaylists = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMorePlaylists = false);
    }
  }

  void _searchInPlaylists(String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      setState(() => _inPlaylistSearchResults = null);
      return;
    }
    final matches = _playlists
        .where(
          (p) =>
              p.title.toLowerCase().contains(trimmed) ||
              (p.author?.toLowerCase().contains(trimmed) ?? false),
        )
        .toList();
    setState(() => _inPlaylistSearchResults = matches);
  }

  void _clearPlaylistSearch() {
    _playlistSearchController.clear();
    setState(() => _inPlaylistSearchResults = null);
  }

  void _clearInChannelSearch() {
    _searchController.clear();
    setState(() {
      _inChannelSearchResults = null;
      _isSearchingInChannel = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subs = _channel.formattedSubscribers;
    final videoCount = _channel.formattedVideoCount;

    final displayedVideos = _inChannelSearchResults ?? _videos;
    final displayedPlaylists = _inPlaylistSearchResults ?? _playlists;

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
              child: CircularProgressIndicator(
                semanticsLabel: 'Loading channel tracks',
              ),
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
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                                        cacheWidth: 240,
                                        cacheHeight: 240,
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
                                    onPressed: () => widget.playback.playQueue(
                                      displayedVideos.isNotEmpty
                                          ? displayedVideos
                                          : _videos,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.shuffle, size: 18),
                                    label: const Text('Shuffle'),
                                    onPressed: () {
                                      final pool = displayedVideos.isNotEmpty
                                          ? displayedVideos
                                          : _videos;
                                      final shuffled =
                                          List<YoutubeSearchItem>.from(pool)
                                            ..shuffle();
                                      widget.playback.playQueue(shuffled);
                                    },
                                  ),
                                ],
                              ),
                            const SizedBox(height: 16),

                            // Channel Exploration Tabs: Tracks & Playlists
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ChoiceChip(
                                    label: const Text('Tracks'),
                                    selected: _currentTab == ChannelTab.tracks,
                                    showCheckmark: false,
                                    avatar: const Icon(Icons.music_note, size: 16),
                                    visualDensity: VisualDensity.compact,
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() => _currentTab = ChannelTab.tracks);
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  ChoiceChip(
                                    label: const Text('Playlists'),
                                    selected: _currentTab == ChannelTab.playlists,
                                    showCheckmark: false,
                                    avatar: const Icon(Icons.playlist_play, size: 18),
                                    visualDensity: VisualDensity.compact,
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() => _currentTab = ChannelTab.playlists);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // TRACKS TAB VIEW
                    if (_currentTab == ChannelTab.tracks) ...[
                      // In-Channel Search Input
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: TextField(
                            controller: _searchController,
                            textInputAction: TextInputAction.search,
                            onSubmitted: _searchInChannel,
                            decoration: InputDecoration(
                              hintText: 'Search in ${_channel.title}…',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: _clearInChannelSearch,
                                    )
                                  : null,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                            ),
                          ),
                        ),
                      ),

                      // In-Channel Searching Indicator
                      if (_isSearchingInChannel)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                        ),

                      // Search Status Header if searching
                      if (_inChannelSearchResults != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'SEARCH RESULTS (${displayedVideos.length})',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    letterSpacing: 1.1,
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                TextButton(
                                  onPressed: _clearInChannelSearch,
                                  child: const Text('Show All'),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Tracks List
                      if (displayedVideos.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _inChannelSearchResults != null
                                    ? 'No tracks matching "${_searchController.text}".'
                                    : 'No tracks available from this channel.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        )
                      else ...[
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final item = displayedVideos[index];
                              return TrackTile(
                                key: ValueKey(item.id),
                                item: item,
                                playback: widget.playback,
                                storage: widget.storage,
                                downloadService: widget.downloadService,
                              );
                            },
                            childCount: displayedVideos.length,
                          ),
                        ),

                        // Load More / Pagination Button
                        if (_inChannelSearchResults == null && _hasMoreUploads)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 16,
                              ),
                              child: Center(
                                child: _isLoadingMore
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : FilledButton.tonalIcon(
                                        icon: const Icon(
                                          Icons.expand_more,
                                          size: 18,
                                        ),
                                        label: const Text('Load More Tracks'),
                                        onPressed: _loadMoreUploads,
                                      ),
                              ),
                            ),
                          ),

                        const SliverToBoxAdapter(
                          child: SizedBox(height: 100),
                        ),
                      ],
                    ],

                    // PLAYLISTS TAB VIEW
                    if (_currentTab == ChannelTab.playlists) ...[
                      // In-Channel Playlist Search Input
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: TextField(
                            controller: _playlistSearchController,
                            textInputAction: TextInputAction.search,
                            onChanged: _searchInPlaylists,
                            onSubmitted: _searchInPlaylists,
                            decoration: InputDecoration(
                              hintText: 'Search playlists in ${_channel.title}…',
                              prefixIcon: const Icon(Icons.search, size: 20),
                              suffixIcon: _playlistSearchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: _clearPlaylistSearch,
                                    )
                                  : null,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: theme.colorScheme.surfaceContainerHighest
                                  .withAlpha(120),
                            ),
                          ),
                        ),
                      ),

                      if (_inPlaylistSearchResults != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Row(
                              children: [
                                Text(
                                  'Matching Playlists (${displayedPlaylists.length})',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: _clearPlaylistSearch,
                                  child: const Text('Show All'),
                                ),
                              ],
                            ),
                          ),
                        ),

                      if (displayedPlaylists.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _inPlaylistSearchResults != null
                                    ? 'No playlists matching "${_playlistSearchController.text}".'
                                    : 'No playlists found for this channel.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        )
                      else ...[
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final playlist = displayedPlaylists[index];
                              return ChannelPlaylistTile(
                                key: ValueKey(playlist.id),
                                playlist: playlist,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          YoutubePlaylistDetailScreen(
                                        playlist: playlist,
                                        youtubeService: widget.youtubeService,
                                        playback: widget.playback,
                                        storage: widget.storage,
                                        downloadService:
                                            widget.downloadService ??
                                                DownloadService(
                                                  storageService: widget.storage,
                                                ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                            childCount: displayedPlaylists.length,
                          ),
                        ),

                        // Load More Playlists Button
                        if (_inPlaylistSearchResults == null && _hasMorePlaylists)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                                vertical: 16,
                              ),
                              child: Center(
                                child: _isLoadingMorePlaylists
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : FilledButton.tonalIcon(
                                        icon: const Icon(
                                          Icons.expand_more,
                                          size: 18,
                                        ),
                                        label: const Text('Load More Playlists'),
                                        onPressed: _loadMorePlaylists,
                                      ),
                              ),
                            ),
                          ),

                        const SliverToBoxAdapter(
                          child: SizedBox(height: 100),
                        ),
                      ],
                    ],
                  ],
                ),
    );
  }
}
