import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../screens/audiobook_reader_screen.dart';
import '../services/book_service.dart';
import '../services/download_service.dart';
import '../services/playback_controller.dart';
import '../services/storage_service.dart';
import 'add_to_playlist_dialog.dart';
import 'attach_pdf_sheet.dart';
import 'confirm_dialog.dart';

class FullPlayerSheet extends StatefulWidget {
  const FullPlayerSheet({
    super.key,
    required this.playback,
    required this.storage,
    this.downloadService,
    this.bookService,
    this.onOpenQueue,
  });

  final PlaybackController playback;
  final StorageService storage;
  final DownloadService? downloadService;
  final BookService? bookService;
  final VoidCallback? onOpenQueue;

  static void show(
    BuildContext context, {
    required PlaybackController playback,
    required StorageService storage,
    DownloadService? downloadService,
    BookService? bookService,
    VoidCallback? onOpenQueue,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => AnimatedBuilder(
        animation: Listenable.merge([
          playback,
          storage,
          ?downloadService,
        ]),
        builder: (context, _) => FullPlayerSheet(
          playback: playback,
          storage: storage,
          downloadService: downloadService,
          bookService: bookService,
          onOpenQueue: onOpenQueue,
        ),
      ),
    );
  }

  @override
  State<FullPlayerSheet> createState() => _FullPlayerSheetState();
}

class _FullPlayerSheetState extends State<FullPlayerSheet> {
  int _seekFeedback = 0; // -10 or +10
  Timer? _seekFeedbackTimer;

  @override
  void dispose() {
    _seekFeedbackTimer?.cancel();
    super.dispose();
  }

