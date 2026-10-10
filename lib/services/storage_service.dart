import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/download_item.dart';
import '../models/playlist.dart';
import '../models/youtube_search_item.dart';
import 'book_service.dart';

class StorageService extends ChangeNotifier {
  StorageService({Duration? debounceDuration})
      : _debounceDuration = debounceDuration ??
            (Platform.environment.containsKey('FLUTTER_TEST')
                ? Duration.zero
                : const Duration(milliseconds: 500));

  File? _storageFile;
  bool _initialized = false;
  Timer? _saveTimer;
  Completer<void>? _saveCompleter;
  Duration _debounceDuration;

  @visibleForTesting
  set debounceDuration(Duration duration) => _debounceDuration = duration;

  @visibleForTesting
  bool get hasPendingSave => _saveTimer != null;

  final List<YoutubeSearchItem> _favorites = [];
  final List<YoutubeSearchItem> _history = [];
  final List<Playlist> _playlists = [];
  final List<DownloadItem> _downloads = [];
  final List<String> _recentSearches = [];
  final Map<String, String> _trackPdfs = {};
  final Map<String, int> _trackPdfPages = {};
  final Map<String, String> _pdfTitles = {};
  final Map<String, int> _pdfPages = {};
  final Set<String> _detachedTracks = {};
  final Set<String> _unmatchedTitleCache = {};
  bool _autoplay = true;
  String _audioQuality = 'high'; // 'high' or 'saver'
  String _themeKey = 'emerald'; // 'emerald', 'cyan', 'amethyst', 'amber'
  late final ValueNotifier<String> _themeNotifier = ValueNotifier<String>(_themeKey);
  double _playbackSpeed = 1.0;

  ValueListenable<String> get themeNotifier => _themeNotifier;
  List<YoutubeSearchItem> get favorites => List.unmodifiable(_favorites);
  List<YoutubeSearchItem> get history => List.unmodifiable(_history);
  List<Playlist> get playlists => List.unmodifiable(_playlists);
  List<DownloadItem> get downloads => List.unmodifiable(_downloads);
  List<String> get recentSearches => List.unmodifiable(_recentSearches);
  bool get autoplay => _autoplay;
  String get audioQuality => _audioQuality;
  String get themeKey => _themeKey;
  double get playbackSpeed => _playbackSpeed;

  String? getTrackPdfPath(String trackId, {String? title}) {
    final direct = _trackPdfs[trackId];
    if (direct != null) {
      return direct;
    }

    if (_detachedTracks.contains(trackId)) {
      return null;
    }

    if (title != null && title.trim().isNotEmpty) {
      final cleanQuery = BookService.cleanAudiobookQuery(title);
      final matching = findMatchingPdfPath(cleanQuery);
      if (matching != null) {
        _trackPdfs[trackId] = matching;
        _scheduleSave();
        return matching;
      }
    }

    return null;
  }

  int getTrackPdfPage(String trackId, {String? pdfPath}) {
    if (_trackPdfPages.containsKey(trackId)) {
      return _trackPdfPages[trackId]!;
    }
    final path = pdfPath ?? _trackPdfs[trackId];
    if (path != null && _pdfPages.containsKey(path)) {
      return _pdfPages[path]!;
    }
    return 0;
  }

  Map<String, String> get trackPdfs => Map.unmodifiable(_trackPdfs);
  String? getPdfTitle(String filePath) => _pdfTitles[filePath];

