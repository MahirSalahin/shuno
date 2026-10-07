import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../main.dart';
import 'storage_service.dart';

class ArchiveBookItem {
  const ArchiveBookItem({
    required this.id,
    required this.title,
    this.creator,
    this.pdfUrl,
    this.fileSize,
  });

  final String id;
  final String title;
  final String? creator;
  final String? pdfUrl;
  final int? fileSize;

  String get formattedSize {
    final bytes = fileSize;
    if (bytes == null || bytes <= 0) return '';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    final kb = bytes / 1024;
    return '${kb.toStringAsFixed(0)} KB';
  }
}

class BookDownloadTask {
  BookDownloadTask({
    required this.bookId,
    required this.title,
    this.targetTrackId,
    this.fallbackSeriesTitle,
    this.progress = 0.0,
    this.isCompleted = false,
    this.error,
    this.savedPath,
  });

  final String bookId;
  final String title;
  final String? targetTrackId;
  final String? fallbackSeriesTitle;
  double progress;
  bool isCompleted;
  String? error;
  String? savedPath;
}

class BookService extends ChangeNotifier {
  static final BookService _instance = BookService._internal();

  factory BookService({http.Client? httpClient}) {
    if (httpClient != null) {
      return BookService._internal(httpClient: httpClient);
    }
    return _instance;
  }

  BookService._internal({http.Client? httpClient})
      : _client = httpClient ?? http.Client();

  final http.Client _client;
  final Map<String, BookDownloadTask> _activeDownloads = {};

  BookDownloadTask? getDownloadTask(String bookId) => _activeDownloads[bookId];

  bool isDownloading(String bookId) {
    final task = _activeDownloads[bookId];
    return task != null && !task.isCompleted && task.error == null;
  }

  double getDownloadProgress(String bookId) =>
      _activeDownloads[bookId]?.progress ?? 0.0;

  /// Checks if a file path points to an existing, valid non-empty PDF (> 50 KB).
  static bool isPdfFileValid(String? path) {
    if (path == null || path.trim().isEmpty) return false;
    try {
      final file = File(path);
      return file.existsSync() && file.lengthSync() > 50 * 1024;
    } catch (_) {
      return false;
    }
  }

  /// Checks whether [text] contains any Bengali script characters.
  static bool containsBengali(String text) =>
      RegExp(r'[\u0980-\u09FF]').hasMatch(text);

  /// Transliterates Bengali text into Latin characters (e.g. "গাভী বিত্তান্ত" -> "gabhi bittanto").
  static String transliterateBengali(String text) {
    // Normalize decomposed forms and common Bengali Unicode variations
    var normalized = text
        .replaceAll('\u09AF\u09BC', '\u09DF') // য + ় -> য়
        .replaceAll('\u09A1\u09BC', '\u09DC') // ড + ় -> ড়
        .replaceAll('\u09A2\u09BC', '\u09DD') // ঢ + ় -> ঢ়
        .replaceAll('\u09BC', ''); // remove remaining orphan nukta

    const vowels = {
      'অ': 'o', 'আ': 'a', 'ই': 'i', 'ঈ': 'i', 'উ': 'u', 'ঊ': 'u',
      'ঋ': 'ri', 'এ': 'e', 'ঐ': 'oi', 'ও': 'o', 'ঔ': 'ou',
    };

    const vowelSigns = {
      'া': 'a', 'ি': 'i', 'ী': 'i', 'ু': 'u', 'ূ': 'u',
      'ৃ': 'ri', 'ে': 'e', 'ৈ': 'oi', 'ো': 'o', 'ৌ': 'ou',
    };

    const consonants = {
      'ক': 'k', 'খ': 'kh', 'গ': 'g', 'ঘ': 'gh', 'ঙ': 'ng',
      'চ': 'ch', 'ছ': 'ch', 'জ': 'j', 'ঝ': 'jh', 'ঞ': 'n',
      'ট': 't', 'ঠ': 'th', 'ড': 'd', 'ঢ': 'dh', 'ণ': 'n',
      'ত': 't', 'থ': 'th', 'দ': 'd', 'ধ': 'dh', 'ন': 'n',
      'প': 'p', 'ফ': 'f', 'ব': 'b', 'ভ': 'bh', 'ম': 'm',
      'য': 'j', 'র': 'r', 'ল': 'l', 'শ': 'sh', 'ষ': 'sh', 'স': 's', 'হ': 'h',
      '\u09DC': 'r', '\u09DD': 'rh', '\u09DF': 'y', 'ৎ': 't',
      'ং': 'ng', 'ঃ': 'h',
    };

    final runes = normalized.runes.toList();
    final sb = StringBuffer();

    for (int i = 0; i < runes.length; i++) {
      final char = String.fromCharCode(runes[i]);

      if (char == 'ঁ') {
        // Nasal candrabindu
        sb.write('n');
        continue;
      }

      if (vowels.containsKey(char)) {
        sb.write(vowels[char]);
      } else if (vowelSigns.containsKey(char)) {
        sb.write(vowelSigns[char]);
      } else if (consonants.containsKey(char)) {
        sb.write(consonants[char]);
        final hasNext = i + 1 < runes.length;
        if (hasNext) {
          final nextChar = String.fromCharCode(runes[i + 1]);
          if (nextChar == '্') {
            // Virama / hasanta
            i++;
          } else if (!vowelSigns.containsKey(nextChar) &&
              consonants.containsKey(nextChar) &&
              nextChar != 'ঁ') {
            // Inherent vowel between consonants
            sb.write('a');
          }
        }
      } else {
        sb.write(char);
      }
    }

    var res = sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    // In Bengali words ending in 'nt', standard Latin representation ends in 'nto'
    if (res.endsWith('nt')) {
      res = '${res}o';
    }
    return res;
  }

