import 'package:flutter/material.dart';

import '../models/youtube_search_item.dart';
import '../services/storage_service.dart';

class AddToPlaylistDialog extends StatefulWidget {
  const AddToPlaylistDialog({
    super.key,
    required this.item,
    required this.storageService,
  });

  final YoutubeSearchItem item;
  final StorageService storageService;

  static Future<void> show(
    BuildContext context, {
    required YoutubeSearchItem item,
    required StorageService storageService,
  }) {
    return showDialog(
      context: context,
      builder: (context) =>
          AddToPlaylistDialog(item: item, storageService: storageService),
    );
  }

  @override
  State<AddToPlaylistDialog> createState() => _AddToPlaylistDialogState();
}

class _AddToPlaylistDialogState extends State<AddToPlaylistDialog> {
  final _newPlaylistController = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _newPlaylistController.dispose();
    super.dispose();
  }

  Future<void> _createNewPlaylist() async {
    final title = _newPlaylistController.text.trim();
    if (title.isEmpty) return;

    final playlist = await widget.storageService.createPlaylist(title, [
      widget.item,
    ]);
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created "${playlist.title}" and added song')),
      );
    }
  }

  Future<void> _addToPlaylist(String playlistId, String title) async {
    final added = await widget.storageService.addTrackToPlaylist(
      playlistId,
      widget.item,
    );
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            added
                ? 'Added to "$title"'
                : 'Song already in "$title"',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlists = widget.storageService.playlists;

    return AlertDialog(
      title: const Text('Add to Playlist'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isCreating) ...[
              TextField(
                controller: _newPlaylistController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Playlist Name',
                  hintText: 'e.g. Chill Beats',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _createNewPlaylist(),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _isCreating = false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _createNewPlaylist,
                    child: const Text('Create & Add'),
                  ),
                ],
              ),
            ] else ...[
              FilledButton.tonalIcon(
                onPressed: () => setState(() => _isCreating = true),
                icon: const Icon(Icons.add),
                label: const Text('New Playlist'),
              ),
              const SizedBox(height: 12),
              if (playlists.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('No playlists yet. Create one!'),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final p = playlists[index];
                      final alreadyIn = p.items.any(
                        (e) => e.id == widget.item.id,
                      );
                      return ListTile(
                        leading: const Icon(Icons.playlist_play),
                        title: Text(p.title),
                        subtitle: Text('${p.items.length} songs'),
                        trailing: alreadyIn
                            ? const Icon(Icons.check, color: Colors.green)
                            : null,
                        onTap: () => _addToPlaylist(p.id, p.title),
                      );
                    },
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isCreating)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
      ],
    );
  }
}
