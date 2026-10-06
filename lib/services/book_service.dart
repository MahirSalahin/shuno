import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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

class BookService {
  BookService({http.Client? httpClient}) : _client = httpClient ?? http.Client();

  final http.Client _client;

  /// Cleans typical YouTube audiobook title noise to extract a clean book and author query for search.
  static String cleanAudiobookQuery(String title) {
    var clean = title;

    // Remove bracketed info: [ ... ] or ( ... )
    clean = clean.replaceAll(RegExp(r'\[.*?\]'), ' ');
    clean = clean.replaceAll(RegExp(r'\(.*?\)'), ' ');

    // Remove common audiobook noise words and patterns (supports English and Bengali)
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
      r'[0-9০-৯]+\s*/\s*[0-9০-৯]+', // e.g. 1/8 or ৫/৮
      r'নতুন\s+গল্প',
      r'নাটক',
      r'উপন্যাস',
      r'গল্প',
    ];

    for (final pattern in noisePatterns) {
      clean = clean.replaceAll(RegExp(pattern, caseSensitive: false), ' ');
    }

    // Replace separators (| or • or - or /) with spaces
    clean = clean.replaceAll(RegExp(r'[|•\-_\/]+'), ' ');

    // Normalize whitespace
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();

    return clean.isNotEmpty ? clean : title.trim();
  }

  /// Cleans an audiobook title for human-readable display (e.g. "শবনম | সৈয়দ মুজতবা আলী"),
  /// removing episode/part numbers and noise while keeping the book & author structure.
  static String cleanAudiobookTitle(String title) {
    var clean = title;

    // Remove bracketed info: [ ... ] or ( ... )
    clean = clean.replaceAll(RegExp(r'\[.*?\]'), ' ');
    clean = clean.replaceAll(RegExp(r'\(.*?\)'), ' ');

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
      r'(পর্ব|খণ্ড|ভাগ|অধ্যায়)\s*[0-9০-৯]+',
      r'chapter\s*[0-9০-৯]+(\s*(to|-)\s*[0-9০-৯]+)?',
      r'ch\s*[0-9০-৯]+',
      r'part\s*[0-9০-৯]+',
      r'episode\s*[0-9০-৯]+',
      r'ep\s*[0-9০-৯]+',
      r'[0-9০-৯]+\s*/\s*[0-9০-৯]+',
      r'নতুন\s+গল্প',
      r'নাটক',
    ];

    for (final pattern in noisePatterns) {
      clean = clean.replaceAll(RegExp(pattern, caseSensitive: false), ' ');
    }

    // Split by common separators (like | or •) to trim and remove empty segments
    final parts = clean
        .split(RegExp(r'[|•]+'))
        .map((p) => p.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((p) => p.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return title.trim();
    }

    // Usually first 1 or 2 parts contain the book title and author:
    // e.g. ["শবনম", "সৈয়দ মুজতবা আলী", "Syed Mujtaba Ali"]
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

    // Remove file extensions
    clean = clean.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');

    // Strip digital library of India and archive prefixes:
    // e.g. "in.ernet.dli.2015.457633 " or "in.ernet.dli."
    clean = clean.replaceAll(
      RegExp(r'^(in\.ernet\.dli\.[0-9.]+|dli\.[0-9.]+|ark:\/[0-9/]+)\s*[-_:]*\s*', caseSensitive: false),
      '',
    );

    // Replace underscores with spaces
    clean = clean.replaceAll('_', ' ');

    // Normalize whitespace
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();

    // If all that's left is digits, dots, and hyphens (like an identifier "2015.457633"),
    // or if it still contains "in.ernet.dli", then use the fallbackTitle!
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
    final cleaned = cleanAudiobookQuery(query);
    if (cleaned.isEmpty) return [];

    try {
      final encoded = Uri.encodeComponent('$cleaned AND mediatype:texts');
      final url = Uri.parse(
        'https://archive.org/advancedsearch.php?q=$encoded&fl[]=identifier,title,creator,downloads&sort[]=downloads+desc&rows=12&output=json',
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
        // Fallback standard Archive URL pattern
        return 'https://archive.org/download/$identifier/$identifier.pdf';
      }

      // Filter out corrupt stubs (< 50 KB)
      final validPdfs = pdfFiles.where((f) {
        final size = int.tryParse(f['size']?.toString() ?? '0') ?? 0;
        return size > 50 * 1024;
      }).toList();

      final candidateList = validPdfs.isNotEmpty ? validPdfs : pdfFiles;

      // Smart selection:
      // 1. Prefer mobile-friendly Text / B&W PDFs (fast to download, clean text)
      // 2. Select the smaller readable version to avoid multi-hundred MB raw scan files
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

        // Among similar formats, pick the smaller file (ASCENDING) to drastically reduce download time
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

  /// Downloads an Archive PDF file to the local books directory, reporting progress [0.0 - 1.0].
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
      final file = File('${booksDir.path}/$safeName.pdf');

      // If already downloaded and non-empty, reuse it!
      if (await file.exists() && await file.length() > 0) {
        onProgress?.call(1.0);
        return file.path;
      }

      final req = http.Request('GET', Uri.parse(pdfUrl));
      req.headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';
      req.headers['Accept'] = 'application/pdf,*/*';
      final response = await _client.send(req);
      if (response.statusCode != 200) return null;

      final contentLength = response.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (contentLength > 0 && onProgress != null) {
          onProgress(received / contentLength);
        }
      }

      await sink.flush();
      await sink.close();
      onProgress?.call(1.0);
      return file.path;
    } catch (_) {
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

  /// Returns the local path if this archive book is already downloaded, or null.
  Future<String?> getDownloadedPdfPath(String identifier) async {
    try {
      final baseDir = await getApplicationDocumentsDirectory();
      final safeName = identifier.replaceAll(RegExp(r'[^\w\.\-]'), '_');
      final file = File('${baseDir.path}/books/$safeName.pdf');
      if (await file.exists() && await file.length() > 0) {
        return file.path;
      }
    } catch (_) {}
    return null;
  }

  /// Lists all downloaded PDF files in the local books directory.
  Future<List<File>> getDownloadedBooks() async {
    try {
      final baseDir = await getApplicationDocumentsDirectory();
      final booksDir = Directory('${baseDir.path}/books');
      if (await booksDir.exists()) {
        final list = await booksDir
            .list()
            .where((entity) =>
                entity is File && entity.path.toLowerCase().endsWith('.pdf'))
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
