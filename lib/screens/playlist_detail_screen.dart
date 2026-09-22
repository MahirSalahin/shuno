import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../services/download_service.dart';
import '../services/playback_controller.dart';
import '../services/storage_service.dart';
import '../widgets/track_tile.dart';

class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
    required this.playback,
    required this.storage,
    this.downloadService,
  });

  final Playlist playlist;
  final PlaybackController playback;
  final StorageService storage;
  final DownloadService? downloadService;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  void _rename() {
    final controller = TextEditingController(text: widget.playlist.title);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Playlist Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                await widget.storage.renamePlaylist(
                  widget.playlist.id,
                  newTitle,
                );
                setState(() {});
                if (context.mounted) Navigator.of(context).pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _delete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Playlist'),
        content: Text('Are you sure you want to delete "${widget.playlist.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              await widget.storage.deletePlaylist(widget.playlist.id);
              if (context.mounted) {
                Navigator.of(context).pop(); // dismiss dialog
                Navigator.of(context).pop(); // pop screen
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = widget.playlist.items;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlist.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename',
            onPressed: _rename,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete Playlist',
            onPressed: _delete,
          ),
        ],
      ),
      body: Column(
        children: [
          // Header info
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.playlist_play,
                    size: 44,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.playlist.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${items.length} songs',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Action buttons: Play All / Shuffle
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play All'),
                      onPressed: () => widget.playback.playQueue(items),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.shuffle),
                      label: const Text('Shuffle'),
                      onPressed: () {
                        final shuffled = List.of(items)..shuffle();
                        widget.playback.playQueue(shuffled);
                      },
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          // List of tracks
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.music_off,
                          size: 48,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No songs in this playlist',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Add songs from search results or your favorites',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return TrackTile(
                        item: item,
                        playback: widget.playback,
                        storage: widget.storage,
                        downloadService: widget.downloadService,
                        trailingAction: Icons.remove_circle_outline,
                        trailingActionTooltip: 'Remove from playlist',
                        onTrailingAction: () async {
                          await widget.storage.removeTrackFromPlaylist(
                            widget.playlist.id,
                            item.id,
                          );
                          setState(() {});
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