  /// Finds any existing PDF attached to another part or track in the library.
  String? findMatchingPdfPath(String cleanTitleQuery) {
    if (cleanTitleQuery.trim().isEmpty) return null;
    final target = cleanTitleQuery.toLowerCase();
    if (_unmatchedTitleCache.contains(target)) return null;

    final targetTranslit = BookService.containsBengali(target)
        ? BookService.transliterateBengali(target).toLowerCase()
        : null;

    // 1. Check known PDF titles from _pdfTitles (string matching first, then disk check)
    for (final entry in _pdfTitles.entries) {
      final path = entry.key;
      final rawTitle = entry.value;
      final cleanTitle = BookService.cleanAudiobookQuery(rawTitle).toLowerCase();
      var matches = cleanTitle.isNotEmpty &&
          (cleanTitle == target ||
              cleanTitle.contains(target) ||
              target.contains(cleanTitle));

      if (!matches && (targetTranslit != null || BookService.containsBengali(cleanTitle))) {
        final t1 = targetTranslit ?? BookService.transliterateBengali(target).toLowerCase();
        final t2 = BookService.transliterateBengali(cleanTitle).toLowerCase();
        if (t1.isNotEmpty && (t1 == t2 || t1.contains(t2) || t2.contains(t1))) {
          matches = true;
        }
      }

      if (matches && File(path).existsSync()) {
        return path;
      }
    }

    // 2. Check all tracks in favorites, history, playlists
    final allItems = <YoutubeSearchItem>[
      ..._history,
      ..._favorites,
      for (final p in _playlists) ...p.items,
    ];

    for (final item in allItems) {
      final path = _trackPdfs[item.id];
      if (path == null) continue;

      final otherClean = BookService.cleanAudiobookQuery(item.title).toLowerCase();
      var matches = otherClean.isNotEmpty &&
          (otherClean == target ||
              otherClean.contains(target) ||
              target.contains(otherClean));

      if (!matches && (targetTranslit != null || BookService.containsBengali(otherClean))) {
        final t1 = targetTranslit ?? BookService.transliterateBengali(target).toLowerCase();
        final t2 = BookService.transliterateBengali(otherClean).toLowerCase();
        if (t1.isNotEmpty && (t1 == t2 || t1.contains(t2) || t2.contains(t1))) {
          matches = true;
        }
      }

      if (matches && File(path).existsSync()) {
        final displayTitle = BookService.cleanAudiobookTitle(item.title);
        _pdfTitles[path] = BookService.sanitizeBookTitle(
          _pdfTitles[path],
          fallbackTitle: displayTitle,
        );
        return path;
      }
    }

    // 3. Check by file names
    for (final path in _trackPdfs.values) {
      final name = path.split(Platform.pathSeparator).last.replaceAll('.pdf', '').toLowerCase();
      if (name.contains(target) || target.contains(name)) {
        if (File(path).existsSync()) {
          return path;
        }
      }
    }

    _unmatchedTitleCache.add(target);
    return null;
  }
  bool get isInitialized => _initialized;

  Future<void> init({File? overrideFile, Duration? debounceDuration}) async {
    if (_initialized) return;
    if (debounceDuration != null) {
      _debounceDuration = debounceDuration;
    } else if (overrideFile != null) {
      _debounceDuration = Duration.zero;
    }
    if (overrideFile != null) {
      _storageFile = overrideFile;
    } else {
      try {
        final dir = await getApplicationDocumentsDirectory();
        _storageFile = File('${dir.path}/shuno_data.json');
      } catch (e) {
        if (kDebugMode) debugPrint('Could not get app documents directory: $e');
      }
    }

    await _loadFromDisk();
    _initialized = true;
    notifyListeners();
  }

