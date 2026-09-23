import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../models/youtube_search_item.dart';
import '../services/storage_service.dart';

class AddSongsToPlaylistSheet extends StatefulWidget {
  const AddSongsToPlaylistSheet({
    super.key,
    required this.playlist,
    required this.storage,
  });

  final Playlist playlist;
  final StorageService storage;

  static Future<void> show(
    BuildContext context, {
    required Playlist playlist,
    required StorageService storage,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddSongsToPlaylistSheet(
        playlist: playlist,
        storage: storage,
      ),
    );
  }

  @override
  State<AddSongsToPlaylistSheet> createState() =>
      _AddSongsToPlaylistSheetState();
}

class _AddSongsToPlaylistSheetState extends State<AddSongsToPlaylistSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final Set<String> _selectedTrackIds = {};
  final Map<String, YoutubeSearchItem> _selectedTracks = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _toggleTrack(YoutubeSearchItem track) {
    setState(() {
      if (_selectedTrackIds.contains(track.id)) {
        _selectedTrackIds.remove(track.id);
        _selectedTracks.remove(track.id);
      } else {
        _selectedTrackIds.add(track.id);
        _selectedTracks[track.id] = track;
      }
    });
  }

  void _selectAll(List<YoutubeSearchItem> tracks, Set<String> existingIds) {
    setState(() {
      for (final t in tracks) {
        if (!existingIds.contains(t.id)) {
          _selectedTrackIds.add(t.id);
          _selectedTracks[t.id] = t;
        }
      }
    });
  }

  Future<void> _save() async {
    if (_selectedTracks.isEmpty) return;
    final toAdd = _selectedTracks.values.toList();
    await widget.storage.addTracksToPlaylist(widget.playlist.id, toAdd);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added ${toAdd.length} songs to "${widget.playlist.title}"'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final existingTrackIds =
        widget.playlist.items.map((t) => t.id).toSet();

    // 1. Downloaded tracks
    final downloadedTracks = widget.storage.downloads
        .where((d) => d.isCompleted)
        .map((d) => d.toSearchItem())
        .toList();

    // 2. Favorites
    final favoriteTracks = widget.storage.favorites;

    // 3. History
    final historyTracks = widget.storage.history;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withAlpha(77),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add to "${widget.playlist.title}"',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Choose from your library to add in bulk',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Tab Bar
          TabBar(
            controller: _tabController,
            labelColor: colorScheme.primary,
            unselectedLabelColor: colorScheme.onSurfaceVariant,
            indicatorColor: colorScheme.primary,
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: [
              Tab(
                text: 'Downloaded (${downloadedTracks.length})',
                icon: const Icon(Icons.download_done, size: 20),
              ),
              Tab(
                text: 'Favorites (${favoriteTracks.length})',
                icon: const Icon(Icons.favorite, size: 20),
              ),
              Tab(
                text: 'History (${historyTracks.length})',
                icon: const Icon(Icons.history, size: 20),
              ),
            ],
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTrackList(
                  downloadedTracks,
                  existingTrackIds,
                  emptyMessage: 'No downloaded tracks yet.',
                  emptyIcon: Icons.download_outlined,
                ),
                _buildTrackList(
                  favoriteTracks,
                  existingTrackIds,
                  emptyMessage: 'No favorite tracks yet.',
                  emptyIcon: Icons.favorite_border,
                ),
                _buildTrackList(
                  historyTracks,
                  existingTrackIds,
                  emptyMessage: 'No listening history yet.',
                  emptyIcon: Icons.history,
                ),
              ],
            ),
          ),

          // Bottom Action Bar
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withAlpha(128),
                border: Border(
                  top: BorderSide(
                    color: colorScheme.outlineVariant.withAlpha(77),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '${_selectedTrackIds.length} selected',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _selectedTrackIds.isEmpty ? null : _save,
                    icon: const Icon(Icons.playlist_add),
                    label: Text(
                      _selectedTrackIds.isEmpty
                          ? 'Select Songs'
                          : 'Add (${_selectedTrackIds.length})',
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

  Widget _buildTrackList(
    List<YoutubeSearchItem> tracks,
    Set<String> existingIds, {
    required String emptyMessage,
    required IconData emptyIcon,
  }) {
    if (tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(emptyIcon, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(emptyMessage, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final availableTracks =
        tracks.where((t) => !existingIds.contains(t.id)).toList();

    return Column(
      children: [
        if (availableTracks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${availableTracks.length} available to add',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                TextButton(
                  onPressed: () => _selectAll(tracks, existingIds),
                  child: const Text('Select All'),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: tracks.length,
            itemBuilder: (context, index) {
              final track = tracks[index];
              final isAlreadyIn = existingIds.contains(track.id);
              final isSelected = _selectedTrackIds.contains(track.id);

              return CheckboxListTile(
                value: isAlreadyIn ? true : isSelected,
                enabled: !isAlreadyIn,
                onChanged: isAlreadyIn
                    ? null
                    : (_) => _toggleTrack(track),
                secondary: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: track.thumbnailUrl.isNotEmpty
                      ? Image.network(
                          track.thumbnailUrl,
                          width: 48,
                          height: 48,
                          cacheWidth: 144,
                          cacheHeight: 144,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            width: 48,
                            height: 48,
                            color: colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.music_note, size: 24),
                          ),
                        )
                      : Container(
                          width: 48,
                          height: 48,
                          color: colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.music_note, size: 24),
                        ),
                ),
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isAlreadyIn
                        ? colorScheme.onSurface.withAlpha(102)
                        : null,
                  ),
                ),
                subtitle: Row(
                  children: [
                    Expanded(
                      child: Text(
                        track.channelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isAlreadyIn
                              ? colorScheme.onSurfaceVariant.withAlpha(102)
                              : null,
                        ),
                      ),
                    ),
                    if (isAlreadyIn) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'In Playlist',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