  void _onDoubleTapDown(TapDownDetails details, double width) {
    final isLeft = details.localPosition.dx < width / 2;
    final delta = isLeft ? -10 : 10;
    final current = widget.playback.position;
    final duration = widget.playback.duration;
    final newSeconds = (current.inSeconds + delta).clamp(
      0,
      duration.inSeconds > 0 ? duration.inSeconds : 0,
    );
    widget.playback.seek(Duration(seconds: newSeconds));

    setState(() {
      _seekFeedback = delta;
    });
    _seekFeedbackTimer?.cancel();
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _seekFeedback = 0);
    });
  }

  void _showSleepTimerPicker(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  const Icon(Icons.bedtime, size: 22),
                  const SizedBox(width: 12),
                  Text(
                    'Sleep Timer',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (widget.playback.hasSleepTimer)
                    TextButton(
                      onPressed: () {
                        widget.playback.cancelSleepTimer();
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('Turn Off'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('15 minutes'),
              trailing: widget.playback.sleepTimerRemaining?.inMinutes == 15
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                widget.playback.setSleepTimer(const Duration(minutes: 15));
                Navigator.of(ctx).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('30 minutes'),
              trailing: widget.playback.sleepTimerRemaining?.inMinutes == 30
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                widget.playback.setSleepTimer(const Duration(minutes: 30));
                Navigator.of(ctx).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('45 minutes'),
              trailing: widget.playback.sleepTimerRemaining?.inMinutes == 45
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                widget.playback.setSleepTimer(const Duration(minutes: 45));
                Navigator.of(ctx).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('60 minutes'),
              trailing: widget.playback.sleepTimerRemaining?.inMinutes == 60
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                widget.playback.setSleepTimer(const Duration(minutes: 60));
                Navigator.of(ctx).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.music_off_outlined),
              title: const Text('End of track'),
              trailing: widget.playback.isSleepAtEndOfTrack
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                widget.playback.setSleepTimer(null, endOfTrack: true);
                Navigator.of(ctx).pop();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openAudiobookReader(BuildContext context) async {
    final item = widget.playback.selected;
    if (item == null) return;

    final existingPdf = widget.storage.getTrackPdfPath(item.id);
    if (existingPdf != null && File(existingPdf).existsSync()) {
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AudiobookReaderScreen(
            item: item,
            pdfPath: existingPdf,
            playback: widget.playback,
            storage: widget.storage,
            downloadService: widget.downloadService,
            bookService: widget.bookService,
          ),
        ),
      );
    } else {
      final pickedPdf = await AttachPdfSheet.show(
        context,
        item: item,
        storage: widget.storage,
        bookService: widget.bookService,
      );
      if (pickedPdf != null && context.mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AudiobookReaderScreen(
              item: item,
              pdfPath: pickedPdf,
              playback: widget.playback,
              storage: widget.storage,
              downloadService: widget.downloadService,
              bookService: widget.bookService,
            ),
          ),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      final hours = duration.inHours;
      final remainingMins = (minutes % 60).toString().padLeft(2, '0');
      return '$hours:$remainingMins:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final playback = widget.playback;
    final storage = widget.storage;
    final downloadService = widget.downloadService;
    final item = playback.selected;

    if (item == null) {
      return const SizedBox(
        height: 300,
        child: Center(child: Text('No song selected')),
      );
    }

    final theme = Theme.of(context);
    final isFav = storage.isFavorite(item.id);
    final isDownloaded = storage.isDownloaded(item.id);
    final isDownloading = downloadService?.isDownloading(item.id) ?? false;
    final hasAttachedPdf = storage.getTrackPdfPath(item.id) != null;
    final duration = playback.duration > Duration.zero
        ? playback.duration
        : (item.duration ?? Duration.zero);
    final position = playback.position;
    final maxSeconds = duration.inSeconds.toDouble();
    final currentSeconds = position.inSeconds.toDouble().clamp(
      0.0,
      maxSeconds > 0 ? maxSeconds : 1.0,
    );

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // Drag Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                  icon: const Icon(Icons.keyboard_arrow_down),
                  tooltip: 'Minimize',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'NOW PLAYING',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      letterSpacing: 1.2,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Playback Speed Button Badge
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      icon: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: playback.playbackSpeed != 1.0
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outlineVariant.withAlpha(140),
                            width: 1.2,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          color: playback.playbackSpeed != 1.0
                              ? theme.colorScheme.primary.withAlpha(35)
                              : Colors.transparent,
                        ),
                        child: Text(
                          playback.playbackSpeed == 1.0
                              ? '1x'
                              : '${playback.playbackSpeed % 1 == 0 ? playback.playbackSpeed.toInt() : playback.playbackSpeed}x',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: playback.playbackSpeed != 1.0
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      tooltip: 'Playback speed: ${playback.playbackSpeed}x',
                      onPressed: () => showSpeedPickerSheet(context, playback),
                    ),
                    // Read Along (PDF / Book) Icon
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                      icon: Icon(
                        storage.getTrackPdfPath(item.id) != null
                            ? Icons.auto_stories
                            : Icons.auto_stories_outlined,
                        size: 21,
                        color: storage.getTrackPdfPath(item.id) != null
                            ? theme.colorScheme.primary
                            : null,
                      ),
                      tooltip: storage.getTrackPdfPath(item.id) != null
                          ? 'Read along (PDF attached)'
                          : 'Attach book (PDF)',
                      onPressed: () => _openAudiobookReader(context),
                    ),
                    // Sleep Timer Header Icon
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                      icon: Icon(
                        playback.hasSleepTimer
                            ? Icons.bedtime
                            : Icons.bedtime_outlined,
                        size: 21,
                        color: playback.hasSleepTimer
                            ? theme.colorScheme.primary
                            : null,
                      ),
                      tooltip: playback.hasSleepTimer
                          ? 'Timer: ${playback.sleepTimerRemainingFormatted}'
                          : 'Set sleep timer',
                      onPressed: () => _showSleepTimerPicker(context),
                    ),
                    // Add to Playlist Icon
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                      icon: const Icon(Icons.playlist_add, size: 22),
                      tooltip: 'Add to playlist',
                      onPressed: () => AddToPlaylistDialog.show(
                        context,
                        item: item,
                        storageService: storage,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Artwork with Double-Tap to Seek (+/- 10s) and Ambient Glow
            Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final artworkWidth = constraints.maxWidth.clamp(0.0, 320.0);
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Ambient Glow behind album artwork
                      Container(
                        width: artworkWidth * 0.82,
                        height: artworkWidth * 0.82,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withAlpha(55),
                              blurRadius: 65,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onDoubleTapDown: (details) =>
                            _onDoubleTapDown(details, artworkWidth),
                        child: Container(
                          width: artworkWidth,
                          height: artworkWidth,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white.withAlpha(20),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(160),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                item.thumbnailUrl.isNotEmpty
                                    ? Image.network(
                                        item.thumbnailUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                Container(
                                          color: theme
                                              .colorScheme.surfaceContainerHighest,
                                          child: const Icon(
                                            Icons.music_note,
                                            size: 80,
                                          ),
                                        ),
                                      )
                                    : Container(
                                        color: theme
                                            .colorScheme.surfaceContainerHighest,
                                        child: const Icon(
                                          Icons.music_note,
                                          size: 80,
                                        ),
                                      ),

                                // Seek Feedback Overlay
                                if (_seekFeedback != 0)
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    color: Colors.black54,
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _seekFeedback < 0
                                                ? Icons.replay_10
                                                : Icons.forward_10,
                                            size: 56,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            _seekFeedback < 0 ? '-10s' : '+10s',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 20),

            // Title, Channel & Favorite
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.channelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  iconSize: 28,
                  icon: Icon(
                    isFav ? Icons.favorite : Icons.favorite_border,
                    color: isFav ? Colors.redAccent : null,
                  ),
                  tooltip: isFav ? 'Remove from favorites' : 'Add to favorites',
                  onPressed: () => storage.toggleFavorite(item),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Scrub Bar
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                trackHeight: 3.5,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: theme.colorScheme.primary,
                thumbColor: theme.colorScheme.primary,
              ),
              child: Slider(
                value: currentSeconds,
                min: 0.0,
                max: maxSeconds > 0 ? maxSeconds : 1.0,
                onChanged: maxSeconds > 0
                    ? (val) => playback.seek(Duration(seconds: val.toInt()))
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(position),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    _formatDuration(duration),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Playback Controls Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Shuffle
                IconButton(
                  icon: Icon(
                    Icons.shuffle,
                    color: playback.isShuffle ? theme.colorScheme.primary : null,
                  ),
                  tooltip: playback.isShuffle
                      ? 'Shuffle is on'
                      : 'Shuffle is off',
                  onPressed: playback.toggleShuffle,
                ),
                // Previous
                IconButton(
                  iconSize: 36,
                  icon: const Icon(Icons.skip_previous),
                  tooltip: 'Previous',
                  onPressed: playback.skipToPrevious,
                ),
                // Play / Pause / Replay with Glow
                if (playback.isLoading)
                  const SizedBox(
                    width: 64,
                    height: 64,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withAlpha(90),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: IconButton.filled(
                      iconSize: 38,
                      style: IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.all(14),
                      ),
                      tooltip: playback.error != null
                          ? 'Retry'
                          : playback.isCompleted
                          ? 'Replay'
                          : playback.isPlaying
                          ? 'Pause'
                          : 'Play',
                      onPressed: playback.togglePlayback,
                      icon: Icon(
                        playback.error != null
                            ? Icons.refresh
                            : playback.isCompleted
                            ? Icons.replay
                            : playback.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                      ),
                    ),
                  ),
                // Next
                IconButton(
                  iconSize: 36,
                  icon: const Icon(Icons.skip_next),
                  tooltip: 'Next',
                  onPressed: playback.skipToNext,
                ),
                // Repeat
                IconButton(
                  icon: Icon(
                    playback.loopMode == PlaybackLoopMode.one
                        ? Icons.repeat_one
                        : playback.loopMode == PlaybackLoopMode.all
                        ? Icons.repeat
                        : Icons.repeat,
                    color: playback.loopMode != PlaybackLoopMode.off
                        ? theme.colorScheme.primary
                        : null,
                  ),
                  tooltip: playback.loopMode == PlaybackLoopMode.one
                      ? 'Repeat One'
                      : playback.loopMode == PlaybackLoopMode.all
                      ? 'Repeat All'
                      : 'Repeat Off',
                  onPressed: playback.toggleLoopMode,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Active Speed, Sleep Timer, or Book indicators
            if (playback.hasSleepTimer || playback.playbackSpeed != 1.0 || hasAttachedPdf)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (playback.playbackSpeed != 1.0)
                      ActionChip(
                        avatar: Icon(
                          Icons.speed,
                          size: 15,
                          color: theme.colorScheme.primary,
                        ),
                        label: Text(
                          'Speed: ${playback.playbackSpeed % 1 == 0 ? playback.playbackSpeed.toInt() : playback.playbackSpeed}x',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => showSpeedPickerSheet(context, playback),
                      ),
                    if (hasAttachedPdf)
                      ActionChip(
                        avatar: Icon(
                          Icons.auto_stories,
                          size: 15,
                          color: theme.colorScheme.primary,
                        ),
                        label: Text(
                          'Book (p. ${storage.getTrackPdfPage(item.id) + 1})',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _openAudiobookReader(context),
                      ),
                    if (playback.hasSleepTimer)
                      ActionChip(
                        avatar: Icon(
                          Icons.bedtime,
                          size: 15,
                          color: theme.colorScheme.primary,
                        ),
                        label: Text(
                          'Sleep: ${playback.sleepTimerRemainingFormatted}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _showSleepTimerPicker(context),
                      ),
                  ],
                ),
              ),

            // Bottom Actions: Download and Queue
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Download Button
                Flexible(
                  child: isDownloading
                      ? TextButton.icon(
                          icon: const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          label: Text(
                            'Downloading ${((downloadService?.getProgress(item.id) ?? 0) * 100).toInt()}%',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: () {
                            downloadService?.cancelDownload(item.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Download cancelled')),
                            );
                          },
                        )
                      : isDownloaded
                      ? TextButton.icon(
                          icon: const Icon(Icons.offline_pin, color: Colors.green),
                          label: const Text(
                            'Downloaded',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: () async {
                            final confirm = await showConfirmDialog(
                              context,
                              title: 'Delete Download?',
                              message:
                                  'Remove downloaded audio for "${item.title}" from your device?',
                              confirmLabel: 'Delete',
                            );
                            if (confirm && context.mounted) {
                              downloadService?.deleteDownload(item.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Download deleted')),
                              );
                            }
                          },
                        )
                      : TextButton.icon(
                          icon: const Icon(Icons.download),
                          label: const Text(
                            'Download',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: () {
                            if (downloadService != null) {
                              downloadService.downloadTrack(item);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Downloading "${item.title}"...'),
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                          },
                        ),
                ),
                const SizedBox(width: 8),

                // Queue Shortcut
                Flexible(
                  child: TextButton.icon(
                    icon: const Icon(Icons.queue_music),
                    label: Text(
                      playback.upNext.isNotEmpty
                          ? 'Queue (${playback.upNext.length})'
                          : 'Queue',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onOpenQueue?.call();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    );
  }
}

void showSpeedPickerSheet(BuildContext context, PlaybackController playback) {
  final theme = Theme.of(context);
  final currentSpeed = playback.playbackSpeed;
  const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: theme.colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'PLAYBACK SPEED',
                    style: theme.textTheme.labelMedium?.copyWith(
                      letterSpacing: 1.2,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      playback.setPlaybackSpeed(1.0);
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('Reset (1.0x)'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            for (final s in speeds)
              ListTile(
                dense: true,
                leading: Icon(
                  Icons.speed,
                  color: s == currentSpeed ? theme.colorScheme.primary : null,
                  size: 20,
                ),
                title: Text(
                  s == 1.0 ? '1.0x (Normal)' : '${s}x',
                  style: TextStyle(
                    fontWeight: s == currentSpeed ? FontWeight.bold : FontWeight.normal,
                    color: s == currentSpeed ? theme.colorScheme.primary : null,
                  ),
                ),
                trailing: s == currentSpeed
                    ? Icon(Icons.check, color: theme.colorScheme.primary, size: 20)
                    : null,
                onTap: () {
                  playback.setPlaybackSpeed(s);
                  Navigator.of(ctx).pop();
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
}
