import 'dart:async';

import 'package:flutter/material.dart';

import '../models/youtube_search_item.dart';
import '../services/download_service.dart';
import '../services/playback_controller.dart';
import '../services/storage_service.dart';
import '../services/youtube_service.dart';
import '../widgets/playback_bar.dart';
import '../widgets/track_tile.dart';

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
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _inputError;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _playback.addListener(_update);
    _storage.addListener(_update);
    _downloadService.addListener(_update);
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _playback.removeListener(_update);
    _storage.removeListener(_update);
    _downloadService.removeListener(_update);
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
    });

    try {
      final results = await _youtubeService.search(query);
      if (!mounted) return;
      setState(() => _results = results);
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
            if (_results.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withAlpha(120),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_results.length} tracks',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Play All'),
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      onPressed: () => _playback.playQueue(_results),
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
            // Compact prompt card (Space-wise & aesthetic)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant.withAlpha(80),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Search YouTube to get started.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

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
                    onPressed: () => _storage.clearRecentSearches(),
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
            ],
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      return const Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Text('No videos found. Try a different search.', textAlign: TextAlign.center),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final item = _results[index];
        return TrackTile(
          item: item,
          playback: _playback,
          storage: _storage,
          downloadService: _downloadService,
        );
      },
    );
  }
}
