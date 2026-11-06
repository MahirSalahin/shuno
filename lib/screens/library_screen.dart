import 'package:flutter/material.dart';

import '../services/download_service.dart';
import '../services/playback_controller.dart';
import '../services/storage_service.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/track_tile.dart';
import 'playlist_detail_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.playback,
    required this.storage,
    this.downloadService,
  });

  final PlaybackController playback;
  final StorageService storage;
  final DownloadService? downloadService;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 4,
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    widget.storage.addListener(_onServiceUpdate);
    widget.downloadService?.addListener(_onServiceUpdate);
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storage != widget.storage) {
      oldWidget.storage.removeListener(_onServiceUpdate);
      widget.storage.addListener(_onServiceUpdate);
    }
    if (oldWidget.downloadService != widget.downloadService) {
      oldWidget.downloadService?.removeListener(_onServiceUpdate);
      widget.downloadService?.addListener(_onServiceUpdate);
    }
  }

  @override
  void dispose() {
    widget.storage.removeListener(_onServiceUpdate);
    widget.downloadService?.removeListener(_onServiceUpdate);
    _tabController.dispose();
    super.dispose();
  }

  void _createNewPlaylist() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Playlist Name',
            hintText: 'e.g. Favorites 2026',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final title = controller.text.trim();
              if (title.isNotEmpty) {
                await widget.storage.createPlaylist(title);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeCount = widget.downloadService?.activeTasks.length ?? 0;
    final downloadCount = widget.storage.downloads.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(
              icon: const Icon(Icons.playlist_play),
              text: 'Playlists (${widget.storage.playlists.length})',
            ),
            Tab(
              icon: const Icon(Icons.favorite),
              text: 'Favorites (${widget.storage.favorites.length})',
            ),
            Tab(
              icon: const Icon(Icons.history),
              text: 'History (${widget.storage.history.length})',
            ),
            Tab(
              icon: Icon(
                activeCount > 0 ? Icons.downloading : Icons.download_done,
                color: activeCount > 0 ? theme.colorScheme.primary : null,
              ),
              text: activeCount > 0
                  ? 'Downloads ($downloadCount • $activeCount active)'
                  : 'Downloads ($downloadCount)',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPlaylistsTab(),
          _buildFavoritesTab(),
          _buildHistoryTab(),
          _buildDownloadsTab(),
        ],
      ),
    );
  }

  Widget _buildPlaylistsTab() {
    final playlists = widget.storage.playlists;
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'YOUR PLAYLISTS',
                style: theme.textTheme.labelMedium?.copyWith(
                  letterSpacing: 1.2,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New'),
                onPressed: _createNewPlaylist,
              ),
            ],
          ),
        ),
        Expanded(
          child: playlists.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.playlist_play,
                        size: 56,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No playlists yet',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap "New" to create your first playlist',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 100),
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final pl = playlists[index];
                    return Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withAlpha(60),
                          width: 0.8,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                theme.colorScheme.primary.withAlpha(60),
                                theme.colorScheme.primary.withAlpha(20),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.playlist_play,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      title: Text(
                        pl.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${pl.items.length} tracks',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.play_circle_fill, size: 28),
                            color: theme.colorScheme.primary,
                            tooltip: 'Play playlist',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                            padding: const EdgeInsets.all(4),
                            onPressed: pl.items.isNotEmpty
                                ? () => widget.playback.playQueue(pl.items)
                                : null,
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            tooltip: 'Delete playlist',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                            padding: const EdgeInsets.all(4),
                            onPressed: () async {
                              final confirm = await showConfirmDialog(
                                context,
                                title: 'Delete Playlist',
                                message: 'Are you sure you want to delete "${pl.title}"?',
                                confirmLabel: 'Delete',
                              );
                              if (confirm) {
                                widget.storage.deletePlaylist(pl.id);
                              }
                            },
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PlaylistDetailScreen(
                              playlist: pl,
                              storage: widget.storage,
                              playback: widget.playback,
                              downloadService: widget.downloadService,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
                ),
        ),
      ],
    );
  }

  Widget _buildFavoritesTab() {
    final favorites = widget.storage.favorites;
    final theme = Theme.of(context);

    if (favorites.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.favorite_border,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'No favorites yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Heart tracks you love to see them here',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${favorites.length} songs'),
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Play All'),
                onPressed: () => widget.playback.playQueue(favorites),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 100),
            itemCount: favorites.length,
            itemBuilder: (context, index) {
              return TrackTile(
                item: favorites[index],
                playback: widget.playback,
                storage: widget.storage,
                downloadService: widget.downloadService,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab() {
    final history = widget.storage.history;
    final theme = Theme.of(context);

    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'No listening history',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Tracks you play will be remembered here',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${history.length} recently played'),
              TextButton.icon(
                icon: const Icon(Icons.delete_sweep, size: 18),
                label: const Text('Clear'),
                onPressed: () async {
                  final confirm = await showConfirmDialog(
                    context,
                    title: 'Clear History?',
                    message: 'Are you sure you want to clear your listening history?',
                    confirmLabel: 'Clear',
                  );
                  if (confirm) {
                    widget.storage.clearHistory();
                  }
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 100),
            itemCount: history.length,
            itemBuilder: (context, index) {
              return TrackTile(
                item: history[index],
                playback: widget.playback,
                storage: widget.storage,
                downloadService: widget.downloadService,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadsTab() {
    final downloads = widget.storage.downloads;
    final activeTasks = widget.downloadService?.activeTasks ?? [];
    final failedTasks = widget.downloadService?.failedTasks ?? [];
    final theme = Theme.of(context);

    if (downloads.isEmpty && activeTasks.isEmpty && failedTasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.download_for_offline,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'No downloaded songs',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Download tracks to listen offline without internet',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final totalBytes = downloads.fold<int>(0, (sum, d) => sum + d.fileSize);
    final totalSizeMB = (totalBytes / (1024 * 1024)).toStringAsFixed(1);

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        // 1. ACTIVE DOWNLOADS SECTION
        if (activeTasks.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'DOWNLOADING (${activeTasks.length})',
                  style: theme.textTheme.labelMedium?.copyWith(
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          for (final task in activeTasks)
            _buildActiveTaskTile(task, theme),
          const Divider(height: 24),
        ],

        // 2. FAILED DOWNLOADS SECTION
        if (failedTasks.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Text(
              'FAILED DOWNLOADS (${failedTasks.length})',
              style: theme.textTheme.labelMedium?.copyWith(
                letterSpacing: 1.2,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.error,
              ),
            ),
          ),
          for (final task in failedTasks)
            _buildFailedTaskTile(task, theme),
          const Divider(height: 24),
        ],

        // 3. COMPLETED DOWNLOADS SECTION
        if (downloads.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${downloads.length} songs ($totalSizeMB MB)',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Play Offline'),
                  onPressed: () {
                    final items = downloads.map((d) => d.item).toList();
                    widget.playback.playQueue(items);
                  },
                ),
              ],
            ),
          ),
          for (final d in downloads)
            TrackTile(
              item: d.item,
              playback: widget.playback,
              storage: widget.storage,
              downloadService: widget.downloadService,
              trailingAction: Icons.delete_outline,
              trailingActionTooltip: 'Delete downloaded file',
              onTrailingAction: () async {
                final confirm = await showConfirmDialog(
                  context,
                  title: 'Delete Download?',
                  message:
                      'Remove downloaded audio for "${d.item.title}" from your device?',
                  confirmLabel: 'Delete',
                );
                if (confirm) {
                  widget.downloadService?.deleteDownload(d.item.id);
                }
              },
            ),
        ] else if (activeTasks.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Center(
              child: Text(
                'Downloaded tracks will appear here once ready for offline playback.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActiveTaskTile(ActiveDownloadTask task, ThemeData theme) {
    final isConnecting = task.status == DownloadStatus.connecting;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: task.item.thumbnailUrl.isNotEmpty
                      ? Image.network(
                          task.item.thumbnailUrl,
                          width: 48,
                          height: 48,
                          cacheWidth: 144,
                          cacheHeight: 144,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            width: 48,
                            height: 48,
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.music_note),
                          ),
                        )
                      : Container(
                          width: 48,
                          height: 48,
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.music_note),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        task.item.channelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Cancel download',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    widget.downloadService?.cancelDownload(task.item.id);
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  task.statusText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (!isConnecting && task.totalBytes > 0)
                  Text(
                    '${(task.progress * 100).toInt()}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: isConnecting ? null : task.progress,
                minHeight: 5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailedTaskTile(ActiveDownloadTask task, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      color: theme.colorScheme.errorContainer.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.error.withValues(alpha: 0.5),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Icon(
          Icons.error_outline,
          color: theme.colorScheme.error,
          size: 32,
        ),
        title: Text(
          task.item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            task.errorMessage ?? 'Download failed',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: 'Retry download',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                widget.downloadService?.downloadTrack(task.item);
              },
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: 'Dismiss',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                widget.downloadService?.dismissFailedTask(task.item.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}