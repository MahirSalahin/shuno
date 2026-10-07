import 'package:flutter/material.dart';

import '../models/youtube_search_item.dart';
import '../screens/audiobook_reader_screen.dart';
import '../services/book_service.dart';
import '../services/download_service.dart';
import '../services/playback_controller.dart';
import '../services/storage_service.dart';
import 'add_to_playlist_dialog.dart';
import 'animated_equalizer.dart';
import 'attach_pdf_sheet.dart';
import 'confirm_dialog.dart';

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.item,
    required this.playback,
    required this.storage,
    this.downloadService,
    this.bookService,
    this.onTap,
    this.leadingWidget,
    this.trailingAction,
    this.trailingActionTooltip,
    this.onTrailingAction,
    this.showMoreOptions = true,
  });

  final YoutubeSearchItem item;
  final PlaybackController playback;
  final StorageService storage;
  final DownloadService? downloadService;
  final BookService? bookService;
  final VoidCallback? onTap;
  final Widget? leadingWidget;
  final IconData? trailingAction;
  final String? trailingActionTooltip;
  final VoidCallback? onTrailingAction;
  final bool showMoreOptions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = playback.selected?.id == item.id;
    final isFav = storage.isFavorite(item.id);
    final isDownloaded = storage.isDownloaded(item.id);
    final downloadItem = storage.getDownload(item.id);
    final isDownloading = downloadService?.isDownloading(item.id) ?? false;
    final duration = item.durationLabel;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2.5),
      decoration: BoxDecoration(
        color: isSelected
            ? theme.colorScheme.primary.withAlpha(26)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected
              ? theme.colorScheme.primary.withAlpha(160)
              : theme.colorScheme.outlineVariant.withAlpha(60),
          width: isSelected ? 1.2 : 0.8,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ?? (playback.isLoading ? null : () => playback.playItem(item)),
        child: Padding(
          padding: const EdgeInsets.only(left: 10, right: 6, top: 8, bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (leadingWidget != null) ...[
                    leadingWidget!,
                    const SizedBox(width: 8),
                  ],
                  // Active left accent indicator bar if playing
                  if (isSelected)
                    Container(
                      width: 3,
                      height: 40,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withAlpha(140),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  // Square Artwork + Equalizer (Spotify aesthetic)
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: item.thumbnailUrl.isNotEmpty
                            ? Image.network(
                                item.thumbnailUrl,
                                width: 50,
                                height: 50,
                                cacheWidth: 150,
                                cacheHeight: 150,
                                fit: BoxFit.cover,
                                excludeFromSemantics: true,
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(
                                  width: 50,
                                  height: 50,
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  child: const Icon(Icons.image_not_supported_outlined, size: 22),
                                ),
                              )
                            : Container(
                                width: 50,
                                height: 50,
                                color: theme.colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.music_note, size: 24),
                              ),
                      ),
                      if (isSelected)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: playback.isPlaying
                                  ? RepaintBoundary(
                                      child: AnimatedEqualizer(
                                        color: theme.colorScheme.primary,
                                        isPlaying: true,
                                        size: 20,
                                      ),
                                    )
                                  : Icon(
                                      Icons.pause_circle_outline,
                                      color: theme.colorScheme.primary,
                                      size: 24,
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 10),

                  // Track Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: isSelected ? theme.colorScheme.primary : null,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.normal,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.channelName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (isDownloaded) ...[
                              Icon(
                                Icons.offline_pin,
                                size: 14,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                            ],
                            if (isDownloading) ...[
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${((downloadService?.getProgress(item.id) ?? 0) * 100).toInt()}%',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            if (duration != null)
                              Text(
                                duration,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            if (BookService.isPdfFileValid(storage.getTrackPdfPath(item.id))) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.auto_stories,
                                size: 13,
                                color: theme.colorScheme.primary,
                              ),
                            ],
                            if (downloadItem != null && downloadItem.hasPlaybackProgress) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primaryContainer.withAlpha(128),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Left at ${downloadItem.formattedLastPosition}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Favorite Button (Ultra-compact)
                  IconButton(
                    iconSize: 18,
                    visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                    constraints: const BoxConstraints.tightFor(width: 28, height: 34),
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      isFav ? Icons.favorite : Icons.favorite_border,
                      size: 18,
                      color: isFav ? Colors.redAccent : null,
                    ),
                    tooltip: isFav ? 'Remove from favorites' : 'Add to favorites',
                    onPressed: () => storage.toggleFavorite(item),
                  ),

                  // 1-Tap Download Button (Ultra-compact)
                  if (downloadService != null && !isDownloaded && !isDownloading)
                    IconButton(
                      iconSize: 18,
                      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                      constraints: const BoxConstraints.tightFor(width: 28, height: 34),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.download_outlined, size: 18),
                      tooltip: 'Download for offline',
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Downloading "${item.title}"...'),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                        downloadService!.downloadTrack(item);
                      },
                    ),

                  // Trailing Action (e.g. Delete or Reorder handle)
                  if (trailingAction != null && onTrailingAction != null)
                    IconButton(
                      iconSize: 18,
                      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                      constraints: const BoxConstraints.tightFor(width: 28, height: 34),
                      padding: EdgeInsets.zero,
                      icon: Icon(trailingAction, size: 18),
                      tooltip: trailingActionTooltip,
                      onPressed: onTrailingAction,
                    ),

                  // Popup Menu (Ultra-compact)
                  if (showMoreOptions)
                    PopupMenuButton<String>(
                      tooltip: 'More options',
                      padding: EdgeInsets.zero,
                      child: SizedBox(
                        width: 28,
                        height: 34,
                        child: Center(
                          child: Icon(
                            Icons.more_vert,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      onSelected: (value) async {
                        switch (value) {
                          case 'play':
                            playback.playItem(item);
                            break;
                          case 'play_from_start':
                            playback.playItem(item, initialPosition: Duration.zero);
                            break;
                          case 'play_next':
                            playback.playNext(item);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Playing next')),
                            );
                            break;
                          case 'add_queue':
                            playback.addToQueue(item);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Added to queue')),
                            );
                            break;
                          case 'add_playlist':
                            AddToPlaylistDialog.show(
                              context,
                              item: item,
                              storageService: storage,
                            );
                            break;
                          case 'favorite':
                            storage.toggleFavorite(item);
                            break;
                          case 'download':
                            if (downloadService != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Downloading "${item.title}"...'),
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                              downloadService!.downloadTrack(item);
                            }
                            break;
                          case 'delete_download':
                            if (downloadService != null) {
                              final confirm = await showConfirmDialog(
                                context,
                                title: 'Delete Download?',
                                message:
                                    'Remove downloaded audio for "${item.title}" from your device?',
                                confirmLabel: 'Delete',
                              );
                              if (confirm) {
                                await downloadService!.deleteDownload(item.id);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Download deleted')),
                                  );
                                }
                              }
                            }
                            break;
                          case 'read_pdf':
                            final existingPdf = storage.getTrackPdfPath(item.id);
                            if (existingPdf != null && BookService.isPdfFileValid(existingPdf)) {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AudiobookReaderScreen(
                                    item: item,
                                    pdfPath: existingPdf,
                                    playback: playback,
                                    storage: storage,
                                    downloadService: downloadService,
                                    bookService: bookService,
                                  ),
                                ),
                              );
                            } else {
                              if (existingPdf != null) {
                                await storage.removeTrackPdf(item.id);
                              }
                              if (!context.mounted) return;
                              final pickedPdf = await AttachPdfSheet.show(
                                context,
                                item: item,
                                storage: storage,
                                bookService: bookService,
                              );
                              if (pickedPdf != null && context.mounted && BookService.isPdfFileValid(pickedPdf)) {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => AudiobookReaderScreen(
                                      item: item,
                                      pdfPath: pickedPdf,
                                      playback: playback,
                                      storage: storage,
                                      downloadService: downloadService,
                                      bookService: bookService,
                                    ),
                                  ),
                                );
                              }
                            }
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'read_pdf',
                          child: ListTile(
                            leading: Icon(
                              BookService.isPdfFileValid(storage.getTrackPdfPath(item.id))
                                  ? Icons.auto_stories
                                  : Icons.auto_stories_outlined,
                              color: BookService.isPdfFileValid(storage.getTrackPdfPath(item.id))
                                  ? theme.colorScheme.primary
                                  : null,
                            ),
                            title: Text(
                              BookService.isPdfFileValid(storage.getTrackPdfPath(item.id))
                                  ? 'Read along (Book attached)'
                                  : 'Read along (PDF)',
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'play',
                          child: ListTile(
                            leading: Icon(Icons.play_arrow),
                            title: Text('Play'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        if (downloadItem != null && downloadItem.hasPlaybackProgress)
                          const PopupMenuItem(
                            value: 'play_from_start',
                            child: ListTile(
                              leading: Icon(Icons.replay),
                              title: Text('Play from Start'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'play_next',
                          child: ListTile(
                            leading: Icon(Icons.playlist_play),
                            title: Text('Play Next'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'add_queue',
                          child: ListTile(
                            leading: Icon(Icons.queue_music),
                            title: Text('Add to Queue'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'add_playlist',
                          child: ListTile(
                            leading: Icon(Icons.playlist_add),
                            title: Text('Add to Playlist'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'favorite',
                          child: ListTile(
                            leading: Icon(
                              isFav ? Icons.favorite : Icons.favorite_border,
                              color: isFav ? Colors.redAccent : null,
                            ),
                            title: Text(isFav ? 'Remove from favorites' : 'Add to favorites'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        if (isDownloaded)
                          const PopupMenuItem(
                            value: 'delete_download',
                            child: ListTile(
                              leading: Icon(Icons.delete_outline),
                              title: Text('Remove Download'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          )
                        else
                          const PopupMenuItem(
                            value: 'download',
                            child: ListTile(
                              leading: Icon(Icons.download),
                              title: Text('Download for Offline'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                      ],
                    ),
                ],
              ),

              // Offline Playback Progress Bar on tile
              if (downloadItem != null && downloadItem.hasPlaybackProgress && !isSelected) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: downloadItem.playbackProgress,
                    minHeight: 3,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.colorScheme.primary.withAlpha(200),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

