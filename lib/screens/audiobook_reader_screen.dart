import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';

import '../models/youtube_search_item.dart';
import '../services/book_service.dart';
import '../services/download_service.dart';
import '../services/playback_controller.dart';
import '../services/storage_service.dart';
import '../widgets/attach_pdf_sheet.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/full_player_sheet.dart';

class AudiobookReaderScreen extends StatefulWidget {
  const AudiobookReaderScreen({
    super.key,
    required this.item,
    required this.pdfPath,
    required this.playback,
    required this.storage,
    this.downloadService,
    this.bookService,
  });

  final YoutubeSearchItem item;
  final String pdfPath;
  final PlaybackController playback;
  final StorageService storage;
  final DownloadService? downloadService;
  final BookService? bookService;

  @override
  State<AudiobookReaderScreen> createState() => _AudiobookReaderScreenState();
}

class _AudiobookReaderScreenState extends State<AudiobookReaderScreen> {
  late String _currentPdfPath = widget.pdfPath;
  late int _currentPage = widget.storage.getTrackPdfPage(widget.item.id, pdfPath: widget.pdfPath);
  int _totalPages = 0;
  bool _isNightMode = true;
  bool _isReady = false;
  String? _errorMessage;
  PDFViewController? _pdfViewController;

  // Immersive reading experience state
  bool _showControls = true;
  Timer? _autoHideTimer;
  bool _swipeHorizontal = false;

  @override
  void initState() {
    super.initState();
    _startAutoHideTimer();
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    super.dispose();
  }

