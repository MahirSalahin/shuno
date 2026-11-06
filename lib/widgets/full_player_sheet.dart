import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../screens/audiobook_reader_screen.dart';
import '../services/book_service.dart';
import '../services/download_service.dart';
import '../services/playback_controller.dart';
import '../services/storage_service.dart';
import 'add_to_playlist_dialog.dart';
import 'attach_pdf_sheet.dart';
import 'confirm_dialog.dart';
import 'marquee_text.dart';

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
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: true,
        barrierDismissible: false,
        pageBuilder: (context, animation, secondaryAnimation) => AnimatedBuilder(
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
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          final curve = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(begin: begin, end: end).animate(curve),
            child: child,
          );
        },
      ),
    );
  }

  @override
  State<FullPlayerSheet> createState() => _FullPlayerSheetState();
}

class _FullPlayerSheetState extends State<FullPlayerSheet> {
  int _seekFeedback = 0; // -10 or +10
  Timer? _seekFeedbackTimer;
  double _cardDragOffset = 0.0;
  bool _isDraggingCard = false;

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

    final existingPdf = widget.storage.getTrackPdfPath(item.id, title: item.title);
    if (existingPdf != null && BookService.isPdfFileValid(existingPdf)) {
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
      if (existingPdf != null) {
        await widget.storage.removeTrackPdf(item.id);
      }
      if (!context.mounted) return;
      final pickedPdf = await AttachPdfSheet.show(
        context,
        item: item,
        storage: widget.storage,
        bookService: widget.bookService,
      );
      if (pickedPdf != null && context.mounted && BookService.isPdfFileValid(pickedPdf)) {
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
    final surfaceColor = theme.colorScheme.surface;
    final rawThumb = item.thumbnailUrl;
    final effectiveThumbnailUrl = rawThumb.contains('mqdefault.jpg')
        ? rawThumb.replaceAll('mqdefault.jpg', 'hqdefault.jpg')
        : rawThumb;
    final hasThumbnail = effectiveThumbnailUrl.isNotEmpty;
    final isYouTubeThumb = effectiveThumbnailUrl.contains('ytimg.com') ||
        effectiveThumbnailUrl.contains('youtube.com') ||
        effectiveThumbnailUrl.contains('googlevideo.com');
    final isFav = storage.isFavorite(item.id);
    final isDownloaded = storage.isDownloaded(item.id);
    final isDownloading = downloadService?.isDownloading(item.id) ?? false;
    final attachedPdfPath = storage.getTrackPdfPath(item.id, title: item.title);
    final hasAttachedPdf = BookService.isPdfFileValid(attachedPdfPath);

    return Scaffold(
      backgroundColor: surfaceColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Fully Opaque Solid Base Color
          ColoredBox(color: surfaceColor),

          // 2. Diffused Ambient Artwork Backdrop (Spotify-style)
          if (hasThumbnail)
            Positioned.fill(
              child: Opacity(
                opacity: 0.38,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 65, sigmaY: 65),
                  child: Transform.scale(
                    scale: 1.4,
                    child: Image.network(
                      effectiveThumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            )
          else
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      theme.colorScheme.primary.withAlpha(45),
                      surfaceColor,
                    ],
                  ),
                ),
              ),
            ),

