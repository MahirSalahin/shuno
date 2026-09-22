import 'dart:async';

import 'package:flutter/material.dart';

import '../models/youtube_search_item.dart';
import '../services/playback_controller.dart';
import '../services/youtube_service.dart';
import '../widgets/playback_bar.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.youtubeService, this.playbackController});

  final YoutubeService? youtubeService;
  final PlaybackController? playbackController;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with WidgetsBindingObserver {
  final _queryController = TextEditingController();
  late final _youtubeService = widget.youtubeService ?? YoutubeService();
  late final _playback =
      widget.playbackController ??
      PlaybackController(youtubeService: _youtubeService);
  List<YoutubeSearchItem> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _inputError;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playback.addListener(_updatePlayback);
  }

  void _updatePlayback() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // This milestone deliberately supports foreground playback only.
    unawaited(_playback.setForeground(state == AppLifecycleState.resumed));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playback.removeListener(_updatePlayback);
    if (widget.playbackController == null) _playback.dispose();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_isLoading) return;

    final query = _queryController.text.trim();
    if (query.isEmpty) {
      setState(() => _inputError = 'Enter something to search for.');
      return;
    }

    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
      appBar: AppBar(title: const Text('Shuno')),
      bottomNavigationBar: _playback.selected == null
          ? null
          : SafeArea(top: false, child: PlaybackBar(controller: _playback)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _queryController,
                    enabled: !_isLoading,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    onChanged: (_) {
                      if (_inputError != null) {
                        setState(() => _inputError = null);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Search YouTube',
                      hintText: 'Song, artist, or video',
                      prefixIcon: const Icon(Icons.search),
                      errorText: _inputError,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _search,
                    icon: const Icon(Icons.search),
                    label: const Text('Search'),
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

    final message =
        _searchError ??
        (!_hasSearched
            ? 'Search YouTube to get started.'
            : _results.isEmpty
            ? 'No videos found. Try a different search.'
            : null);
    if (message != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _results.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _results[index];
        final duration = item.durationLabel;
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _playback.isLoading ? null : () => _playback.playItem(item),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      item.thumbnailUrl,
                      width: 104,
                      height: 64,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox(
                            width: 104,
                            height: 64,
                            child: Icon(Icons.image_not_supported_outlined),
                          ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.channelName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (duration != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            duration,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
