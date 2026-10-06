import 'package:flutter/material.dart';

import '../models/youtube_playlist_item.dart';

class ChannelPlaylistTile extends StatelessWidget {
  const ChannelPlaylistTile({
    super.key,
    required this.playlist,
    required this.onTap,
    this.showAuthor = false,
  });

  final YoutubePlaylistItem playlist;
  final VoidCallback onTap;
  final bool showAuthor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withAlpha(50),
          ),
        ),
        child: Row(
          children: [
            // Playlist cover
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 58,
                height: 58,
                child: playlist.thumbnailUrl.isNotEmpty
                    ? Image.network(
                        playlist.thumbnailUrl,
                        cacheWidth: 174,
                        cacheHeight: 174,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildPlaceholder(theme),
                      )
                    : _buildPlaceholder(theme),
              ),
            ),
            const SizedBox(width: 14),

            // Title & track count
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    playlist.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.queue_music,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          showAuthor &&
                                  playlist.author != null &&
                                  playlist.author!.trim().isNotEmpty
                              ? '${playlist.author!.trim()} • ${playlist.videoCountLabel}'
                              : playlist.videoCountLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Arrow forward / chevron
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.playlist_play,
        size: 28,
        color: theme.colorScheme.primary,
      ),
    );
  }
}

typedef YoutubePlaylistTile = ChannelPlaylistTile;

