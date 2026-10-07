import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shuno/models/youtube_search_item.dart';
import 'package:shuno/services/book_service.dart';
import 'package:shuno/services/storage_service.dart';

void main() {
  group('BookService Query Cleaning & Extraction', () {
    test('cleans common YouTube audiobook title noise and tags', () {
      expect(
        BookService.cleanAudiobookQuery('Brave New World [Full Audiobook] HQ'),
        'Brave New World',
      );

      expect(
        BookService.cleanAudiobookQuery(
          'Crime and Punishment - Fyodor Dostoevsky (Part 1 of 2)',
        ),
        'Crime and Punishment',
      );

      expect(
        BookService.cleanAudiobookQuery('1984 George Orwell [Complete Audiobook]'),
        '1984 George Orwell',
      );

      expect(
        BookService.cleanAudiobookQuery('The Great Gatsby | Chapter 1 to 5'),
        'The Great Gatsby',
      );

      // Bengali audiobook title with Bengali digits
      expect(
        BookService.cleanAudiobookQuery('শবনম ৫/৮ | সৈয়দ মুজতবা আলী | Syed Mujtaba Ali'),
        'শবনম',
      );
    });

    test('extractSearchQueries extracts robust multi-query candidates for Bengali audiobook', () {
      const title = 'গাভী বিত্তান্ত 1/6 | আহমদ ছফা | Ahmed Sofa | Golpokothon by Kollol';
      final queries = BookService.extractSearchQueries(title);

      // Must include primary title
      expect(queries, contains('গাভী বিত্তান্ত'));
      // Must include Bengali title + Bengali author
      expect(queries, contains('গাভী বিত্তান্ত আহমদ ছফা'));
      // Must include Bengali title + English author
      expect(queries, contains('গাভী বিত্তান্ত Ahmed Sofa'));
      // Must include transliterated title
      expect(queries, contains('gabhi bittanto'));
      // Must include transliterated title + English author
      expect(queries, contains('gabhi bittanto Ahmed Sofa'));

      // Must discard narrator noise 'Golpokothon by Kollol'
      for (final q in queries) {
        expect(q.toLowerCase().contains('golpokothon'), isFalse);
        expect(q.toLowerCase().contains('by kollol'), isFalse);
      }
    });

    test('transliterateBengali correctly maps Bengali script to Latin letters', () {
      expect(BookService.transliterateBengali('গাভী বিত্তান্ত'), 'gabhi bittanto');
      expect(BookService.transliterateBengali('পথের পাঁচালী'), 'pather panchali');
      expect(BookService.transliterateBengali('শবনম'), 'shabanam');
      expect(BookService.transliterateBengali('হিমু'), 'himu');
    });

    test('cleanAudiobookTitle formats clean human-readable series title', () {
      expect(
        BookService.cleanAudiobookTitle('শবনম ৫/৮ | সৈয়দ মুজতবা আলী | Syed Mujtaba Ali'),
        'শবনম | সৈয়দ মুজতবা আলী',
      );

      expect(
        BookService.cleanAudiobookTitle('Crime and Punishment [Full Audiobook] - Fyodor Dostoevsky'),
        'Crime and Punishment - Fyodor Dostoevsky',
      );
    });

    test('sanitizeBookTitle removes raw Internet Archive / DLI identifiers', () {
      expect(
        BookService.sanitizeBookTitle(
          'in.ernet.dli.2015.457633 Rabi Thakurer Gaan',
          fallbackTitle: 'শবনম',
        ),
        'Rabi Thakurer Gaan',
      );

      // If the title is only a raw archive identifier, it falls back to the clean series title
      expect(
        BookService.sanitizeBookTitle(
          'in.ernet.dli.2015.457633',
          fallbackTitle: 'শবনম | সৈয়দ মুজতবা আলী',
        ),
        'শবনম | সৈয়দ মুজতবা আলী',
      );
    });
  });

  group('StorageService PDF & Page Bookmark Persistence', () {
    late Directory tempDir;
    late File testFile;
    late StorageService storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('shuno_book_test_');
      testFile = File('${tempDir.path}/test_storage.json');
      storage = StorageService();
      await storage.init(overrideFile: testFile);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saves, updates, reloads, and removes track PDF and page number', () async {
      const trackId = 'audiobook_track_123';
      const pdfPath = '/path/to/downloaded/book.pdf';

      // Default state
      expect(storage.getTrackPdfPath(trackId), isNull);
      expect(storage.getTrackPdfPage(trackId), 0);

      // Set PDF path
      await storage.setTrackPdf(trackId, pdfPath);
      expect(storage.getTrackPdfPath(trackId), pdfPath);

      // Update page bookmark
      await storage.setTrackPdfPage(trackId, 42);
      expect(storage.getTrackPdfPage(trackId), 42);

      // Verify persistence across disk re-load
      final reloadedStorage = StorageService();
      await reloadedStorage.init(overrideFile: testFile);
      expect(reloadedStorage.getTrackPdfPath(trackId), pdfPath);
      expect(reloadedStorage.getTrackPdfPage(trackId), 42);

      // Remove PDF
      await reloadedStorage.removeTrackPdf(trackId);
      expect(reloadedStorage.getTrackPdfPath(trackId), isNull);
      expect(reloadedStorage.getTrackPdfPage(trackId), 0);

      // Verify removal persisted to disk
      final verifiedStorage = StorageService();
      await verifiedStorage.init(overrideFile: testFile);
      expect(verifiedStorage.getTrackPdfPath(trackId), isNull);
      expect(verifiedStorage.getTrackPdfPage(trackId), 0);
    });

    test('findMatchingPdfPath finds PDF attached to another part of the same book', () async {
      // Simulate user attached PDF to Part 1
      final part1Pdf = '${tempDir.path}/shobnom_book.pdf';
      await File(part1Pdf).writeAsString('dummy pdf data');

      await storage.addToHistory(const YoutubeSearchItem(
        id: 'track_part_1',
        title: 'শবনম 1/8 | সৈয়দ মুজতবা আলী',
        channelName: 'Audiobooks',
        thumbnailUrl: '',
      ));
      await storage.setTrackPdf('track_part_1', part1Pdf);

      // Now query with Part 8 of the same book
      final cleanQueryPart8 = BookService.cleanAudiobookQuery('শবনম 8/8 | সৈয়দ মুজতবা আলী');
      final matchingPath = storage.findMatchingPdfPath(cleanQueryPart8);

      expect(matchingPath, part1Pdf);
    });

    test('isPdfFileValid validates complete PDF files and rejects stubs', () async {
      expect(BookService.isPdfFileValid(null), isFalse);
      expect(BookService.isPdfFileValid(''), isFalse);
      expect(BookService.isPdfFileValid('${tempDir.path}/nonexistent.pdf'), isFalse);

      // Tiny stub file (100 bytes) -> invalid
      final stubFile = File('${tempDir.path}/stub.pdf');
      await stubFile.writeAsBytes(List.filled(100, 0));
      expect(BookService.isPdfFileValid(stubFile.path), isFalse);

      // Valid PDF size (100 KB) -> valid
      final validFile = File('${tempDir.path}/valid.pdf');
      await validFile.writeAsBytes(List.filled(100 * 1024, 0));
      expect(BookService.isPdfFileValid(validFile.path), isTrue);
    });
  });

  group('BookService Internet Archive API Mocking & Multi-Search', () {
    test('searchArchive parses Internet Archive items correctly', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString().contains('advancedsearch.php')) {
          final mockResponse = {
            'response': {
              'numFound': 1,
              'docs': [
                {
                  'identifier': 'bravenewworld00huxl',
                  'title': 'Brave New World',
                  'creator': 'Aldous Huxley',
                },
              ],
            },
          };
          return http.Response(jsonEncode(mockResponse), 200, headers: {
            'content-type': 'application/json',
          });
        }
        return http.Response('Not Found', 404);
      });

      final service = BookService(httpClient: mockClient);
      final results = await service.searchArchive('Brave New World');

      expect(results.length, 1);
      expect(results.first.id, 'bravenewworld00huxl');
      expect(results.first.title, 'Brave New World');
      expect(results.first.creator, 'Aldous Huxley');
    });

    test('searchArchiveMulti merges and deduplicates results across candidate queries', () async {
      final mockClient = MockClient((request) async {
        final queryParam = request.url.queryParameters['q'] ?? '';
        final docs = <Map<String, dynamic>>[];

        if (queryParam.contains('গাভী বিত্তান্ত')) {
          docs.add({
            'identifier': 'gavibittanto01',
            'title': 'গাভী বিত্তান্ত',
            'creator': 'আহমদ ছফা',
          });
        }
        if (queryParam.contains('gabhi bittanto')) {
          docs.add({
            'identifier': 'gavibittanto01', // duplicate ID
            'title': 'গাভী বিত্তান্ত',
            'creator': 'আহমদ ছফা',
          });
          docs.add({
            'identifier': 'gabi_edition_english',
            'title': 'Gabhi Bittanto (English Translit)',
            'creator': 'Ahmed Sofa',
          });
        }

        return http.Response(
          jsonEncode({
            'response': {'docs': docs}
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = BookService(httpClient: mockClient);
      final results = await service.searchArchiveMulti([
        'গাভী বিত্তান্ত',
        'gabhi bittanto',
      ]);

      // Should contain 2 items after deduplicating gavibittanto01
      expect(results.length, 2);
      expect(results.map((b) => b.id).toSet(), {'gavibittanto01', 'gabi_edition_english'});
    });

    test('resolvePdfUrl resolves direct PDF download link from metadata', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString().contains('metadata/bravenewworld00huxl/files')) {
          final mockResponse = {
            'result': [
              {
                'name': 'bravenewworld00huxl_meta.xml',
                'format': 'Metadata',
                'size': '1234',
              },
              {
                'name': 'bravenewworld00huxl.pdf',
                'format': 'Text PDF',
                'size': '4567890',
              },
            ],
          };
          return http.Response(jsonEncode(mockResponse), 200, headers: {
            'content-type': 'application/json',
          });
        }
        return http.Response('Not Found', 404);
      });

      final service = BookService(httpClient: mockClient);
      final pdfUrl = await service.resolvePdfUrl('bravenewworld00huxl');

      expect(pdfUrl, isNotNull);
      expect(
        pdfUrl,
        'https://archive.org/download/bravenewworld00huxl/bravenewworld00huxl.pdf',
      );
    });

    test('BookService manages background download tasks state', () {
      final service = BookService();
      expect(service.isDownloading('test_book_id'), isFalse);
      expect(service.getDownloadProgress('test_book_id'), 0.0);
    });
  });
}