  Future<void> _loadFromDisk() async {
    final file = _storageFile;
    if (file == null || !await file.exists()) return;

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return;
      final data = jsonDecode(content) as Map<String, dynamic>;

      _favorites.clear();
      if (data['favorites'] is List) {
        for (final item in data['favorites'] as List) {
          _favorites.add(
            YoutubeSearchItem.fromJson(item as Map<String, dynamic>),
          );
        }
      }

      _history.clear();
      if (data['history'] is List) {
        for (final item in data['history'] as List) {
          _history.add(
            YoutubeSearchItem.fromJson(item as Map<String, dynamic>),
          );
        }
      }

      _playlists.clear();
      if (data['playlists'] is List) {
        for (final item in data['playlists'] as List) {
          _playlists.add(Playlist.fromJson(item as Map<String, dynamic>));
        }
      }

      _downloads.clear();
      if (data['downloads'] is List) {
        for (final item in data['downloads'] as List) {
          _downloads.add(DownloadItem.fromJson(item as Map<String, dynamic>));
        }
      }

      _recentSearches.clear();
      if (data['recentSearches'] is List) {
        for (final item in data['recentSearches'] as List) {
          if (item is String && item.trim().isNotEmpty) {
            _recentSearches.add(item.trim());
          }
        }
      }

      if (data['autoplay'] is bool) {
        _autoplay = data['autoplay'] as bool;
      }
      if (data['audioQuality'] is String) {
        _audioQuality = data['audioQuality'] as String;
      }
      if (data['themeKey'] is String) {
        _themeKey = data['themeKey'] as String;
        _themeNotifier.value = _themeKey;
      }
      if (data['playbackSpeed'] is num) {
        _playbackSpeed = (data['playbackSpeed'] as num).toDouble();
      }

      _trackPdfs.clear();
      if (data['trackPdfs'] is Map) {
        (data['trackPdfs'] as Map).forEach((k, v) {
          if (k is String && v is String) {
            _trackPdfs[k] = v;
          }
        });
      }

      _trackPdfPages.clear();
      if (data['trackPdfPages'] is Map) {
        (data['trackPdfPages'] as Map).forEach((k, v) {
          if (k is String && v is int) {
            _trackPdfPages[k] = v;
          }
        });
      }

      _pdfTitles.clear();
      if (data['pdfTitles'] is Map) {
        (data['pdfTitles'] as Map).forEach((k, v) {
          if (k is String && v is String) {
            _pdfTitles[k] = v;
          }
        });
      }

      _pdfPages.clear();
      if (data['pdfPages'] is Map) {
        (data['pdfPages'] as Map).forEach((k, v) {
          if (k is String && v is int) {
            _pdfPages[k] = v;
          }
        });
      }

      _detachedTracks.clear();
      if (data['detachedTracks'] is List) {
        for (final item in data['detachedTracks'] as List) {
          if (item is String) {
            _detachedTracks.add(item);
          }
        }
      }

      // Migrate any existing PDFs residing in temporary cache directories to persistent books directory
      if (_trackPdfs.isNotEmpty) {
        try {
          final baseDir = await getApplicationDocumentsDirectory();
          final booksDir = Directory('${baseDir.path}/books');
          for (final entry in _trackPdfs.entries.toList()) {
            final oldPath = entry.value;
            if (oldPath.contains('/cache/') ||
                oldPath.contains('${Platform.pathSeparator}cache${Platform.pathSeparator}')) {
              final oldFile = File(oldPath);
              if (oldFile.existsSync()) {
                if (!booksDir.existsSync()) {
                  booksDir.createSync(recursive: true);
                }
                final fileName = oldPath.split(Platform.pathSeparator).last;
                final safeName = fileName.replaceAll(RegExp(r'[^\w\.\-]'), '_');
                final newPath =
                    '${booksDir.path}/local_${DateTime.now().millisecondsSinceEpoch}_$safeName';
                oldFile.copySync(newPath);
                _trackPdfs[entry.key] = newPath;
                if (_pdfTitles.containsKey(oldPath)) {
                  _pdfTitles[newPath] = _pdfTitles[oldPath]!;
                  _pdfTitles.remove(oldPath);
                }
              }
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading storage: $e');
    }
  }

  Future<void> _saveToDisk() async {
    final file = _storageFile;
    if (file == null) return;

    try {
      final data = {
        'favorites': _favorites.map((e) => e.toJson()).toList(),
        'history': _history.map((e) => e.toJson()).toList(),
        'playlists': _playlists.map((e) => e.toJson()).toList(),
        'downloads': _downloads.map((e) => e.toJson()).toList(),
        'recentSearches': _recentSearches,
        'autoplay': _autoplay,
        'audioQuality': _audioQuality,
        'themeKey': _themeKey,
        'playbackSpeed': _playbackSpeed,
        'trackPdfs': _trackPdfs,
        'trackPdfPages': _trackPdfPages,
        'pdfTitles': _pdfTitles,
        'pdfPages': _pdfPages,
        'detachedTracks': _detachedTracks.toList(),
      };
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (e) {
      if (kDebugMode) debugPrint('Error saving storage: $e');
    }
  }

  Future<void> _scheduleSave({bool immediate = false}) {
    if (immediate || _debounceDuration == Duration.zero) {
      return flushPendingSave();
    }

    _saveTimer?.cancel();
    final completer = _saveCompleter ??= Completer<void>();
    _saveTimer = Timer(_debounceDuration, () async {
      _saveTimer = null;
      final currentCompleter = _saveCompleter;
      _saveCompleter = null;
      try {
        await _saveToDisk();
        if (currentCompleter != null && !currentCompleter.isCompleted) {
          currentCompleter.complete();
        }
      } catch (e) {
        if (currentCompleter != null && !currentCompleter.isCompleted) {
          currentCompleter.completeError(e);
        }
      }
    });
    return completer.future;
  }

  Future<void> flushPendingSave() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final currentCompleter = _saveCompleter;
    _saveCompleter = null;
    try {
      await _saveToDisk();
      if (currentCompleter != null && !currentCompleter.isCompleted) {
        currentCompleter.complete();
      }
    } catch (e) {
      if (currentCompleter != null && !currentCompleter.isCompleted) {
        currentCompleter.completeError(e);
      }
    }
  }

  @override
  void dispose() {
    flushPendingSave();
    super.dispose();
  }

  Future<void> setThemeKey(String key) async {
    if (_themeKey == key) return;
    _themeKey = key;
    _themeNotifier.value = key;
    notifyListeners();
    await _scheduleSave();
  }

  // --- Favorites ---
  bool isFavorite(String videoId) {
    return _favorites.any((item) => item.id == videoId);
  }

  Future<void> toggleFavorite(YoutubeSearchItem item) async {
    final index = _favorites.indexWhere((e) => e.id == item.id);
    if (index >= 0) {
      _favorites.removeAt(index);
    } else {
      _favorites.insert(0, item);
    }
    notifyListeners();
    await _scheduleSave();
  }

  // --- History ---
  Future<void> addToHistory(YoutubeSearchItem item) async {
    _history.removeWhere((e) => e.id == item.id);
    _history.insert(0, item);
    if (_history.length > 100) {
      _history.removeRange(100, _history.length);
    }
    notifyListeners();
    await _scheduleSave();
  }

  Future<void> clearHistory() async {
    _history.clear();
    notifyListeners();
    await _scheduleSave();
  }

  // --- Playlists ---
  Future<Playlist> createPlaylist(
    String title, [
    List<YoutubeSearchItem>? items,
  ]) async {
    final playlist = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title.trim(),
      items: items != null ? List.of(items) : [],
    );
    _playlists.add(playlist);
    notifyListeners();
    await _scheduleSave();
    return playlist;
  }

  Future<void> deletePlaylist(String id) async {
    _playlists.removeWhere((p) => p.id == id);
    notifyListeners();
    await _scheduleSave();
  }

  Future<void> renamePlaylist(String id, String newTitle) async {
    final index = _playlists.indexWhere((p) => p.id == id);
    if (index >= 0) {
      _playlists[index].title = newTitle.trim();
      notifyListeners();
      await _scheduleSave();
    }
  }

  Future<bool> addTrackToPlaylist(
    String playlistId,
    YoutubeSearchItem item,
  ) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index >= 0) {
      if (!_playlists[index].items.any((e) => e.id == item.id)) {
        _playlists[index].items.add(item);
        notifyListeners();
        await _scheduleSave();
        return true;
      }
    }
    return false;
  }

