import 'dart:io';

import 'package:flutter/material.dart';

import '../models/youtube_search_item.dart';
import '../services/book_service.dart';
import '../services/storage_service.dart';
import 'confirm_dialog.dart';

class AttachPdfSheet extends StatefulWidget {
  const AttachPdfSheet({
    super.key,
    required this.item,
    required this.storage,
    this.bookService,
  });

  final YoutubeSearchItem item;
  final StorageService storage;
  final BookService? bookService;

  static Future<String?> show(
    BuildContext context, {
    required YoutubeSearchItem item,
    required StorageService storage,
    BookService? bookService,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AttachPdfSheet(
        item: item,
        storage: storage,
        bookService: bookService,
      ),
    );
  }

  @override
  State<AttachPdfSheet> createState() => _AttachPdfSheetState();
}

class _AttachPdfSheetState extends State<AttachPdfSheet> {
  late final _bookService = widget.bookService ?? BookService();
  late final List<String> _candidateQueries =
      BookService.extractSearchQueries(widget.item.title);
  late final _searchController = TextEditingController(
    text: _candidateQueries.isNotEmpty
        ? _candidateQueries.first
        : BookService.cleanAudiobookQuery(widget.item.title),
  );

  int _selectedChipIndex = -1; // -1 means "All Matches"
  List<ArchiveBookItem> _archiveResults = [];
  Set<String> _downloadedArchiveIds = {};
  List<File> _downloadedFiles = [];
  String? _suggestedPdfPath;
  String? _suggestedPdfName;
  bool _isSearching = false;
  String? _downloadingId;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _bookService.addListener(_onBookServiceChanged);
    _loadDownloadedFiles();
    _findSuggestedPdf();
    _performInitialSearch();
  }

  @override
  void dispose() {
    _bookService.removeListener(_onBookServiceChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onBookServiceChanged() {
    if (!mounted) return;
    setState(() {});

    if (_downloadingId != null) {
      final task = _bookService.getDownloadTask(_downloadingId!);
      if (task != null && task.isCompleted && task.savedPath != null) {
        // Auto-open reader if sheet is still open in foreground!
        Navigator.of(context).pop(task.savedPath);
      }
    }
  }

  Future<void> _loadDownloadedFiles() async {
    final list = await _bookService.getDownloadedBooks();
    if (mounted) {
      setState(() {
        _downloadedFiles = list;
      });
    }
  }

  Future<void> _findSuggestedPdf() async {
    final cleanSeriesTitle = BookService.cleanAudiobookTitle(widget.item.title);
    final cleanQuery = BookService.cleanAudiobookQuery(widget.item.title);

    // 1. Check if another track/part in the library has a matching PDF
    final matchingStoragePath = widget.storage.findMatchingPdfPath(cleanQuery);
    if (matchingStoragePath != null && BookService.isPdfFileValid(matchingStoragePath)) {
      if (mounted) {
        final rawTitle = widget.storage.getPdfTitle(matchingStoragePath);
        final relevantTitle = BookService.sanitizeBookTitle(
          rawTitle,
          fallbackTitle: cleanSeriesTitle,
        );
        if (rawTitle == null || rawTitle != relevantTitle) {
          widget.storage.setPdfTitle(matchingStoragePath, relevantTitle);
        }
        setState(() {
          _suggestedPdfPath = matchingStoragePath;
          _suggestedPdfName = relevantTitle;
        });
      }
      return;
    }

    // 2. Check local downloaded books directory for matching title
    final localBooks = await _bookService.getDownloadedBooks();
    final lowerQuery = cleanQuery.toLowerCase();
    for (final file in localBooks) {
      final rawTitle = widget.storage.getPdfTitle(file.path);
      final relevantTitle = BookService.sanitizeBookTitle(
        rawTitle,
        fallbackTitle: cleanSeriesTitle,
      );
      final name = file.path
          .split(Platform.pathSeparator)
          .last
          .replaceAll('.pdf', '')
          .toLowerCase();
      if (lowerQuery.isNotEmpty &&
          (name.contains(lowerQuery) ||
              lowerQuery.contains(name) ||
              (rawTitle != null && rawTitle.toLowerCase().contains(lowerQuery)))) {
        if (mounted) {
          if (rawTitle == null || rawTitle != relevantTitle) {
            widget.storage.setPdfTitle(file.path, relevantTitle);
          }
          setState(() {
            _suggestedPdfPath = file.path;
            _suggestedPdfName = relevantTitle;
          });
        }
        return;
      }
    }
  }

  Future<void> _performInitialSearch() async {
    setState(() {
      _isSearching = true;
      _statusMessage = null;
    });

    List<ArchiveBookItem> results;
    if (_candidateQueries.isNotEmpty) {
      results = await _bookService.searchArchiveMulti(_candidateQueries);
    } else {
      results = await _bookService.searchArchive(_searchController.text);
    }

    if (!mounted) return;
    await _processSearchResults(results);
  }

  Future<void> _performSearch([String? specificQuery]) async {
    final query = (specificQuery ?? _searchController.text).trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _statusMessage = null;
    });

    final results = await _bookService.searchArchive(query);
    if (!mounted) return;
    await _processSearchResults(results);
  }

  Future<void> _processSearchResults(List<ArchiveBookItem> results) async {
    final downloaded = <String>{};
    for (final book in results) {
      final path = await _bookService.getDownloadedPdfPath(book.id);
      if (path != null) {
        downloaded.add(book.id);
      }
    }

    if (!mounted) return;
    setState(() {
      _archiveResults = results;
      _downloadedArchiveIds = downloaded;
      _isSearching = false;
      if (results.isEmpty) {
        _statusMessage =
            'No matching books found on Internet Archive. Try tapping another keyword chip or pick from your device.';
      }
    });
  }

  Future<void> _pickFromDevice() async {
    final path = await _bookService.pickLocalPdf();
    if (path != null && mounted) {
      final relevantTitle = BookService.cleanAudiobookTitle(widget.item.title);
      await widget.storage.setTrackPdf(widget.item.id, path, title: relevantTitle);
      if (mounted) {
        Navigator.of(context).pop(path);
      }
    }
  }

  Future<void> _attachLocalPath(String path, {String? title}) async {
    final chosenTitle = BookService.sanitizeBookTitle(
      title ?? _suggestedPdfName ?? widget.storage.getPdfTitle(path),
      fallbackTitle: BookService.cleanAudiobookTitle(widget.item.title),
    );
    await widget.storage.setTrackPdf(widget.item.id, path, title: chosenTitle);
    if (mounted) {
      Navigator.of(context).pop(path);
    }
  }

  Future<void> _downloadAndAttach(ArchiveBookItem book) async {
    if (_bookService.isDownloading(book.id)) return;

    // Instant reuse: Check if already downloaded on disk!
    final existingLocal = await _bookService.getDownloadedPdfPath(book.id);
    if (existingLocal != null && mounted) {
      final relevantTitle = BookService.sanitizeBookTitle(
        book.title,
        fallbackTitle: BookService.cleanAudiobookTitle(widget.item.title),
      );
      await _attachLocalPath(existingLocal, title: relevantTitle);
      return;
    }

    setState(() {
      _downloadingId = book.id;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloading "${BookService.sanitizeBookTitle(book.title)}" in background...'),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // Launch robust background download
    await _bookService.startBackgroundDownload(
      book: book,
      targetTrackId: widget.item.id,
      fallbackSeriesTitle: BookService.cleanAudiobookTitle(widget.item.title),
      storage: widget.storage,
    );
  }


  void _showSavedPdfsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          final theme = Theme.of(ctx);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'DOWNLOADED BOOKS (${_downloadedFiles.length})',
                          style: theme.textTheme.labelMedium?.copyWith(
                            letterSpacing: 1.2,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (_downloadedFiles.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('No downloaded books stored on device.')),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _downloadedFiles.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (itemCtx, index) {
                          final file = _downloadedFiles[index];
                          final sizeBytes = file.existsSync() ? file.lengthSync() : 0;
                          final mb = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);
                          final rawTitle = widget.storage.getPdfTitle(file.path);
                          final fallback = file.path
                              .split(Platform.pathSeparator)
                              .last
                              .replaceAll('.pdf', '')
                              .replaceAll('_', ' ');
                          final savedTitle = BookService.sanitizeBookTitle(
                            rawTitle,
                            fallbackTitle: fallback,
                          );

                          return ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer.withAlpha(120),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.picture_as_pdf,
                                color: theme.colorScheme.primary,
                                size: 22,
                              ),
                            ),
                            title: Text(
                              savedTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                            ),
                            subtitle: Text(
                              '$mb MB • Stored locally',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FilledButton.tonal(
                                  style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    _attachLocalPath(file.path, title: savedTitle);
                                  },
                                  child: const Text('Attach'),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: theme.colorScheme.error,
                                    size: 20,
                                  ),
                                  tooltip: 'Delete from device',
                                  onPressed: () async {
                                    final confirm = await showConfirmDialog(
                                      context,
                                      title: 'Delete Book File?',
                                      message:
                                          'Delete "$savedTitle" from device storage? This will free up storage space.',
                                      confirmLabel: 'Delete',
                                    );
                                    if (confirm) {
                                      await _bookService.deleteDownloadedPdf(file.path);
                                      await widget.storage.purgePdf(file.path);
                                      await _loadDownloadedFiles();
                                      setModalState(() {});
                                      if (mounted) setState(() {});
                                      if (_downloadedFiles.isEmpty && ctx.mounted) {
                                        Navigator.of(ctx).pop();
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);

    return Container(
      height: mediaQuery.size.height * 0.85,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant.withAlpha(120),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title & subtitle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.auto_stories, color: theme.colorScheme.primary, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Attach Book (PDF)',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.item.title,
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
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 16),

          // Quick actions: Pick from device & View Saved Books
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Pick PDF from device'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _downloadingId != null ? null : _pickFromDevice,
                  ),
                ),
                if (_downloadedFiles.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.download_done, size: 18),
                    label: Text('Saved (${_downloadedFiles.length})'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _downloadingId != null ? null : _showSavedPdfsModal,
                  ),
                ],
              ],
            ),
          ),

          // Suggested Book for this Series (e.g. Part 1, 2, ...)
          if (_suggestedPdfPath != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withAlpha(90),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.primary.withAlpha(140),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.auto_stories, color: theme.colorScheme.primary, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Already on device for this series:',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _suggestedPdfName ?? 'Attached Book',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: () => _attachLocalPath(_suggestedPdfPath!),
                      child: const Text('Use this'),
                    ),
                  ],
                ),
              ),
            ),

          // Search bar for Internet Archive
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (val) {
                setState(() => _selectedChipIndex = -2);
                _performSearch(val);
              },
              decoration: InputDecoration(
                hintText: 'Search Internet Archive books…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 20),
                  onPressed: () {
                    setState(() => _selectedChipIndex = -2);
                    _performSearch(_searchController.text);
                  },
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          // Suggestion Chips (Transliterated, Bengali, English variations)
          if (_candidateQueries.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        avatar: Icon(
                          Icons.auto_awesome,
                          size: 14,
                          color: _selectedChipIndex == -1
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.primary,
                        ),
                        label: Text(
                          _archiveResults.isNotEmpty && _selectedChipIndex == -1
                              ? 'All Matches (${_archiveResults.length})'
                              : 'All Matches',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                        ),
                        selected: _selectedChipIndex == -1,
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        onSelected: (selected) {
                          setState(() {
                            _selectedChipIndex = -1;
                            _searchController.text = _candidateQueries.first;
                          });
                          _performInitialSearch();
                        },
                      ),
                    ),
                    for (int i = 0; i < _candidateQueries.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(
                            _candidateQueries[i],
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          selected: _selectedChipIndex == i,
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          onSelected: (selected) {
                            setState(() {
                              _selectedChipIndex = selected ? i : -1;
                              if (selected) {
                                _searchController.text = _candidateQueries[i];
                              }
                            });
                            if (selected) {
                              _performSearch(_candidateQueries[i]);
                            } else {
                              _performInitialSearch();
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // Results header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Text(
              'ONLINE MATCHES (INTERNET ARCHIVE)',
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.1,
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Results list or status
          Expanded(
            child: _buildResults(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(ThemeData theme) {
    if (_isSearching) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Searching Internet Archive…'),
          ],
        ),
      );
    }

    if (_statusMessage != null && _archiveResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 40, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text(
                _statusMessage!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      itemCount: _archiveResults.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final book = _archiveResults[index];
        final isDownloading = _bookService.isDownloading(book.id) || _downloadingId == book.id;
        final downloadProgress = _bookService.getDownloadProgress(book.id);
        final isCached = _downloadedArchiveIds.contains(book.id);

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isCached
                  ? theme.colorScheme.primaryContainer.withAlpha(120)
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isCached ? Icons.offline_pin : Icons.picture_as_pdf,
              color: theme.colorScheme.primary,
              size: 24,
            ),
          ),
          title: Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
          subtitle: Row(
            children: [
              if (isCached) ...[
                Text(
                  'Downloaded on device',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (book.creator != null && book.creator!.isNotEmpty)
                  Text(
                    ' • ',
                    style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
              if (book.creator != null && book.creator!.isNotEmpty)
                Expanded(
                  child: Text(
                    book.creator!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          trailing: isDownloading
              ? SizedBox(
                  width: 32,
                  height: 32,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: downloadProgress > 0 ? downloadProgress : null,
                        strokeWidth: 3,
                      ),
                      if (downloadProgress > 0)
                        Text(
                          '${(downloadProgress * 100).toInt()}%',
                          style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                )
              : isCached
              ? FilledButton.tonal(
                  onPressed: () => _downloadAndAttach(book),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary.withAlpha(35),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, size: 14, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Attach',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                )
              : FilledButton.tonal(
                  onPressed: () => _downloadAndAttach(book),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Read', style: TextStyle(fontSize: 12)),
                ),
        );
      },
    );
  }
}
