import 'dart:async';

import 'package:flutter/material.dart';

import '../models/youtube_channel_item.dart';
import '../models/youtube_playlist_item.dart';
import '../models/youtube_search_item.dart';
import '../services/download_service.dart';
import '../services/playback_controller.dart';
import '../services/storage_service.dart';
import '../services/youtube_service.dart';
import '../widgets/channel_playlist_tile.dart';
import '../widgets/channel_tile.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/playback_bar.dart';
import '../widgets/track_tile.dart';
import 'channel_detail_screen.dart';
import 'youtube_playlist_detail_screen.dart';

enum SearchCategory { tracks, playlists, channels }

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    this.youtubeService,
    this.playbackController,
    this.storageService,
    this.downloadService,
    this.showBottomPlayer = true,
  });

  final YoutubeService? youtubeService;
  final PlaybackController? playbackController;
  final StorageService? storageService;
  final DownloadService? downloadService;
  final bool showBottomPlayer;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _queryController = TextEditingController();
  late final _youtubeService = widget.youtubeService ?? YoutubeService();
  late final _storage = widget.storageService ?? StorageService();
  late final _playback =
      widget.playbackController ??
      PlaybackController(
        youtubeService: _youtubeService,
        storageService: _storage,
      );
  late final _downloadService =
      widget.downloadService ?? DownloadService(storageService: _storage);

  List<YoutubeSearchItem> _results = [];
  List<YoutubePlaylistItem> _playlistResults = [];
  List<YoutubeChannelItem> _channelResults = [];
  SearchCategory _selectedCategory = SearchCategory.tracks;
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _inputError;
  String? _searchError;

  String? _lastPlayingId;
  bool _lastIsPlaying = false;
  bool _lastIsBuffering = false;
  bool _lastIsLoading = false;

  @override
  void initState() {
    super.initState();
    _lastPlayingId = _playback.selected?.id;
    _lastIsPlaying = _playback.isPlaying;
    _lastIsBuffering = _playback.isBuffering;
    _lastIsLoading = _playback.isLoading;
    _playback.addListener(_onPlaybackUpdate);
    _storage.addListener(_onServiceUpdate);
    _downloadService.addListener(_onServiceUpdate);
  }

  void _onPlaybackUpdate() {
    final curId = _playback.selected?.id;
    final curPlaying = _playback.isPlaying;
    final curBuffering = _playback.isBuffering;
    final curLoading = _playback.isLoading;
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
    _playback.removeListener(_onPlaybackUpdate);
    _storage.removeListener(_onServiceUpdate);
    _downloadService.removeListener(_onServiceUpdate);
    if (widget.playbackController == null) _playback.dispose();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search([String? customQuery]) async {
    if (_isLoading) return;

    final query = (customQuery ?? _queryController.text).trim();
    if (customQuery != null) {
      _queryController.text = customQuery;
    }

    if (query.isEmpty) {
      setState(() => _inputError = 'Enter something to search for.');
      return;
    }

    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    unawaited(_storage.addRecentSearch(query));
    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _inputError = null;
      _searchError = null;
      _results = [];
      _playlistResults = [];
      _channelResults = [];
    });

    try {
      final resultsFuture = _youtubeService.search(query);
      final channelsFuture = _youtubeService
          .searchChannels(query)
          .catchError((_) => <YoutubeChannelItem>[]);
      final playlistsFuture = _youtubeService
          .searchPlaylists(query)
          .catchError((_) => <YoutubePlaylistItem>[]);

      final results = await resultsFuture;
      final channels = await channelsFuture;
      final playlists = await playlistsFuture;

      if (!mounted) return;
      setState(() {
        _results = results;
        _channelResults = channels;
        _playlistResults = playlists;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _searchError = 'Search timed out. Check your connection and try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searchError =
            'Could not search YouTube. Check your connection and try again.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/shuno.png',
                height: 26,
                width: 26,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Shuno'),
          ],
        ),
      ),
      bottomNavigationBar:
          widget.showBottomPlayer && _playback.selected != null
          ? SafeArea(
              top: false,
              child: PlaybackBar(
                controller: _playback,
                storageService: _storage,
                downloadService: _downloadService,
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _queryController,
                      enabled: !_isLoading,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      onChanged: (_) {
                        if (_inputError != null) {
                          setState(() => _inputError = null);
                        } else {
                          setState(() {});
                        }
                      },
                      decoration: InputDecoration(
                        hintText: 'Search songs, artists, podcasts…',
                        prefixIcon: const Icon(Icons.search, size: 22),
                        suffixIcon: _queryController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _queryController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                        errorText: _inputError,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                    onPressed: _isLoading ? null : () => _search(),
                    icon: const Icon(Icons.search, size: 20),
                    label: const Text('Search'),
                  ),
                ],
              ),
            ),
            if (_hasSearched &&
                !_isLoading &&
                (_results.isNotEmpty ||
                    _playlistResults.isNotEmpty ||
                    _channelResults.isNotEmpty))
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Tracks'),
                      selected: _selectedCategory == SearchCategory.tracks,
                      showCheckmark: false,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedCategory = SearchCategory.tracks);
                        }
                      },
                      avatar: const Icon(Icons.graphic_eq, size: 16),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Playlists'),
                      selected: _selectedCategory == SearchCategory.playlists,
                      showCheckmark: false,
                      onSelected: (selected) {
                        if (selected) {
                          setState(
                            () => _selectedCategory = SearchCategory.playlists,
                          );
                        }
                      },
                      avatar: const Icon(Icons.playlist_play, size: 16),
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Channels'),
                      selected: _selectedCategory == SearchCategory.channels,
                      showCheckmark: false,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedCategory = SearchCategory.channels);
                        }
                      },
                      avatar: const Icon(Icons.person, size: 16),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            Expanded(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Searching YouTube'),
      );
    }

    if (_searchError != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Text(_searchError!, textAlign: TextAlign.center),
        ),
      );
    }

    if (!_hasSearched) {
      final recents = _storage.recentSearches;
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (recents.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'RECENT SEARCHES',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          letterSpacing: 1.2,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final confirm = await showConfirmDialog(
                        context,
                        title: 'Clear Recent Searches?',
                        message:
                            'Are you sure you want to clear all recent search queries?',
                        confirmLabel: 'Clear',
                      );
                      if (confirm) {
                        _storage.clearRecentSearches();
                      }
                    },
                    child: const Text('Clear All'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: recents.map((query) {
                  return InputChip(
                    avatar: const Icon(Icons.history, size: 16),
                    label: Text(query),
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withAlpha(100),
                      ),
                    ),
                    onPressed: () => _search(query),
                    onDeleted: () => _storage.removeRecentSearch(query),
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),
            ],
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.headphones_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Search YouTube to get started.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_results.isEmpty &&
        _playlistResults.isEmpty &&
        _channelResults.isEmpty) {
      return const Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Text(
            'No videos found. Try a different search.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_selectedCategory == SearchCategory.tracks) {
      if (_results.isEmpty) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No tracks found for this search. Try the Playlists or Channels tab.',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: _results.length,
        itemBuilder: (context, index) {
          final item = _results[index];
          return TrackTile(
            key: ValueKey(item.id),
            item: item,
            playback: _playback,
            storage: _storage,
            downloadService: _downloadService,
          );
        },
      );
    } else if (_selectedCategory == SearchCategory.playlists) {
      if (_playlistResults.isEmpty) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No playlists found for this search. Try the Tracks or Channels tab.',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: _playlistResults.length,
        itemBuilder: (context, index) {
          final playlist = _playlistResults[index];
          return ChannelPlaylistTile(
            key: ValueKey(playlist.id),
            playlist: playlist,
            showAuthor: true,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => YoutubePlaylistDetailScreen(
                    playlist: playlist,
                    youtubeService: _youtubeService,
                    playback: _playback,
                    storage: _storage,
                    downloadService: _downloadService,
                  ),
                ),
              );
            },
          );
        },
      );
    } else {
      if (_channelResults.isEmpty) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No channels found for this search. Try the Tracks or Playlists tab.',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: _channelResults.length,
        itemBuilder: (context, index) {
          final channel = _channelResults[index];
          return ChannelTile(
            key: ValueKey(channel.id),
            channel: channel,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ChannelDetailScreen(
                    channel: channel,
                    youtubeService: _youtubeService,
                    playback: _playback,
                    storage: _storage,
                    downloadService: _downloadService,
                  ),
                ),
              );
            },
          );
        },
      );
    }
  }
}