  Future<void> removeTrackFromPlaylist(
    String playlistId,
    String videoId,
  ) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index >= 0) {
      _playlists[index].items.removeWhere((e) => e.id == videoId);
      notifyListeners();
      await _scheduleSave();
    }
  }

  Future<void> reorderPlaylistTracks(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index >= 0) {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final items = _playlists[index].items;
      if (oldIndex >= 0 &&
          oldIndex < items.length &&
          newIndex >= 0 &&
          newIndex < items.length) {
        final item = items.removeAt(oldIndex);
        items.insert(newIndex, item);
        notifyListeners();
        await _scheduleSave();
      }
    }
  }

  Future<int> addTracksToPlaylist(
    String playlistId,
    List<YoutubeSearchItem> items,
  ) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index >= 0) {
      int added = 0;
      for (final item in items) {
        if (!_playlists[index].items.any((e) => e.id == item.id)) {
          _playlists[index].items.add(item);
          added++;
        }
      }
      if (added > 0) {
        notifyListeners();
        await _scheduleSave();
      }
      return added;
    }
    return 0;
  }

  // --- Downloads ---
  bool isDownloaded(String videoId) {
    return _downloads.any((d) => d.item.id == videoId);
  }

  DownloadItem? getDownload(String videoId) {
    try {
      return _downloads.firstWhere((d) => d.item.id == videoId);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDownload(DownloadItem download) async {
    _downloads.removeWhere((d) => d.item.id == download.item.id);
    _downloads.insert(0, download);
    notifyListeners();
    await _scheduleSave();
  }

  Future<void> removeDownload(String videoId) async {
    _downloads.removeWhere((d) => d.item.id == videoId);
    notifyListeners();
    await _scheduleSave();
  }

  Future<void> updatePlaybackPosition(String videoId, Duration position) async {
    final index = _downloads.indexWhere((d) => d.item.id == videoId);
    if (index >= 0) {
      final current = _downloads[index];
      // Only write if position changed meaningfully (> 1 sec)
      if ((current.lastPositionMs - position.inMilliseconds).abs() > 1000) {
        _downloads[index] = current.copyWith(
          lastPositionMs: position.inMilliseconds,
          lastPlayedAt: DateTime.now(),
        );
        notifyListeners();
        await _scheduleSave();
      }
    }
  }

  Future<void> clearPlaybackPosition(String videoId) async {
    final index = _downloads.indexWhere((d) => d.item.id == videoId);
    if (index >= 0) {
      _downloads[index] = _downloads[index].copyWith(
        lastPositionMs: 0,
        lastPlayedAt: null,
      );
      notifyListeners();
      await _scheduleSave();
    }
  }

  // --- Recent Searches ---
  Future<void> addRecentSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _recentSearches.removeWhere((q) => q.toLowerCase() == trimmed.toLowerCase());
    _recentSearches.insert(0, trimmed);
    if (_recentSearches.length > 20) {
      _recentSearches.removeRange(20, _recentSearches.length);
    }
    notifyListeners();
    await _scheduleSave();
  }

  Future<void> removeRecentSearch(String query) async {
    _recentSearches.removeWhere((q) => q == query);
    notifyListeners();
    await _scheduleSave();
  }

  Future<void> clearRecentSearches() async {
    _recentSearches.clear();
    notifyListeners();
    await _scheduleSave();
  }

  // --- Settings ---
  Future<void> setAutoplay(bool enabled) async {
    _autoplay = enabled;
    notifyListeners();
    await _scheduleSave();
  }

  Future<void> setAudioQuality(String quality) async {
    _audioQuality = quality;
    notifyListeners();
    await _scheduleSave();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    if (speed <= 0 || _playbackSpeed == speed) return;
    _playbackSpeed = speed;
    notifyListeners();
    await _scheduleSave();
  }

  Future<void> setTrackPdf(String trackId, String filePath, {String? title}) async {
    var resolvedPath = filePath;

    // Safety: If filePath points to a temporary cache location, make a permanent copy
    try {
      if (resolvedPath.contains('${Platform.pathSeparator}cache${Platform.pathSeparator}') ||
          resolvedPath.contains('/cache/')) {
        final file = File(resolvedPath);
        if (file.existsSync()) {
          final baseDir = await getApplicationDocumentsDirectory();
          final booksDir = Directory('${baseDir.path}/books');
          if (!await booksDir.exists()) {
            await booksDir.create(recursive: true);
          }
          final fileName = resolvedPath.split(Platform.pathSeparator).last;
          final safeName = fileName.replaceAll(RegExp(r'[^\w\.\-]'), '_');
          final permPath =
              '${booksDir.path}/local_${DateTime.now().millisecondsSinceEpoch}_$safeName';
          await file.copy(permPath);
          if (await File(permPath).exists()) {
            resolvedPath = permPath;
          }
        }
      }
    } catch (_) {}

    _trackPdfs[trackId] = resolvedPath;
    _detachedTracks.remove(trackId);
    _unmatchedTitleCache.clear();

    if (title != null && title.trim().isNotEmpty) {
      final cleanTitle = BookService.sanitizeBookTitle(title);
      _pdfTitles[resolvedPath] = cleanTitle;

      // Auto-associate with matching sibling parts in history, favorites, playlists
      final query = BookService.cleanAudiobookQuery(cleanTitle).toLowerCase();
      if (query.isNotEmpty) {
        final allItems = <YoutubeSearchItem>[
          ..._history,
          ..._favorites,
          for (final p in _playlists) ...p.items,
        ];
        for (final item in allItems) {
          if (item.id != trackId && !_detachedTracks.contains(item.id)) {
            final otherQuery =
                BookService.cleanAudiobookQuery(item.title).toLowerCase();
            if (otherQuery.isNotEmpty &&
                (otherQuery == query ||
                    otherQuery.contains(query) ||
                    query.contains(otherQuery))) {
              _trackPdfs[item.id] = resolvedPath;
            }
          }
        }
      }
    }

    notifyListeners();
    await _scheduleSave();
  }

  Future<void> setPdfTitle(String filePath, String title) async {
    if (title.trim().isEmpty) return;
    _pdfTitles[filePath] = BookService.sanitizeBookTitle(title);
    notifyListeners();
    await _scheduleSave();
  }

  Future<void> purgePdf(String filePath) async {
    _trackPdfs.removeWhere((_, path) => path == filePath);
    _pdfTitles.remove(filePath);
    _pdfPages.remove(filePath);
    _unmatchedTitleCache.clear();
    notifyListeners();
    await _scheduleSave(immediate: true);
  }

  Future<void> setTrackPdfPage(String trackId, int page, {String? pdfPath}) async {
    _trackPdfPages[trackId] = page;
    final path = pdfPath ?? _trackPdfs[trackId];
    if (path != null) {
      _pdfPages[path] = page;
    }
    await _scheduleSave();
  }

  Future<void> removeTrackPdf(String trackId) async {
    _trackPdfs.remove(trackId);
    _trackPdfPages.remove(trackId);
    _detachedTracks.add(trackId);
    notifyListeners();
    await _scheduleSave();
  }

  Future<void> clearAllData() async {
    _favorites.clear();
    _history.clear();
    _playlists.clear();
    _downloads.clear();
    _recentSearches.clear();
    _trackPdfs.clear();
    _trackPdfPages.clear();
    _pdfTitles.clear();
    _pdfPages.clear();
    _detachedTracks.clear();
    _unmatchedTitleCache.clear();
    _themeNotifier.value = 'emerald';
    _playbackSpeed = 1.0;
    notifyListeners();
    await flushPendingSave();
  }
}