  /// Extracts multiple candidate search queries from an audiobook title, including:
  /// - Clean book title (e.g. "গাভী বিত্তান্ত")
  /// - Book title + Bengali author (e.g. "গাভী বিত্তান্ত আহমদ ছফা")
  /// - Book title + English author (e.g. "গাভী বিত্তান্ত Ahmed Sofa")
  /// - Transliterated title (e.g. "gabhi bittanto")
  /// - Transliterated title + English author (e.g. "gabhi bittanto Ahmed Sofa")
  static List<String> extractSearchQueries(String title) {
    var clean = title.replaceAll(RegExp(r'\[.*?\]'), ' ').replaceAll(RegExp(r'\(.*?\)'), ' ');

    // Pre-clean fractions (like 1/6 or ৫/৮)
    clean = clean.replaceAll(RegExp(r'[0-9০-৯]+\s*/\s*[0-9০-৯]+'), ' ');

    final narratorNoisePatterns = [
      r'\bby\s+[A-Za-z0-9\u0980-\u09FF\s]+$',
      r'\b(narrat|narrator|narrated)\b(\s+by)?\s*[\w\u0980-\u09FF\s]*',
      r'(পাঠ|কণ্ঠ|আবৃত্তি|পরিবেশনা)(\s*:\s*|\s+[\w\u0980-\u09FF\s]+)',
      r'\bgolpokothon\b.*',
      r'\bsunday\s+suspense\b.*',
      r'\bmir\s+afsar\s+ali\b.*',
      r'\baudiobook\b',
      r'\baudio\s+book\b',
      r'\b(hq|hd|4k|unabridged|full|complete)\b',
    ];

    final partNoisePatterns = [
      r'chapter\s*[0-9০-৯]+(\s*(to|-)\s*[0-9০-৯]+)?',
      r'ch\s*[0-9০-৯]+',
      r'part\s*[0-9০-৯]+(\s*of\s*[0-9০-৯]+)?',
      r'episode\s*[0-9০-৯]+',
      r'ep\s*[0-9০-৯]+',
      r'(পর্ব|খণ্ড|ভাগ|অধ্যায়)\s*[0-9০-৯]+',
      r'^[0-9০-৯]+[\.:\)\-]\s*',
      r'নতুন\s+গল্প',
      r'নাটক',
      r'উপন্যাস',
    ];

    final rawSegments = clean
        .split(RegExp(r'[|•\-_—–]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final validSegments = <String>[];

    for (final seg in rawSegments) {
      var s = seg;
      bool isNarrator = false;
      for (final pat in narratorNoisePatterns) {
        if (RegExp(pat, caseSensitive: false).hasMatch(s)) {
          s = s.replaceAll(RegExp(pat, caseSensitive: false), ' ').trim();
          if (s.isEmpty || s.toLowerCase().startsWith('by ')) {
            isNarrator = true;
            break;
          }
        }
      }
      if (isNarrator) continue;

      for (final pat in partNoisePatterns) {
        s = s.replaceAll(RegExp(pat, caseSensitive: false), ' ');
      }
      s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

      if (s.isNotEmpty && s.length > 1 && !RegExp(r'^[0-9০-৯\s]+$').hasMatch(s)) {
        validSegments.add(s);
      }
    }

    final queries = <String>{};

    if (validSegments.isEmpty) {
      var fallback = clean;
      for (final pat in [...narratorNoisePatterns, ...partNoisePatterns]) {
        fallback = fallback.replaceAll(RegExp(pat, caseSensitive: false), ' ');
      }
      fallback = fallback.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (fallback.isNotEmpty) {
        queries.add(fallback);
        if (containsBengali(fallback)) {
          final t = transliterateBengali(fallback);
          if (t.isNotEmpty) queries.add(t);
        }
      }
      return queries.toList();
    }

    final primaryTitle = validSegments.first;
    queries.add(primaryTitle);

    String? bengaliAuthor;
    String? englishAuthor;

    for (int i = 1; i < validSegments.length; i++) {
      final seg = validSegments[i];
      if (containsBengali(seg)) {
        bengaliAuthor ??= seg;
      } else {
        englishAuthor ??= seg;
      }
    }

    if (bengaliAuthor != null) {
      queries.add('$primaryTitle $bengaliAuthor');
    }

    if (englishAuthor != null) {
      queries.add('$primaryTitle $englishAuthor');
    }

    if (containsBengali(primaryTitle)) {
      final translitTitle = transliterateBengali(primaryTitle);
      if (translitTitle.isNotEmpty) {
        queries.add(translitTitle);
        if (englishAuthor != null) {
          queries.add('$translitTitle $englishAuthor');
        }
        if (bengaliAuthor != null) {
          final translitAuthor = transliterateBengali(bengaliAuthor);
          if (translitAuthor.isNotEmpty) {
            queries.add('$translitTitle $translitAuthor');
          }
        }
      }
    }

    return queries.where((q) => q.trim().length > 1).toList();
  }

  /// Cleans typical YouTube audiobook title noise to extract a clean book and author query for search.
  static String cleanAudiobookQuery(String title) {
    final candidates = extractSearchQueries(title);
    if (candidates.isNotEmpty) {
      return candidates.first;
    }

    var clean = title;
    clean = clean.replaceAll(RegExp(r'\[.*?\]'), ' ');
    clean = clean.replaceAll(RegExp(r'\(.*?\)'), ' ');
    clean = clean.replaceAll(RegExp(r'[0-9০-৯]+\s*/\s*[0-9০-৯]+'), ' ');

    final noisePatterns = [
      r'full\s+audiobook',
      r'complete\s+audiobook',
      r'audiobook',
      r'audio\s+book',
      r'\b(hq|hd|4k|unabridged)\b',
      r'golpokothon',
      r'sunday\s+suspense',
      r'special\s+edition',
      r'official\s+audio',
      r'chapter\s*[0-9০-৯]+(\s*(to|-)\s*[0-9০-৯]+)?',
      r'ch\s*[0-9০-৯]+',
      r'part\s*[0-9০-৯]+',
      r'episode\s*[0-9০-৯]+',
      r'ep\s*[0-9০-৯]+',
      r'(পর্ব|খণ্ড|ভাগ|অধ্যায়)\s*[0-9০-৯]+',
      r'নতুন\s+গল্প',
      r'নাটক',
      r'উপন্যাস',
      r'গল্প',
    ];

    for (final pattern in noisePatterns) {
      clean = clean.replaceAll(RegExp(pattern, caseSensitive: false), ' ');
    }

    clean = clean.replaceAll(RegExp(r'[|•\-_\/]+'), ' ');
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.isNotEmpty ? clean : title.trim();
  }

  /// Cleans an audiobook title for human-readable display (e.g. "গাভী বিত্তান্ত | আহমদ ছফা"),
  /// removing episode/part numbers and noise while keeping the book & author structure.
  static String cleanAudiobookTitle(String title) {
    var clean = title;
    clean = clean.replaceAll(RegExp(r'\[.*?\]'), ' ');
    clean = clean.replaceAll(RegExp(r'\(.*?\)'), ' ');
    clean = clean.replaceAll(RegExp(r'[0-9০-৯]+\s*/\s*[0-9০-৯]+'), ' ');

    final noisePatterns = [
      r'full\s+audiobook',
      r'complete\s+audiobook',
      r'audiobook',
      r'audio\s+book',
      r'\b(hq|hd|4k|unabridged)\b',
      r'golpokothon(\s+by\s+\w+)?',
      r'sunday\s+suspense',
      r'special\s+edition',
      r'official\s+audio',
      r'\bby\s+[A-Za-z0-9\u0980-\u09FF\s]+$',
      r'(পর্ব|খণ্ড|ভাগ|অধ্যায়)\s*[0-9০-৯]+',
      r'chapter\s*[0-9০-৯]+(\s*(to|-)\s*[0-9০-৯]+)?',
      r'ch\s*[0-9০-৯]+',
      r'part\s*[0-9০-৯]+',
      r'episode\s*[0-9০-৯]+',
      r'ep\s*[0-9০-৯]+',
      r'নতুন\s+গল্প',
      r'নাটক',
    ];

    for (final pattern in noisePatterns) {
      clean = clean.replaceAll(RegExp(pattern, caseSensitive: false), ' ');
    }

    final parts = clean
        .split(RegExp(r'[|•]+'))
        .map((p) => p.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((p) => p.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return title.trim();
    }

    if (parts.length > 2) {
      clean = '${parts[0]} | ${parts[1]}';
    } else {
      clean = parts.join(' | ');
    }

    return clean.trim();
  }

  /// Cleans an Internet Archive book title or filename into a human-friendly book title.
  static String sanitizeBookTitle(String? title, {String? fallbackTitle}) {
    if (title == null || title.trim().isEmpty) {
      return fallbackTitle?.trim() ?? '';
    }

    var clean = title.trim();
    clean = clean.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    clean = clean.replaceAll(
      RegExp(r'^(in\.ernet\.dli\.[0-9.]+|dli\.[0-9.]+|ark:\/[0-9/]+)\s*[-_:]*\s*', caseSensitive: false),
      '',
    );
    clean = clean.replaceAll('_', ' ');
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();

    final isRawId = RegExp(r'^[0-9.\-_]+$').hasMatch(clean) ||
        clean.toLowerCase().contains('in.ernet.dli') ||
        clean.length < 2;

    if (isRawId) {
      if (fallbackTitle != null && fallbackTitle.trim().isNotEmpty) {
        return fallbackTitle.trim();
      }
    }

    return clean.isNotEmpty ? clean : (fallbackTitle?.trim() ?? '');
  }

  /// Searches Internet Archive for texts/books matching [query].
  Future<List<ArchiveBookItem>> searchArchive(String query) async {
    final cleaned = query.trim();
    if (cleaned.isEmpty) return [];

    try {
      final encoded = Uri.encodeComponent('$cleaned AND mediatype:texts');
      final url = Uri.parse(
        'https://archive.org/advancedsearch.php?q=$encoded&fl[]=identifier,title,creator,downloads&sort[]=downloads+desc&rows=15&output=json',
      );

      final response = await _client.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final docs = data['response']?['docs'] as List? ?? [];

      return docs.map((doc) {
        final id = doc['identifier'] as String? ?? '';
        final title = doc['title'] as String? ?? id;
        final creator = doc['creator'] as String?;
        return ArchiveBookItem(
          id: id,
          title: title,
          creator: creator,
        );
      }).where((b) => b.id.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  /// Searches Internet Archive across multiple candidate queries in parallel,
  /// merging results and removing duplicates by identifier.
  Future<List<ArchiveBookItem>> searchArchiveMulti(List<String> queries) async {
    if (queries.isEmpty) return [];

    final distinctQueries = queries
        .map((q) => q.trim())
        .where((q) => q.isNotEmpty)
        .toSet()
        .take(4)
        .toList();

    if (distinctQueries.isEmpty) return [];

    try {
      final resultsLists = await Future.wait(
        distinctQueries.map((q) => searchArchive(q)),
      );

      final seen = <String>{};
      final merged = <ArchiveBookItem>[];
      for (final list in resultsLists) {
        for (final item in list) {
          if (seen.add(item.id)) {
            merged.add(item);
          }
        }
      }
      return merged;
    } catch (_) {
      return [];
    }
  }

  /// Resolves the actual PDF URL and file size for an Internet Archive item.
  Future<String?> resolvePdfUrl(String identifier) async {
    try {
      final url = Uri.parse('https://archive.org/metadata/$identifier/files');
      final res = await _client.get(url).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final files = data['result'] as List? ?? [];

      final pdfFiles = files.where((f) {
        final name = (f['name'] as String? ?? '').toLowerCase();
        return name.endsWith('.pdf');
      }).toList();

      if (pdfFiles.isEmpty) {
        return 'https://archive.org/download/$identifier/$identifier.pdf';
      }

      final validPdfs = pdfFiles.where((f) {
        final size = int.tryParse(f['size']?.toString() ?? '0') ?? 0;
        return size > 50 * 1024;
      }).toList();

      final candidateList = validPdfs.isNotEmpty ? validPdfs : pdfFiles;

      candidateList.sort((a, b) {
        final nameA = (a['name'] as String? ?? '').toLowerCase();
        final nameB = (b['name'] as String? ?? '').toLowerCase();
        final formatA = (a['format'] as String? ?? '').toLowerCase();
        final formatB = (b['format'] as String? ?? '').toLowerCase();
        final sizeA = int.tryParse(a['size']?.toString() ?? '0') ?? 0;
        final sizeB = int.tryParse(b['size']?.toString() ?? '0') ?? 0;

        final isTextA = formatA.contains('text') || nameA.contains('_text') || nameA.contains('_bw');
        final isTextB = formatB.contains('text') || nameB.contains('_text') || nameB.contains('_bw');
        if (isTextA && !isTextB) return -1;
        if (!isTextA && isTextB) return 1;

        if (sizeA > 0 && sizeB > 0) {
          return sizeA.compareTo(sizeB);
        }
        return 0;
      });

      final bestName = candidateList.first['name'] as String;
      return 'https://archive.org/download/$identifier/${Uri.encodeComponent(bestName)}';
    } catch (_) {
      return 'https://archive.org/download/$identifier/$identifier.pdf';
    }
  }

  /// Downloads an Archive PDF file atomically to the local books directory:
  /// Writes chunks to `.part` first, verifies valid size (> 50KB),
  /// and only renames to `.pdf` upon 100% completion.
  Future<String?> downloadPdf(
    String pdfUrl,
    String filename, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final baseDir = await getApplicationDocumentsDirectory();
      final booksDir = Directory('${baseDir.path}/books');
      if (!await booksDir.exists()) {
        await booksDir.create(recursive: true);
      }

      final safeName = filename.replaceAll(RegExp(r'[^\w\.\-]'), '_');
      final finalFile = File('${booksDir.path}/$safeName.pdf');
      final partFile = File('${booksDir.path}/$safeName.pdf.part');

      // If already downloaded and valid (> 50KB), reuse it!
      if (await finalFile.exists() && await finalFile.length() > 50 * 1024) {
        onProgress?.call(1.0);
        return finalFile.path;
      }

      // If broken/truncated file exists, remove it
      if (await finalFile.exists()) {
        try {
          await finalFile.delete();
        } catch (_) {}
      }

      // Remove leftover .part file if any
      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }

      final req = http.Request('GET', Uri.parse(pdfUrl));
      req.headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';
      req.headers['Accept'] = 'application/pdf,*/*';
      final response = await _client.send(req);
      if (response.statusCode != 200) {
        if (await partFile.exists()) try { await partFile.delete(); } catch (_) {}
        return null;
      }

      final contentLength = response.contentLength ?? 0;
      var received = 0;
      final sink = partFile.openWrite();

      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (contentLength > 0 && onProgress != null) {
            onProgress(received / contentLength);
          }
        }
        await sink.flush();
        await sink.close();
      } catch (e) {
        try {
          await sink.close();
          if (await partFile.exists()) await partFile.delete();
        } catch (_) {}
        return null;
      }

      // Verify file is complete and non-empty (> 50KB)
      if (await partFile.exists() && await partFile.length() > 50 * 1024) {
        await partFile.rename(finalFile.path);
        onProgress?.call(1.0);
        return finalFile.path;
      } else {
        if (await partFile.exists()) try { await partFile.delete(); } catch (_) {}
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  /// Starts a managed background download that survives sheet dismissals and navigation.
  /// When complete, atomically saves the PDF, binds it to [targetTrackId] in [storage],
  /// and notifies listeners and global UI.
  Future<String?> startBackgroundDownload({
    required ArchiveBookItem book,
    String? targetTrackId,
    String? fallbackSeriesTitle,
    StorageService? storage,
  }) async {
    if (isDownloading(book.id)) {
      return null;
    }

    final task = BookDownloadTask(
      bookId: book.id,
      title: book.title,
      targetTrackId: targetTrackId,
      fallbackSeriesTitle: fallbackSeriesTitle,
    );
    _activeDownloads[book.id] = task;
    notifyListeners();

    try {
      final pdfUrl = await resolvePdfUrl(book.id);
      if (pdfUrl == null) {
        task.error = 'Could not resolve PDF link';
        notifyListeners();
        return null;
      }

      final savedPath = await downloadPdf(
        pdfUrl,
        book.id,
        onProgress: (p) {
          task.progress = p;
          notifyListeners();
        },
      );

      if (savedPath != null) {
        task.isCompleted = true;
        task.savedPath = savedPath;

        if (targetTrackId != null && storage != null) {
          final cleanTitle = sanitizeBookTitle(
            book.title,
            fallbackTitle: fallbackSeriesTitle,
          );
          await storage.setTrackPdf(targetTrackId, savedPath, title: cleanTitle);
        }

        notifyListeners();

        // Inform user via global snackbar
        final cleanTitle = sanitizeBookTitle(
          book.title,
          fallbackTitle: fallbackSeriesTitle,
        );
        rootScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('Attached "$cleanTitle" to track'),
            duration: const Duration(seconds: 3),
          ),
        );

        return savedPath;
      } else {
        task.error = 'Download failed';
        notifyListeners();
        return null;
      }
    } catch (e) {
      task.error = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Allows picking a local PDF file from the user's phone storage.
  Future<String?> pickLocalPdf() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (files.isNotEmpty) {
        return files.first.path;
      }
    } catch (_) {}
    return null;
  }

  /// Returns the local path if this archive book is already downloaded and valid, or null.
  Future<String?> getDownloadedPdfPath(String identifier) async {
    try {
      final baseDir = await getApplicationDocumentsDirectory();
      final safeName = identifier.replaceAll(RegExp(r'[^\w\.\-]'), '_');
      final file = File('${baseDir.path}/books/$safeName.pdf');
      if (await file.exists()) {
        if (await file.length() > 50 * 1024) {
          return file.path;
        } else {
          // Clean up corrupt stub
          try {
            await file.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return null;
  }

  /// Lists all valid downloaded PDF files (> 50KB) in the local books directory.
  Future<List<File>> getDownloadedBooks() async {
    try {
      final baseDir = await getApplicationDocumentsDirectory();
      final booksDir = Directory('${baseDir.path}/books');
      if (await booksDir.exists()) {
        final list = await booksDir
            .list()
            .where((entity) =>
                entity is File &&
                entity.path.toLowerCase().endsWith('.pdf') &&
                entity.lengthSync() > 50 * 1024)
            .cast<File>()
            .toList();
        list.sort((a, b) {
          try {
            return b.lastModifiedSync().compareTo(a.lastModifiedSync());
          } catch (_) {
            return 0;
          }
        });
        return list;
      }
    } catch (_) {}
    return [];
  }

  /// Deletes a downloaded PDF file from device storage, returning true if deleted.
  Future<bool> deleteDownloadedPdf(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
    } catch (_) {}
    return false;
  }
}

