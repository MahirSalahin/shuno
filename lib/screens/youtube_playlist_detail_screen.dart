import 'package:flutter/material.dart';

import '../models/youtube_playlist_item.dart';
import '../models/youtube_search_item.dart';
import '../services/download_service.dart';
import '../services/playback_controller.dart';
import '../services/storage_service.dart';
import '../services/youtube_service.dart';
import '../widgets/playback_bar.dart';
import '../widgets/track_tile.dart';

class YoutubePlaylistDetailScreen extends StatefulWidget {
  const YoutubePlaylistDetailScreen({
    super.key,
    required this.playlist,
    this.youtubeService,
    required this.playback,
    required this.storage,
    required this.downloadService,
  });

  final YoutubePlaylistItem playlist;
  final YoutubeService? youtubeService;
  final PlaybackController playback;
  final StorageService storage;
  final DownloadService downloadService;

  @override
  State<YoutubePlaylistDetailScreen> createState() =>
      _YoutubePlaylistDetailScreenState();
}

class _YoutubePlaylistDetailScreenState
    extends State<YoutubePlaylistDetailScreen> {
  late final _youtubeService = widget.youtubeService ?? YoutubeService();

  List<YoutubeSearchItem> _tracks = [];
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTracks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final tracks = await _youtubeService.getPlaylistTracks(
        widget.playlist.id,
      );
      if (mounted) {
        setState(() {
          _tracks = tracks;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load playlist tracks. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _searchQuery.trim().toLowerCase();
    final displayedTracks = query.isEmpty
        ? _tracks
        : _tracks
            .where(
              (t) =>
                  t.title.toLowerCase().contains(query) ||
                  t.channelName.toLowerCase().contains(query),
            )
            .toList();

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // App Bar
              SliverAppBar(
                pinned: true,
                expandedHeight: 280,
                backgroundColor: theme.scaffoldBackgroundColor,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Gradient background
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              theme.colorScheme.primary.withAlpha(50),
                              theme.scaffoldBackgroundColor,
                            ],
                          ),
                        ),
                      ),
                      SafeArea(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 16),
                            // Artwork
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(120),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(
                                  width: 120,
                                  height: 120,
                                  child: widget.playlist.thumbnailUrl.isNotEmpty
                                      ? Image.network(
                                          widget.playlist.thumbnailUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  _buildPlaceholder(theme),
                                        )
                                      : _buildPlaceholder(theme),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                widget.playlist.title,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.playlist.author != null
                                  ? '${widget.playlist.author} • ${widget.playlist.videoCountLabel}'
                                  : widget.playlist.videoCountLabel,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Action Buttons Header: Play All / Shuffle
              if (!_isLoading && _tracks.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FilledButton.icon(
                          icon: const Icon(Icons.play_arrow, size: 20),
                          label: const Text('Play All'),
                          onPressed: () => widget.playback.playQueue(
                            displayedTracks.isNotEmpty ? displayedTracks : _tracks,
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.shuffle, size: 18),
                          label: const Text('Shuffle'),
                          onPressed: () {
                            final pool = displayedTracks.isNotEmpty
                                ? displayedTracks
                                : _tracks;
                            final shuffled =
                                List<YoutubeSearchItem>.from(pool)..shuffle();
                            widget.playback.playQueue(shuffled);
                          },
                        ),
                      ],
                    ),
                  ),
                ),

              // In-Playlist Search Input
              if (!_isLoading && _tracks.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) =>
                          setState(() => _searchQuery = val.trim()),
                      decoration: InputDecoration(
                        hintText: 'Search tracks in playlist…',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
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

              // Loading / Error / Track list
              if (_isLoading)
                const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_error != null)
                SliverFillRemaining(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 44,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 14),
                          FilledButton.tonal(
                            onPressed: _loadTracks,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (displayedTracks.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _searchQuery.isNotEmpty
                            ? 'No tracks matching "$_searchQuery" in this playlist.'
                            : 'No tracks found in this playlist.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.only(bottom: 110),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final track = displayedTracks[index];
                        return TrackTile(
                          item: track,
                          playback: widget.playback,
                          storage: widget.storage,
                          downloadService: widget.downloadService,
                        );
                      },
                      childCount: displayedTracks.length,
                    ),
                  ),
                ),
            ],
          ),

          // Floating Bottom Mini Player
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: PlaybackBar(
              controller: widget.playback,
              storageService: widget.storage,
              downloadService: widget.downloadService,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.playlist_play,
        size: 40,
        color: theme.colorScheme.primary,
      ),
    );
  }
}
