import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/download_item.dart';
import '../models/playlist.dart';
import '../models/youtube_search_item.dart';
import 'book_service.dart';

class StorageService extends ChangeNotifier {
  File? _storageFile;
  bool _initialized = false;

  final List<YoutubeSearchItem> _favorites = [];
  final List<YoutubeSearchItem> _history = [];
  final List<Playlist> _playlists = [];
  final List<DownloadItem> _downloads = [];
  final List<String> _recentSearches = [];
  final Map<String, String> _trackPdfs = {};
  final Map<String, int> _trackPdfPages = {};
  final Map<String, String> _pdfTitles = {};
  bool _autoplay = true;
  String _audioQuality = 'high'; // 'high' or 'saver'
  String _themeKey = 'emerald'; // 'emerald', 'cyan', 'amethyst', 'amber'
  double _playbackSpeed = 1.0;

  List<YoutubeSearchItem> get favorites => List.unmodifiable(_favorites);
  List<YoutubeSearchItem> get history => List.unmodifiable(_history);
  List<Playlist> get playlists => List.unmodifiable(_playlists);
  List<DownloadItem> get downloads => List.unmodifiable(_downloads);
  List<String> get recentSearches => List.unmodifiable(_recentSearches);
  bool get autoplay => _autoplay;
  String get audioQuality => _audioQuality;
  String get themeKey => _themeKey;
  double get playbackSpeed => _playbackSpeed;
  String? getTrackPdfPath(String trackId) => _trackPdfs[trackId];
  int getTrackPdfPage(String trackId) => _trackPdfPages[trackId] ?? 0;
  Map<String, String> get trackPdfs => Map.unmodifiable(_trackPdfs);
  String? getPdfTitle(String filePath) => _pdfTitles[filePath];

  /// Finds any existing PDF attached to another part or track in the library.
  String? findMatchingPdfPath(String cleanTitleQuery) {
    if (cleanTitleQuery.trim().isEmpty) return null;
    final target = cleanTitleQuery.toLowerCase();

    // Check all tracks in favorites, history, playlists
    final allItems = <YoutubeSearchItem>[
      ..._history,
      ..._favorites,
      for (final p in _playlists) ...p.items,
    ];

    for (final item in allItems) {
      final path = _trackPdfs[item.id];
      if (path != null && File(path).existsSync()) {
        final otherClean = BookService.cleanAudiobookQuery(item.title).toLowerCase();
        if (otherClean.isNotEmpty &&
            (otherClean == target ||
                otherClean.contains(target) ||
                target.contains(otherClean))) {
          final displayTitle = BookService.cleanAudiobookTitle(item.title);
          _pdfTitles[path] = BookService.sanitizeBookTitle(
            _pdfTitles[path],
            fallbackTitle: displayTitle,
          );
          return path;
        }
      }
    }

    // Check by file names
    for (final path in _trackPdfs.values) {
      if (File(path).existsSync()) {
        final name = path.split(Platform.pathSeparator).last.replaceAll('.pdf', '').toLowerCase();
        if (name.contains(target) || target.contains(name)) {
          return path;
        }
      }
    }

    return null;
  }
  bool get isInitialized => _initialized;

  Future<void> init({File? overrideFile}) async {
    if (_initialized) return;
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
      };
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (e) {
      if (kDebugMode) debugPrint('Error saving storage: $e');
    }
  }

  Future<void> setThemeKey(String key) async {
    if (_themeKey == key) return;
    _themeKey = key;
    notifyListeners();
    await _saveToDisk();
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
    await _saveToDisk();
  }

  // --- History ---
  Future<void> addToHistory(YoutubeSearchItem item) async {
    _history.removeWhere((e) => e.id == item.id);
    _history.insert(0, item);
    if (_history.length > 100) {
      _history.removeRange(100, _history.length);
    }
    notifyListeners();
    await _saveToDisk();
  }

  Future<void> clearHistory() async {
    _history.clear();
    notifyListeners();
    await _saveToDisk();
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
    await _saveToDisk();
    return playlist;
  }

  Future<void> deletePlaylist(String id) async {
    _playlists.removeWhere((p) => p.id == id);
    notifyListeners();
    await _saveToDisk();
  }

  Future<void> renamePlaylist(String id, String newTitle) async {
    final index = _playlists.indexWhere((p) => p.id == id);
    if (index >= 0) {
      _playlists[index].title = newTitle.trim();
      notifyListeners();
      await _saveToDisk();
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
        await _saveToDisk();
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
      await _saveToDisk();
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
        await _saveToDisk();
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
        await _saveToDisk();
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
    await _saveToDisk();
  }

  Future<void> removeDownload(String videoId) async {
    _downloads.removeWhere((d) => d.item.id == videoId);
    notifyListeners();
    await _saveToDisk();
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
        await _saveToDisk();
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
      await _saveToDisk();
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
    await _saveToDisk();
  }

  Future<void> removeRecentSearch(String query) async {
    _recentSearches.removeWhere((q) => q == query);
    notifyListeners();
    await _saveToDisk();
  }

  Future<void> clearRecentSearches() async {
    _recentSearches.clear();
    notifyListeners();
    await _saveToDisk();
  }

  // --- Settings ---
  Future<void> setAutoplay(bool enabled) async {
    _autoplay = enabled;
    notifyListeners();
    await _saveToDisk();
  }

  Future<void> setAudioQuality(String quality) async {
    _audioQuality = quality;
    notifyListeners();
    await _saveToDisk();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    if (speed <= 0 || _playbackSpeed == speed) return;
    _playbackSpeed = speed;
    notifyListeners();
    await _saveToDisk();
  }

  Future<void> setTrackPdf(String trackId, String filePath, {String? title}) async {
    _trackPdfs[trackId] = filePath;
    if (title != null && title.trim().isNotEmpty) {
      _pdfTitles[filePath] = BookService.sanitizeBookTitle(title);
    }
    notifyListeners();
    await _saveToDisk();
  }

  Future<void> setPdfTitle(String filePath, String title) async {
    if (title.trim().isEmpty) return;
    _pdfTitles[filePath] = BookService.sanitizeBookTitle(title);
    notifyListeners();
    await _saveToDisk();
  }

  Future<void> purgePdf(String filePath) async {
    _trackPdfs.removeWhere((_, path) => path == filePath);
    _pdfTitles.remove(filePath);
    notifyListeners();
    await _saveToDisk();
  }

  Future<void> setTrackPdfPage(String trackId, int page) async {
    if (_trackPdfPages[trackId] == page) return;
    _trackPdfPages[trackId] = page;
    await _saveToDisk();
  }

  Future<void> removeTrackPdf(String trackId) async {
    _trackPdfs.remove(trackId);
    _trackPdfPages.remove(trackId);
    notifyListeners();
    await _saveToDisk();
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
    _playbackSpeed = 1.0;
    notifyListeners();
    await _saveToDisk();
  }
}