          // 3. Smooth Vignette & Bottom Surface Fade Gradient
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withAlpha(90),
                    Colors.black.withAlpha(75),
                    surfaceColor.withAlpha(220),
                    surfaceColor,
                  ],
                  stops: const [0.0, 0.35, 0.72, 1.0],
                ),
              ),
            ),
          ),

          // 4. Foreground Content (Full-Screen Spaced Layout)
          SafeArea(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0.0) > 280) {
                  Navigator.of(context).pop();
                }
              },
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final screenHeight = constraints.maxHeight;
                  final screenWidth = constraints.maxWidth;

                  // Fixed element heights (Spotify-matched spacing)
                  const topPadding = 6.0;
                  const topBarHeight = 44.0;
                  const titleRowHeight = 48.0;
                  const titleToScrubber = 12.0;
                  const scrubberHeight = 44.0;
                  const scrubberToControls = 14.0;
                  const controlsHeight = 68.0;
                  const bottomToolbarHeight = 44.0;
                  const bottomPadding = 10.0;

                  const totalFixedUi = topPadding +
                      topBarHeight +
                      titleRowHeight +
                      titleToScrubber +
                      scrubberHeight +
                      scrubberToControls +
                      controlsHeight +
                      bottomToolbarHeight +
                      bottomPadding;

                  final availableSpace =
                      (screenHeight - totalFixedUi).clamp(0.0, double.infinity);

                  // 16:9 Video Artwork sizing (preserves original video aspect ratio, prevents chopping titles & faces)
                  final targetWidth = (screenWidth - 40).clamp(240.0, 420.0);
                  final targetHeight = targetWidth * (9 / 16);
                  final maxArtHeight = (availableSpace * 0.55).clamp(140.0, 320.0);

                  final artworkHeight =
                      targetHeight > maxArtHeight ? maxArtHeight : targetHeight;
                  final artworkWidth = targetHeight > maxArtHeight
                      ? artworkHeight * (16 / 9)
                      : targetWidth;

                  // Remaining margins distributed between top gap, mid gap, and bottom gap
                  final remainingMargins =
                      (availableSpace - artworkHeight).clamp(0.0, double.infinity);
                  final topGap = (remainingMargins * 0.30).clamp(16.0, 90.0);
                  final bottomGap = (remainingMargins * 0.28).clamp(20.0, 72.0);
                  final midGap = (remainingMargins - topGap - bottomGap).clamp(16.0, double.infinity);

                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: topPadding),

                        // Top Bar: Minimize arrow, Center "NOW PLAYING" & channel name, Right Sleep & Playlist Add
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              iconSize: 28,
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                              tooltip: 'Minimize',
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'NOW PLAYING',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      letterSpacing: 1.5,
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.onSurfaceVariant.withAlpha(210),
                                      fontSize: 10.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.channelName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Sleep Timer Icon
                                IconButton(
                                  iconSize: 22,
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                                  icon: Icon(
                                    playback.hasSleepTimer
                                        ? Icons.bedtime
                                        : Icons.bedtime_outlined,
                                    size: 22,
                                    color: playback.hasSleepTimer
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                  tooltip: playback.hasSleepTimer
                                      ? 'Sleep timer: ${playback.sleepTimerRemainingFormatted}'
                                      : 'Set sleep timer',
                                  onPressed: () => _showSleepTimerPicker(context),
                                ),
                                const SizedBox(width: 4),
                                // Add to Playlist Icon
                                IconButton(
                                  iconSize: 24,
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                                  icon: Icon(
                                    Icons.playlist_add,
                                    color: Colors.white.withAlpha(200),
                                  ),
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

                        SizedBox(height: topGap),

                        // Center Artwork with Double-Tap to Seek (+/- 10s) and Ambient Natural Shadow
                        Center(
                                child: GestureDetector(
                        key: const ValueKey('full_player_track_card'),
                        onDoubleTapDown: (details) =>
                            _onDoubleTapDown(details, artworkWidth),
                        onHorizontalDragStart: (_) {
                          setState(() {
                            _isDraggingCard = true;
                            _cardDragOffset = 0.0;
                          });
                        },
                        onHorizontalDragUpdate: (details) {
                          setState(() {
                            _cardDragOffset = (_cardDragOffset + (details.primaryDelta ?? 0.0))
                                .clamp(-120.0, 120.0);
                          });
                        },
                        onHorizontalDragEnd: (details) {
                          final velocity = details.primaryVelocity ?? 0.0;
                          final shouldNext = _cardDragOffset < -40.0 || velocity < -250.0;
                          final shouldPrev = _cardDragOffset > 40.0 || velocity > 250.0;

                          if (shouldNext) {
                            widget.playback.skipToNext();
                          } else if (shouldPrev) {
                            widget.playback.skipToPrevious();
                          }

                          setState(() {
                            _isDraggingCard = false;
                            _cardDragOffset = 0.0;
                          });
                        },
                        onHorizontalDragCancel: () {
                          if (_isDraggingCard) {
                            setState(() {
                              _isDraggingCard = false;
                              _cardDragOffset = 0.0;
                            });
                          }
                        },
                        child: AnimatedContainer(
                          duration: _isDraggingCard
                              ? Duration.zero
                              : const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          transform: Matrix4.translationValues(_cardDragOffset, 0, 0)
                            ..rotateZ(_cardDragOffset * 0.0006),
                          child: Container(
                            width: artworkWidth,
                            height: artworkHeight,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
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
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  effectiveThumbnailUrl.isNotEmpty
                                      ? Image.network(
                                          effectiveThumbnailUrl,
                                          fit: isYouTubeThumb
                                              ? BoxFit.cover
                                              : BoxFit.contain,
                                          cacheWidth: (artworkWidth * 2).toInt(),
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  Container(
                                            color: theme
                                                .colorScheme.surfaceContainerHighest,
                                            child: const Icon(
                                              Icons.graphic_eq,
                                              size: 80,
                                            ),
                                          ),
                                        )
                                      : Container(
                                          color: theme
                                              .colorScheme.surfaceContainerHighest,
                                          child: const Icon(
                                            Icons.graphic_eq,
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

                                  // Swipe Feedback Overlay (Next / Previous)
                                  if (_cardDragOffset.abs() > 20)
                                    Positioned.fill(
                                      child: Container(
                                        color: Colors.black.withAlpha(
                                          (_cardDragOffset.abs() * 0.85).clamp(0, 150).toInt(),
                                        ),
                                        child: Center(
                                          child: Row(
                                            mainAxisAlignment: _cardDragOffset < 0
                                                ? MainAxisAlignment.end
                                                : MainAxisAlignment.start,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 24),
                                                child: Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      _cardDragOffset < 0
                                                          ? Icons.skip_next
                                                          : Icons.skip_previous,
                                                      size: 40,
                                                      color: Colors.white.withAlpha(
                                                        (_cardDragOffset.abs() * 3).clamp(80, 255).toInt(),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      _cardDragOffset < 0 ? 'Next' : 'Previous',
                                                      style: TextStyle(
                                                        color: Colors.white.withAlpha(
                                                          (_cardDragOffset.abs() * 3).clamp(80, 255).toInt(),
                                                        ),
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: midGap),

            // Title, Channel, Download & Favorite
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MarqueeText(
                        text: item.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.3,
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
                const SizedBox(width: 8),
                // Download Button (Track-level action)
                if (isDownloading)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                    icon: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        value: downloadService?.getProgress(item.id),
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    tooltip:
                        'Downloading ${((downloadService?.getProgress(item.id) ?? 0) * 100).toInt()}% (tap to cancel)',
                    onPressed: () {
                      downloadService?.cancelDownload(item.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Download cancelled')),
                      );
                    },
                  )
                else if (isDownloaded)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                    icon: Icon(
                      Icons.download_done,
                      size: 24,
                      color: theme.colorScheme.primary,
                    ),
                    tooltip: 'Downloaded (offline ready)',
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
                else
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                    icon: Icon(
                      Icons.arrow_circle_down_outlined,
                      size: 24,
                      color: Colors.white.withAlpha(200),
                    ),
                    tooltip: 'Download',
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
                const SizedBox(width: 2),
                // Favorite Button (Track-level action)
                IconButton(
                  iconSize: 26,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                  icon: Icon(
                    isFav ? Icons.favorite : Icons.favorite_border,
                    color: isFav ? Colors.redAccent : Colors.white.withAlpha(200),
                  ),
                  tooltip: isFav ? 'Remove from favorites' : 'Add to favorites',
                  onPressed: () => storage.toggleFavorite(item),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Scrub Bar
            _PlayerScrubber(
              playback: playback,
              item: item,
            ),
            const SizedBox(height: 14),

            // Playback Controls Row (Layer 1 - prominent touch targets)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Shuffle
                IconButton(
                  iconSize: 26,
                  icon: Icon(
                    Icons.shuffle,
                    color: playback.isShuffle
                        ? theme.colorScheme.primary
                        : Colors.white.withAlpha(180),
                  ),
                  tooltip: playback.isShuffle
                      ? 'Shuffle is on'
                      : 'Shuffle is off',
                  onPressed: playback.toggleShuffle,
                ),
                // Previous
                IconButton(
                  iconSize: 34,
                  icon: const Icon(Icons.skip_previous, color: Colors.white),
                  tooltip: 'Previous',
                  onPressed: playback.skipToPrevious,
                ),
                // Play / Pause / Replay with Clean Contrast Shadow
                if (playback.isLoading)
                  const SizedBox(
                    width: 68,
                    height: 68,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 3.2,
                        color: Colors.white,
                      ),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(80),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: IconButton.filled(
                      iconSize: 38,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.all(15),
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
                  iconSize: 34,
                  icon: const Icon(Icons.skip_next, color: Colors.white),
                  tooltip: 'Next',
                  onPressed: playback.skipToNext,
                ),
                // Repeat
                IconButton(
                  iconSize: 26,
                  icon: Icon(
                    playback.loopMode == PlaybackLoopMode.one
                        ? Icons.repeat_one
                        : playback.loopMode == PlaybackLoopMode.all
                        ? Icons.repeat
                        : Icons.repeat,
                    color: playback.loopMode != PlaybackLoopMode.off
                        ? theme.colorScheme.primary
                        : Colors.white.withAlpha(180),
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

            // Bottom Icon Toolbar (Layer 2): Audio tools group (Speed, Book) on left, Queue on right
            Padding(
              padding: EdgeInsets.only(top: bottomGap, bottom: bottomPadding),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left group: Playback Speed badge + Book / PDF reader
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Playback Speed Button Badge
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
                        icon: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: playback.playbackSpeed != 1.0
                                  ? theme.colorScheme.primary
                                  : Colors.white.withAlpha(100),
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
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: playback.playbackSpeed != 1.0
                                  ? theme.colorScheme.primary
                                  : Colors.white.withAlpha(200),
                            ),
                          ),
                        ),
                        tooltip: 'Playback speed: ${playback.playbackSpeed}x',
                        onPressed: () => showSpeedPickerSheet(context, playback),
                      ),
                      const SizedBox(width: 8),
                      // Read Along / Book (PDF) Icon
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(width: 42, height: 42),
                        icon: Icon(
                          hasAttachedPdf
                              ? Icons.auto_stories
                              : Icons.auto_stories_outlined,
                          size: 23,
                          color: hasAttachedPdf
                              ? theme.colorScheme.primary
                              : Colors.white.withAlpha(200),
                        ),
                        tooltip: hasAttachedPdf
                            ? 'Read along (PDF attached)'
                            : 'Attach book (PDF)',
                        onPressed: () => _openAudiobookReader(context),
                      ),
                    ],
                  ),

                  // Right group: Queue Icon (Clean, non-music icon, no badge)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 42, height: 42),
                    icon: Icon(
                      Icons.playlist_play,
                      size: 28,
                      color: Colors.white.withAlpha(200),
                    ),
                    tooltip: 'Queue',
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onOpenQueue?.call();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  ),
),
          ),
        ],
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

class _PlayerScrubber extends StatefulWidget {
  const _PlayerScrubber({
    required this.playback,
    required this.item,
  });

  final PlaybackController playback;
  final dynamic item;

  @override
  State<_PlayerScrubber> createState() => _PlayerScrubberState();
}

class _PlayerScrubberState extends State<_PlayerScrubber> {
  double? _dragSeconds;

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
    final theme = Theme.of(context);
    final playback = widget.playback;

    return ValueListenableBuilder<Duration>(
      valueListenable: playback.positionNotifier,
      builder: (context, position, _) {
        final duration = playback.duration > Duration.zero
            ? playback.duration
            : (widget.item.duration ?? Duration.zero);
        final maxSeconds = duration.inSeconds.toDouble();
        final currentSeconds = (_dragSeconds ?? position.inSeconds.toDouble())
            .clamp(0.0, maxSeconds > 0 ? maxSeconds : 1.0)
            .toDouble();

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                trackHeight: 3.5,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: Colors.white,
                thumbColor: Colors.white,
                inactiveTrackColor: Colors.white.withAlpha(45),
              ),
              child: Slider(
                value: currentSeconds,
                min: 0.0,
                max: maxSeconds > 0 ? maxSeconds : 1.0,
                onChangeStart: maxSeconds > 0
                    ? (val) {
                        setState(() => _dragSeconds = val);
                      }
                    : null,
                onChanged: maxSeconds > 0
                    ? (val) {
                        setState(() => _dragSeconds = val);
                      }
                    : null,
                onChangeEnd: maxSeconds > 0
                    ? (val) {
                        setState(() => _dragSeconds = null);
                        playback.seek(Duration(seconds: val.toInt()));
                      }
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(
                      _dragSeconds != null
                          ? Duration(seconds: _dragSeconds!.toInt())
                          : position,
                    ),
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
          ],
        );
      },
    );
  }
}