  void _startAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _showControls) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startAutoHideTimer();
    } else {
      _autoHideTimer?.cancel();
    }
  }

  void _onUserInteracted() {
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _startAutoHideTimer();
  }

  Future<void> _jumpToPage(int page) async {
    if (_totalPages <= 0) return;
    final targetPage = page.clamp(0, _totalPages - 1);
    await _pdfViewController?.setPage(targetPage);
    if (mounted) {
      setState(() => _currentPage = targetPage);
      widget.storage.setTrackPdfPage(widget.item.id, targetPage, pdfPath: _currentPdfPath);
    }
  }

  void _showJumpToPageDialog() {
    _autoHideTimer?.cancel();
    final controller = TextEditingController(text: '${_currentPage + 1}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Jump to Page'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter page number (1 – $_totalPages):',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Page',
                suffixText: '/ $_totalPages',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onSubmitted: (val) {
                final page = int.tryParse(val.trim());
                if (page != null && page >= 1 && page <= _totalPages) {
                  Navigator.of(ctx).pop();
                  _jumpToPage(page - 1);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final page = int.tryParse(controller.text.trim());
              if (page != null && page >= 1 && page <= _totalPages) {
                Navigator.of(ctx).pop();
                _jumpToPage(page - 1);
              }
            },
            child: const Text('Go'),
          ),
        ],
      ),
    ).then((_) {
      if (mounted && _showControls) {
        _startAutoHideTimer();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileExists = File(_currentPdfPath).existsSync();

    return Scaffold(
      backgroundColor: _isNightMode ? Colors.black : const Color(0xFFF7F7F7),
      body: Stack(
        children: [
          // 1. Edge-to-Edge PDF Reader Canvas
          Positioned.fill(
            child: !fileExists
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image, size: 48, color: theme.colorScheme.error),
                          const SizedBox(height: 12),
                          const Text(
                            'PDF file not found on device.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            icon: const Icon(Icons.refresh),
                            label: const Text('Re-attach PDF'),
                            onPressed: () async {
                              final newPath = await AttachPdfSheet.show(
                                context,
                                item: widget.item,
                                storage: widget.storage,
                                bookService: widget.bookService,
                              );
                              if (newPath != null && mounted) {
                                setState(() => _currentPdfPath = newPath);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  )
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Error loading PDF: $_errorMessage',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      )
                    : PDFView(
                        key: ValueKey('pdf_view_${_swipeHorizontal}_$_isNightMode'),
                        filePath: _currentPdfPath,
                        enableSwipe: true,
                        swipeHorizontal: _swipeHorizontal,
                        autoSpacing: _swipeHorizontal,
                        pageFling: _swipeHorizontal,
                        pageSnap: _swipeHorizontal,
                        defaultPage: _currentPage,
                        fitPolicy: FitPolicy.WIDTH,
                        preventLinkNavigation: false,
                        nightMode: _isNightMode,
                        onViewCreated: (controller) {
                          _pdfViewController = controller;
                        },
                        onRender: (pages) {
                          if (mounted) {
                            setState(() {
                              _totalPages = pages ?? 0;
                              _isReady = true;
                            });
                          }
                        },
                        onError: (error) {
                          if (mounted) {
                            setState(() => _errorMessage = error.toString());
                          }
                        },
                        onPageError: (page, error) {
                          if (mounted) {
                            setState(() => _errorMessage = '$page: $error');
                          }
                        },
                        onPageChanged: (page, total) {
                          if (page != null && mounted) {
                            setState(() => _currentPage = page);
                            widget.storage.setTrackPdfPage(widget.item.id, page, pdfPath: _currentPdfPath);
                          }
                        },
                      ),
          ),

          // 2. Loading Indicator
          if (fileExists && !_isReady && _errorMessage == null)
            const Center(
              child: CircularProgressIndicator(),
            ),

          // 3. Translucent Floating Top Bar (Disappears when reading)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopBar(theme),
          ),

          // 4. Translucent Floating Bottom Controls (Disappears when reading)
          Positioned(
            left: 14,
            right: 14,
            bottom: 16,
            child: _buildBottomControls(theme),
          ),

          // 5. Minimal Reading Pill (Only visible when main controls are hidden)
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: _buildImmersiveReadingPill(theme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(ThemeData theme) {
    final title = BookService.cleanAudiobookTitle(widget.item.title);

    return AnimatedSlide(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      offset: _showControls ? Offset.zero : const Offset(0, -1.2),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 240),
        opacity: _showControls ? 1.0 : 0.0,
        child: IgnorePointer(
          ignoring: !_showControls,
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: SafeArea(
              bottom: false,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withAlpha(165),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withAlpha(70),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(40),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.arrow_back),
                          tooltip: 'Back',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: _showJumpToPageDialog,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    _totalPages > 0
                                        ? 'Page ${_currentPage + 1} of $_totalPages • Tap to jump'
                                        : 'Page ${_currentPage + 1}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 11,
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Immersion Button (Disappear UI)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Immersive reading mode',
                          icon: const Icon(Icons.fullscreen),
                          onPressed: _toggleControls,
                        ),
                        // Reading Mode (Night / Light)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: _isNightMode ? 'Light reading mode' : 'Dark reading mode',
                          icon: Icon(_isNightMode ? Icons.light_mode : Icons.dark_mode, size: 20),
                          onPressed: () {
                            setState(() => _isNightMode = !_isNightMode);
                            _onUserInteracted();
                          },
                        ),
                        // Menu
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 20),
                          onSelected: (value) async {
                            _onUserInteracted();
                            if (value == 'orientation') {
                              setState(() => _swipeHorizontal = !_swipeHorizontal);
                            } else if (value == 'jump') {
                              _showJumpToPageDialog();
                            } else if (value == 'change') {
                              final newPath = await AttachPdfSheet.show(
                                context,
                                item: widget.item,
                                storage: widget.storage,
                                bookService: widget.bookService,
                              );
                              if (newPath != null && mounted) {
                                setState(() {
                                  _currentPdfPath = newPath;
                                  _isReady = false;
                                  _errorMessage = null;
                                });
                              }
                            } else if (value == 'detach') {
                              final nav = Navigator.of(context);
                              final confirm = await showConfirmDialog(
                                context,
                                title: 'Detach Book?',
                                message:
                                    'Detach this PDF from "${widget.item.title}"? The file will remain on your device.',
                                confirmLabel: 'Detach',
                              );
                              if (confirm && mounted) {
                                await widget.storage.removeTrackPdf(widget.item.id);
                                if (mounted) {
                                  nav.pop();
                                }
                              }
                            } else if (value == 'delete') {
                              final nav = Navigator.of(context);
                              final confirm = await showConfirmDialog(
                                context,
                                title: 'Delete Book File?',
                                message:
                                    'Permanently delete this PDF file from your device to free up storage space?',
                                confirmLabel: 'Delete',
                              );
                              if (confirm && mounted) {
                                final bService = widget.bookService ?? BookService();
                                await bService.deleteDownloadedPdf(_currentPdfPath);
                                await widget.storage.purgePdf(_currentPdfPath);
                                if (mounted) {
                                  nav.pop();
                                }
                              }
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'orientation',
                              child: Row(
                                children: [
                                  Icon(
                                    _swipeHorizontal ? Icons.view_headline : Icons.view_carousel,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(_swipeHorizontal ? 'Vertical scroll' : 'Horizontal page flip'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'jump',
                              child: Row(
                                children: [
                                  Icon(Icons.pin, size: 20),
                                  SizedBox(width: 10),
                                  Text('Jump to page'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'change',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_note, size: 20),
                                  SizedBox(width: 10),
                                  Text('Change PDF'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'detach',
                              child: Row(
                                children: [
                                  Icon(Icons.link_off, size: 20),
                                  SizedBox(width: 10),
                                  Text('Detach from track'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                  SizedBox(width: 10),
                                  Text('Delete from device', style: TextStyle(color: Colors.redAccent)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls(ThemeData theme) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      offset: _showControls ? Offset.zero : const Offset(0, 1.2),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 240),
        opacity: _showControls ? 1.0 : 0.0,
        child: IgnorePointer(
          ignoring: !_showControls,
          child: SafeArea(
            top: false,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withAlpha(165),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withAlpha(70),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(50),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // --- Page Navigation Scrubber & Quick Jumps ---
                      Row(
                        children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                            icon: const Icon(Icons.chevron_left, size: 22),
                            tooltip: 'Previous page',
                            onPressed: _currentPage > 0
                                ? () {
                                    _jumpToPage(_currentPage - 1);
                                    _onUserInteracted();
                                  }
                                : null,
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                trackHeight: 3,
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                activeTrackColor: theme.colorScheme.primary,
                                thumbColor: theme.colorScheme.primary,
                              ),
                              child: Slider(
                                value: (_currentPage + 1).toDouble().clamp(
                                  1.0,
                                  _totalPages > 0 ? _totalPages.toDouble() : 1.0,
                                ),
                                min: 1.0,
                                max: _totalPages > 0 ? _totalPages.toDouble() : 1.0,
                                divisions: _totalPages > 1 ? _totalPages - 1 : 1,
                                onChanged: (val) {
                                  _jumpToPage(val.toInt() - 1);
                                  _onUserInteracted();
                                },
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                            icon: const Icon(Icons.chevron_right, size: 22),
                            tooltip: 'Next page',
                            onPressed: _currentPage < _totalPages - 1
                                ? () {
                                    _jumpToPage(_currentPage + 1);
                                    _onUserInteracted();
                                  }
                                : null,
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: _showJumpToPageDialog,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface.withAlpha(150),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: theme.colorScheme.primary.withAlpha(120),
                                ),
                              ),
                              child: Text(
                                _totalPages > 0 ? '${_currentPage + 1}/$_totalPages' : '${_currentPage + 1}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      Divider(
                        height: 10,
                        thickness: 0.8,
                        color: theme.colorScheme.outlineVariant.withAlpha(60),
                      ),

                      // --- Audio Scrubber & Controls ---
                      ListenableBuilder(
                        listenable: widget.playback,
                        builder: (context, _) {
                          final playback = widget.playback;
                          final isPlaying = playback.isPlaying;
                          final isBuffering = playback.isBuffering;

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ValueListenableBuilder<Duration>(
                                valueListenable: playback.positionNotifier,
                                builder: (context, position, _) {
                                  final duration = playback.duration;
                                  final maxSeconds = duration.inSeconds > 0
                                      ? duration.inSeconds.toDouble()
                                      : 1.0;
                                  final curSeconds = position.inSeconds
                                      .toDouble()
                                      .clamp(0.0, maxSeconds);

                                  return Row(
                                    children: [
                                      Text(
                                        _formatDuration(position),
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      Expanded(
                                        child: SliderTheme(
                                          data: SliderTheme.of(context).copyWith(
                                            thumbShape:
                                                const RoundSliderThumbShape(
                                                    enabledThumbRadius: 5),
                                            trackHeight: 2.5,
                                            overlayShape:
                                                const RoundSliderOverlayShape(
                                                    overlayRadius: 10),
                                          ),
                                          child: Slider(
                                            value: curSeconds,
                                            min: 0.0,
                                            max: maxSeconds,
                                            onChanged: (val) {
                                              playback.seek(
                                                  Duration(seconds: val.toInt()));
                                              _onUserInteracted();
                                            },
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _formatDuration(duration),
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  // Speed badge
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
                                    icon: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: playback.playbackSpeed != 1.0
                                            ? theme.colorScheme.primaryContainer
                                            : theme.colorScheme.surface.withAlpha(140),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        playback.playbackSpeed == 1.0
                                            ? '1x'
                                            : '${playback.playbackSpeed % 1 == 0 ? playback.playbackSpeed.toInt() : playback.playbackSpeed}x',
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: playback.playbackSpeed != 1.0
                                            ? theme.colorScheme.onPrimaryContainer
                                            : theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    tooltip: 'Playback speed',
                                    onPressed: () {
                                      showSpeedPickerSheet(context, playback);
                                      _onUserInteracted();
                                    },
                                  ),

                                  // Skip backward 10s
                                  IconButton(
                                    icon: const Icon(Icons.replay_10, size: 24),
                                    tooltip: 'Back 10 seconds',
                                    onPressed: () {
                                      final target = playback.position - const Duration(seconds: 10);
                                      playback.seek(target < Duration.zero ? Duration.zero : target);
                                      _onUserInteracted();
                                    },
                                  ),

                                  // Play/Pause button
                                  IconButton.filled(
                                    style: IconButton.styleFrom(
                                      backgroundColor: theme.colorScheme.primary,
                                      foregroundColor: theme.colorScheme.onPrimary,
                                      padding: const EdgeInsets.all(10),
                                    ),
                                    icon: isBuffering
                                        ? SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.2,
                                              color: theme.colorScheme.onPrimary,
                                            ),
                                          )
                                        : Icon(
                                            isPlaying ? Icons.pause : Icons.play_arrow,
                                            size: 26,
                                          ),
                                    onPressed: () {
                                      playback.togglePlayback();
                                      _onUserInteracted();
                                    },
                                  ),

                                  // Skip forward 10s
                                  IconButton(
                                    icon: const Icon(Icons.forward_10, size: 24),
                                    tooltip: 'Forward 10 seconds',
                                    onPressed: () {
                                      final target = playback.position + const Duration(seconds: 10);
                                      final dur = playback.duration;
                                      playback.seek(target > dur ? dur : target);
                                      _onUserInteracted();
                                    },
                                  ),

                                  // Hide Controls Button
                                  IconButton(
                                    icon: const Icon(Icons.keyboard_arrow_down, size: 24),
                                    tooltip: 'Hide controls',
                                    onPressed: _toggleControls,
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImmersiveReadingPill(ThemeData theme) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      offset: !_showControls ? Offset.zero : const Offset(0, 1.6),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 240),
        opacity: !_showControls ? 0.9 : 0.0,
        child: IgnorePointer(
          ignoring: _showControls,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _toggleControls,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withAlpha(165),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withAlpha(70),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(50),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.playback.isPlaying ? Icons.play_arrow : Icons.pause,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _totalPages > 0
                            ? '${_currentPage + 1} / $_totalPages'
                            : 'Page ${_currentPage + 1}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.expand_less,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
