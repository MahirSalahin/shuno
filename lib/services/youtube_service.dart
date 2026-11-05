import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/youtube_channel_item.dart';
import '../models/youtube_playlist_item.dart';
import '../models/youtube_search_item.dart';

class ChannelUploadsPage {
  const ChannelUploadsPage({
    required this.items,
    this.hasMore = false,
    this.continuation,
  });

  final List<YoutubeSearchItem> items;
  final bool hasMore;
  final dynamic continuation;
}

class ChannelPlaylistsPage {
  const ChannelPlaylistsPage({
    required this.items,
    this.hasMore = false,
    this.continuation,
  });

  final List<YoutubePlaylistItem> items;
  final bool hasMore;
  final String? continuation;
}

class _CachedStreamUrl {
  const _CachedStreamUrl({
    required this.url,
    required this.expiresAt,
  });

  final Uri url;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class _CachedSearchResult {
  const _CachedSearchResult({
    required this.items,
    required this.timestamp,
  });

  final List<YoutubeSearchItem> items;
  final DateTime timestamp;

  bool get isExpired =>
      DateTime.now().difference(timestamp) > const Duration(minutes: 10);
}

class YoutubeService {
  YoutubeExplode? _client;
  YoutubeExplode get _yt => _client ??= YoutubeExplode();

  final Map<String, _CachedStreamUrl> _streamUrlCache = {};
  final Map<String, _CachedSearchResult> _searchCache = {};
  final Map<String, Future<Uri>> _inFlightResolutions = {};

  void dispose() {
    _streamUrlCache.clear();
    _searchCache.clear();
    _inFlightResolutions.clear();
    _client?.close();
    _client = null;
  }

  void clearCachedUrl(String videoId) {
    _streamUrlCache.remove('$videoId-true');
    _streamUrlCache.remove('$videoId-false');
    _inFlightResolutions.remove('$videoId-true');
    _inFlightResolutions.remove('$videoId-false');
  }

  @visibleForTesting
  bool hasCachedUrl(String videoId, {bool highQuality = true}) {
    final cached = _streamUrlCache['$videoId-$highQuality'];
    return cached != null && !cached.isExpired;
  }

  @visibleForTesting
  Uri cacheResolvedUrl(String cacheKey, Uri url) => _cacheResolvedUrl(cacheKey, url);

  Uri _cacheResolvedUrl(String cacheKey, Uri url) {
    DateTime expiresAt;
    final expireParam = url.queryParameters['expire'];
    final expireSeconds = expireParam != null ? int.tryParse(expireParam) : null;
    if (expireSeconds != null) {
      // 15-minute buffer before expiration
      expiresAt = DateTime.fromMillisecondsSinceEpoch(expireSeconds * 1000)
          .subtract(const Duration(minutes: 15));
      if (expiresAt.difference(DateTime.now()).inMinutes < 5) {
        expiresAt = DateTime.now().add(const Duration(hours: 2));
      }
    } else {
      expiresAt = DateTime.now().add(const Duration(hours: 2));
    }

    if (_streamUrlCache.length >= 50) {
      _streamUrlCache.remove(_streamUrlCache.keys.first);
    }
    _streamUrlCache[cacheKey] = _CachedStreamUrl(
      url: url,
      expiresAt: expiresAt,
    );
    return url;
  }

  Future<Uri> resolveAudioUrl(String videoId, {bool highQuality = true}) async {
    final cacheKey = '$videoId-$highQuality';
    final cached = _streamUrlCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.url;
    }

    final inFlight = _inFlightResolutions[cacheKey];
    if (inFlight != null) {
      return await inFlight;
    }

    final future = resolveAudioUrlInternal(
      videoId,
      highQuality: highQuality,
      cacheKey: cacheKey,
    );
    _inFlightResolutions[cacheKey] = future;
    try {
      return await future;
    } finally {
      _inFlightResolutions.remove(cacheKey);
    }
  }

  @visibleForTesting
  Future<Uri> resolveAudioUrlInternal(
    String videoId, {
    required bool highQuality,
    required String cacheKey,
  }) async {
    final youtube = _yt;
    StreamManifest manifest;
    try {
      // Query InnerTube API directly with mobile clients to avoid web watch page rate-limiting (429)
      manifest = await youtube.videos.streamsClient
          .getManifest(
            videoId,
            ytClients: [
              YoutubeApiClient.androidSdkless,
              YoutubeApiClient.ios,
              YoutubeApiClient.androidMusic,
            ],
            requireWatchPage: false,
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      if (kDebugMode) debugPrint('InnerTube direct manifest fetch failed ($e), falling back...');
      manifest = await youtube.videos.streamsClient
          .getManifest(videoId)
          .timeout(const Duration(seconds: 25));
    }

    // Prioritize Stream 18 (universal 360p MP4 with AAC stereo audio, ratebypass=yes, unthrottled)
    final stream18 = manifest.muxed.where((s) => s.tag == 18).firstOrNull;
    if (stream18 != null) {
      return _cacheResolvedUrl(cacheKey, stream18.url);
    }

    if (manifest.audioOnly.isEmpty) {
      if (manifest.muxed.isNotEmpty) {
        return _cacheResolvedUrl(cacheKey, manifest.muxed.first.url);
      }
      throw StateError('This video has no playable audio stream.');
    }
    final mp4 = manifest.audioOnly.where(
      (stream) => stream.container == StreamContainer.mp4,
    );
    final pool = mp4.isNotEmpty ? mp4 : manifest.audioOnly;
    final stream = highQuality
        ? pool.withHighestBitrate()
        : (pool.length > 1 ? pool.elementAt(pool.length ~/ 2) : pool.first);
    return _cacheResolvedUrl(cacheKey, stream.url);
  }

  Future<List<YoutubeSearchItem>> search(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return [];

    final cacheKey = trimmedQuery.toLowerCase();
    final cached = _searchCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.items;
    }

    final youtube = _yt;
    final results = await youtube.search
        .searchContent(trimmedQuery, filter: TypeFilters.video)
        .timeout(const Duration(seconds: 20));

    final items = results
        .whereType<SearchVideo>()
        .map(
          (video) => YoutubeSearchItem(
            id: video.id.value,
            title: video.title,
            channelName: video.author,
            thumbnailUrl: ThumbnailSet(video.id.value).mediumResUrl,
            duration: _parseDuration(video.duration),
          ),
        )
        .toList();

    if (_searchCache.length >= 25) {
      _searchCache.remove(_searchCache.keys.first);
    }
    _searchCache[cacheKey] = _CachedSearchResult(
      items: List.unmodifiable(items),
      timestamp: DateTime.now(),
    );

    return items;
  }

  Future<List<YoutubeChannelItem>> searchChannels(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return [];

    try {
      final scraped = await _scrapeChannels(trimmedQuery);
      if (scraped.isNotEmpty) return scraped;
    } catch (_) {}

    final youtube = _yt;
    try {
      final results = await youtube.search
          .searchContent(trimmedQuery, filter: TypeFilters.channel)
          .timeout(const Duration(seconds: 20));

      return results
          .whereType<SearchChannel>()
          .map(
            (ch) => YoutubeChannelItem(
              id: ch.id.value,
              title: ch.name,
              thumbnailUrl: ch.thumbnails.isNotEmpty
                  ? ch.thumbnails.last.url.toString()
                  : '',
              videoCount: ch.videoCount >= 0 ? ch.videoCount : null,
              description: ch.description,
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<YoutubeChannelItem>> _scrapeChannels(String query) async {
    final url =
        'https://www.youtube.com/results?search_query=${Uri.encodeQueryComponent(query)}&sp=EgIQAg%253D%253D&hl=en';
    final res = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept-Language': 'en-US,en;q=0.9',
      },
    ).timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) return [];

    return compute(_parseChannelsWorker, res.body);
  }

  Future<List<YoutubePlaylistItem>> searchPlaylists(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return [];

    final youtube = _yt;
    try {
      final results = await youtube.search
          .searchContent(trimmedQuery, filter: TypeFilters.playlist)
          .timeout(const Duration(seconds: 20));

      return results
          .whereType<SearchPlaylist>()
          .map(
            (pl) => YoutubePlaylistItem(
              id: pl.id.value,
              title: pl.title,
              thumbnailUrl: pl.thumbnails.isNotEmpty
                  ? pl.thumbnails.last.url.toString()
                  : '',
              videoCount: pl.videoCount >= 0 ? pl.videoCount : null,
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<YoutubeChannelItem?> getChannel(String channelId) async {
    if (channelId.trim().isEmpty) return null;
    final youtube = _yt;
    try {
      final channel = await youtube.channels
          .get(channelId)
          .timeout(const Duration(seconds: 15));
      return YoutubeChannelItem(
        id: channel.id.value,
        title: channel.title,
        thumbnailUrl: channel.logoUrl,
        subscriberCount: channel.subscribersCount,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<YoutubeSearchItem>> getChannelVideos(
    String channelId, {
    String? channelName,
  }) async {
    final page = await getChannelUploadsPage(
      channelId,
      channelName: channelName,
    );
    return page.items;
  }

  Future<ChannelUploadsPage> getChannelUploadsPage(
    String channelId, {
    String? channelName,
    dynamic continuation,
  }) async {
    final continuationToken = continuation is String ? continuation : null;

    try {
      final page = await _scrapeChannelVideosPage(
        channelId,
        channelName: channelName,
        continuationToken: continuationToken,
      );
      if (page.items.isNotEmpty) {
        return page;
      }
    } catch (_) {}

    try {
      if (continuation != null) {
        if (continuation is ChannelUploadsList) {
          final nextUploads = await continuation
              .nextPage()
              .timeout(const Duration(seconds: 15));
          if (nextUploads != null && nextUploads.isNotEmpty) {
            final videos = nextUploads
                .where((v) => v.title.isNotEmpty)
                .map(
                  (v) => YoutubeSearchItem(
                    id: v.id.value,
                    title: v.title,
                    channelName:
                        v.author.isNotEmpty ? v.author : (channelName ?? ''),
                    thumbnailUrl: v.thumbnails.mediumResUrl,
                    duration: (v.duration != null && v.duration! > Duration.zero)
                        ? v.duration
                        : null,
                  ),
                )
                .toList();
            if (videos.isNotEmpty) {
              return ChannelUploadsPage(
                items: videos,
                hasMore: true,
                continuation: nextUploads,
              );
            }
          }
          return const ChannelUploadsPage(items: [], hasMore: false);
        }
      }

      // Initial page fallback using youtube_explode
      final pageUploads = await _yt.channels
          .getUploadsFromPage(channelId)
          .timeout(const Duration(seconds: 15));

      final videos = pageUploads
          .where((v) => v.title.isNotEmpty)
          .map(
            (v) => YoutubeSearchItem(
              id: v.id.value,
              title: v.title,
              channelName: v.author.isNotEmpty ? v.author : (channelName ?? ''),
              thumbnailUrl: v.thumbnails.mediumResUrl,
              duration: (v.duration != null && v.duration! > Duration.zero)
                  ? v.duration
                  : null,
            ),
          )
          .toList();

      if (videos.isNotEmpty) {
        return ChannelUploadsPage(
          items: videos,
          hasMore: true,
          continuation: pageUploads,
        );
      }

      // Fallback: dedicated uploads stream
      final uploadsStream = _yt.channels.getUploads(channelId).take(30);
      final streamVideos = <YoutubeSearchItem>[];
      await for (final v in uploadsStream) {
        streamVideos.add(
          YoutubeSearchItem(
            id: v.id.value,
            title: v.title.isNotEmpty
                ? v.title
                : (channelName != null ? '$channelName Track' : 'Track'),
            channelName: v.author.isNotEmpty ? v.author : (channelName ?? ''),
            thumbnailUrl: v.thumbnails.mediumResUrl,
            duration: (v.duration != null && v.duration! > Duration.zero)
                ? v.duration
                : null,
          ),
        );
      }

      return ChannelUploadsPage(
        items: streamVideos,
        hasMore: false,
        continuation: null,
      );
    } catch (_) {
      return const ChannelUploadsPage(items: [], hasMore: false);
    }
  }

  Future<ChannelUploadsPage> _scrapeChannelVideosPage(
    String channelId, {
    String? channelName,
    String? continuationToken,
  }) async {
    final id = channelId.trim();
    if (id.isEmpty) return const ChannelUploadsPage(items: []);

    try {
      if (continuationToken != null && continuationToken.isNotEmpty) {
        final postRes = await http.post(
          Uri.parse('https://www.youtube.com/youtubei/v1/browse?prettyPrint=false'),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept-Language': 'en-US,en;q=0.9',
          },
          body: jsonEncode({
            'context': {
              'client': {
                'clientName': 'WEB',
                'clientVersion': '2.20231219.00.00',
                'hl': 'en',
                'gl': 'US',
              },
            },
            'continuation': continuationToken,
          }),
        ).timeout(const Duration(seconds: 15));

        if (postRes.statusCode != 200) {
          return const ChannelUploadsPage(items: []);
        }
        return compute(_parseChannelUploadsWorker, {
          'body': postRes.body,
          'channelName': channelName ?? '',
          'isJson': 'true',
        });
      }

      final videosUrl = id.startsWith('@')
          ? 'https://www.youtube.com/$id/videos?hl=en'
          : 'https://www.youtube.com/channel/$id/videos?hl=en';
      final response = await http.get(
        Uri.parse(videosUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return const ChannelUploadsPage(items: []);
      }

      return compute(_parseChannelUploadsWorker, {
        'body': response.body,
        'channelName': channelName ?? '',
        'isJson': 'false',
      });
    } catch (_) {
      return const ChannelUploadsPage(items: []);
    }
  }

  Future<ChannelPlaylistsPage> getChannelPlaylistsPage(
    String channelName, {
    String? channelId,
    String? continuation,
  }) async {
    final id = channelId?.trim() ?? '';
    if (id.isEmpty) return const ChannelPlaylistsPage(items: []);

    try {
      if (continuation != null && continuation.isNotEmpty) {
        final postRes = await http.post(
          Uri.parse('https://www.youtube.com/youtubei/v1/browse?prettyPrint=false'),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept-Language': 'en-US,en;q=0.9',
          },
          body: jsonEncode({
            'context': {
              'client': {
                'clientName': 'WEB',
                'clientVersion': '2.20231201.00.00',
                'hl': 'en',
              },
            },
            'continuation': continuation,
          }),
        ).timeout(const Duration(seconds: 15));

        if (postRes.statusCode != 200) {
          return const ChannelPlaylistsPage(items: []);
        }
        return compute(_parseChannelPlaylistsWorker, {
          'body': postRes.body,
          'channelName': channelName,
          'isJson': 'true',
        });
      }

      final playlistsUrl = 'https://www.youtube.com/channel/$id/playlists?hl=en';
      final response = await http.get(
        Uri.parse(playlistsUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return const ChannelPlaylistsPage(items: []);
      }

      return compute(_parseChannelPlaylistsWorker, {
        'body': response.body,
        'channelName': channelName,
        'isJson': 'false',
      });
    } catch (_) {
      return const ChannelPlaylistsPage(items: []);
    }
  }

  Future<List<YoutubePlaylistItem>> getChannelPlaylists(
    String channelName, {
    String? channelId,
  }) async {
    final page = await getChannelPlaylistsPage(
      channelName,
      channelId: channelId,
    );
    return page.items;
  }

  static ChannelPlaylistsPage _extractChannelPlaylistsPageFromJson(
    dynamic node,
    String defaultAuthor,
  ) {
    final results = <YoutubePlaylistItem>[];
    final seenIds = <String>{};
    String? nextContinuation;

    void walk(dynamic obj) {
      if (obj is Map<String, dynamic>) {
        if (obj.containsKey('lockupViewModel')) {
          final lvm = obj['lockupViewModel'] as Map<String, dynamic>;
          final contentId = lvm['contentId']?.toString() ?? '';
          final contentType = lvm['contentType']?.toString() ?? '';
          if (contentId.startsWith('PL') || contentType == 'LOCKUP_CONTENT_TYPE_PLAYLIST') {
            if (contentId.isNotEmpty && seenIds.add(contentId)) {
              final titleMeta = lvm['metadata']?['lockupMetadataViewModel']?['title'];
              final title = titleMeta?['content']?.toString() ?? 'Playlist';

              String thumb = '';
              final thumbObj = lvm['contentImage']?['collectionThumbnailViewModel']
                  ?['primaryThumbnail']?['thumbnailViewModel']?['image']?['sources'];
              if (thumbObj is List && thumbObj.isNotEmpty) {
                thumb = thumbObj.last?['url']?.toString() ?? '';
              }

              int? videoCount;
              final overlays = lvm['contentImage']?['collectionThumbnailViewModel']
                  ?['primaryThumbnail']?['thumbnailViewModel']?['overlays'];
              if (overlays is List) {
                for (final ov in overlays) {
                  final badges = ov['thumbnailOverlayBadgeViewModel']?['thumbnailBadges'];
                  if (badges is List) {
                    for (final b in badges) {
                      final text = b['thumbnailBadgeViewModel']?['text']?.toString() ?? '';
                      final match = RegExp(r'(\d+)').firstMatch(text.replaceAll(',', ''));
                      if (match != null) {
                        videoCount = int.tryParse(match.group(1)!);
                        break;
                      }
                    }
                  }
                }
              }

              results.add(
                YoutubePlaylistItem(
                  id: contentId,
                  title: title,
                  thumbnailUrl: thumb,
                  videoCount: videoCount,
                  author: defaultAuthor,
                ),
              );
            }
          }
        } else if (obj.containsKey('gridPlaylistRenderer')) {
          final gpr = obj['gridPlaylistRenderer'] as Map<String, dynamic>;
          final playlistId = gpr['playlistId']?.toString() ?? '';
          if (playlistId.isNotEmpty && seenIds.add(playlistId)) {
            final titleObj = gpr['title'];
            var title = 'Playlist';
            if (titleObj is Map<String, dynamic>) {
              if (titleObj['runs'] is List && (titleObj['runs'] as List).isNotEmpty) {
                title = titleObj['runs'][0]['text']?.toString() ?? 'Playlist';
              } else if (titleObj['simpleText'] != null) {
                title = titleObj['simpleText'].toString();
              }
            }

            var thumb = '';
            final thumbs = gpr['thumbnail']?['thumbnails'];
            if (thumbs is List && thumbs.isNotEmpty) {
              thumb = thumbs.last['url']?.toString() ?? '';
            }

            int? videoCount;
            final countText = gpr['videoCountShortText']?['simpleText']?.toString() ??
                gpr['videoCountText']?['runs']?[0]?['text']?.toString() ??
                '';
            final countMatch = RegExp(r'(\d+)').firstMatch(countText.replaceAll(',', ''));
            if (countMatch != null) {
              videoCount = int.tryParse(countMatch.group(1)!);
            }

            results.add(
              YoutubePlaylistItem(
                id: playlistId,
                title: title,
                thumbnailUrl: thumb,
                videoCount: videoCount,
                author: defaultAuthor,
              ),
            );
          }
        } else if (obj.containsKey('continuationItemRenderer')) {
          final cir = obj['continuationItemRenderer'] as Map<String, dynamic>;
          final endpoint = cir['continuationEndpoint'];
          final token = endpoint?['continuationCommand']?['token']?.toString();
          if (token != null && token.isNotEmpty) {
            nextContinuation ??= token;
          }
        }

        for (final v in obj.values) {
          walk(v);
        }
      } else if (obj is List) {
        for (final item in obj) {
          walk(item);
        }
      }
    }

    walk(node);
    return ChannelPlaylistsPage(
      items: results,
      hasMore: nextContinuation != null && results.isNotEmpty,
      continuation: nextContinuation,
    );
  }

  Future<List<YoutubeSearchItem>> getPlaylistTracks(
    String playlistId, {
    int limit = 50,
  }) async {
    final trimmedId = playlistId.trim();
    if (trimmedId.isEmpty) return [];

    try {
      final scraped = await _scrapePlaylistTracks(trimmedId, limit: limit);
      if (scraped.isNotEmpty) return scraped;
    } catch (_) {}

    try {
      final videoStream = _yt.playlists.getVideos(trimmedId).take(limit);
      final items = <YoutubeSearchItem>[];
      await for (final video in videoStream) {
        items.add(
          YoutubeSearchItem(
            id: video.id.value,
            title: video.title.isNotEmpty ? video.title : 'Track',
            channelName: video.author,
            thumbnailUrl: ThumbnailSet(video.id.value).mediumResUrl,
            duration: (video.duration != null && video.duration! > Duration.zero)
                ? video.duration
                : null,
          ),
        );
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  Future<List<YoutubeSearchItem>> _scrapePlaylistTracks(
    String playlistId, {
    int limit = 50,
  }) async {
    final url = 'https://www.youtube.com/playlist?list=$playlistId&hl=en';
    final res = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept-Language': 'en-US,en;q=0.9',
      },
    ).timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) return [];

    return compute(_parsePlaylistTracksWorker, {
      'body': res.body,
      'limit': limit,
    });
  }

  static List<YoutubeSearchItem> _extractPlaylistVideosFromJson(
    dynamic node, {
    int limit = 50,
  }) {
    final results = <YoutubeSearchItem>[];
    final seenIds = <String>{};

    void walk(dynamic obj) {
      if (results.length >= limit) return;
      if (obj is Map<String, dynamic>) {
        final item = _parseVideoFromNode(obj, seenIds, '');
        if (item != null) {
          results.add(item);
        }
        for (final v in obj.values) {
          if (results.length >= limit) return;
          walk(v);
        }
      } else if (obj is List) {
        for (final item in obj) {
          if (results.length >= limit) return;
          walk(item);
        }
      }
    }

    walk(node);
    return results;
  }

  Future<List<YoutubeSearchItem>> searchChannelTracks(
    String channelId,
    String query, {
    String? channelName,
  }) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return [];

    final id = channelId.trim();
    if (id.isEmpty) return [];

    try {
      final searchUrl = id.startsWith('@')
          ? 'https://www.youtube.com/$id/search?query=${Uri.encodeComponent(trimmedQuery)}&hl=en'
          : 'https://www.youtube.com/channel/$id/search?query=${Uri.encodeComponent(trimmedQuery)}&hl=en';
      final response = await http.get(
        Uri.parse(searchUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return [];

      return compute(_parseChannelSearchWorker, {
        'body': response.body,
        'channelName': channelName ?? '',
      });
    } catch (_) {
      return [];
    }
  }

  static List<YoutubeSearchItem> _extractChannelVideosFromJson(
    dynamic node,
    String defaultAuthor,
  ) {
    final results = <YoutubeSearchItem>[];
    final seenIds = <String>{};

    void walk(dynamic obj) {
      if (obj is Map<String, dynamic>) {
        final item = _parseVideoFromNode(obj, seenIds, defaultAuthor);
        if (item != null) {
          results.add(item);
        }
        for (final v in obj.values) {
          walk(v);
        }
      } else if (obj is List) {
        for (final elem in obj) {
          walk(elem);
        }
      }
    }

    walk(node);
    return results;
  }

  static ChannelUploadsPage _extractChannelUploadsPageFromJson(
    dynamic node,
    String defaultAuthor,
  ) {
    final results = <YoutubeSearchItem>[];
    final seenIds = <String>{};
    String? nextContinuation;

    void walk(dynamic obj) {
      if (obj is Map<String, dynamic>) {
        final item = _parseVideoFromNode(obj, seenIds, defaultAuthor);
        if (item != null) {
          results.add(item);
        } else if (obj.containsKey('continuationItemRenderer')) {
          final cr = obj['continuationItemRenderer'] as Map<String, dynamic>;
          final token = cr['continuationEndpoint']?['continuationCommand']?['token']?.toString() ??
              cr['continuationCommand']?['token']?.toString();
          if (token != null && token.isNotEmpty && nextContinuation == null) {
            nextContinuation = token;
          }
        }

        for (final v in obj.values) {
          walk(v);
        }
      } else if (obj is List) {
        for (final elem in obj) {
          walk(elem);
        }
      }
    }

    walk(node);
    return ChannelUploadsPage(
      items: results,
      hasMore: nextContinuation != null && results.isNotEmpty,
      continuation: nextContinuation,
    );
  }

  @visibleForTesting
  ChannelUploadsPage extractChannelUploadsPageFromJson(
    dynamic node,
    String defaultAuthor,
  ) =>
      _extractChannelUploadsPageFromJson(node, defaultAuthor);

  @visibleForTesting
  List<YoutubeChannelItem> extractChannelsFromJson(dynamic node) =>
      _extractChannelsFromJson(node);

  static YoutubeSearchItem? _parseVideoFromNode(
    Map<String, dynamic> obj,
    Set<String> seenIds,
    String defaultAuthor,
  ) {
    if (obj.containsKey('lockupViewModel')) {
      final lvm = obj['lockupViewModel'] as Map<String, dynamic>;
      final contentType = lvm['contentType']?.toString() ?? '';
      final contentId = lvm['contentId']?.toString() ?? '';
      if ((contentType == 'LOCKUP_CONTENT_TYPE_VIDEO' || contentType.isEmpty) &&
          contentId.isNotEmpty &&
          !contentId.startsWith('PL') &&
          !contentId.startsWith('UC') &&
          seenIds.add(contentId)) {
        var title = '';
        final titleMeta = lvm['metadata']?['lockupMetadataViewModel']?['title'];
        if (titleMeta is Map<String, dynamic>) {
          if (titleMeta['content'] != null &&
              titleMeta['content'].toString().trim().isNotEmpty) {
            title = titleMeta['content'].toString().trim();
          } else if (titleMeta['runs'] is List && (titleMeta['runs'] as List).isNotEmpty) {
            title = titleMeta['runs'][0]['text']?.toString().trim() ?? '';
          } else if (titleMeta['simpleText'] != null) {
            title = titleMeta['simpleText'].toString().trim();
          }
        }
        if (title.isEmpty) {
          final label = lvm['rendererContext']?['accessibilityContext']?['label']?.toString().trim();
          if (label != null && label.isNotEmpty) {
            title = label;
          }
        }
        if (title.isEmpty) {
          title = defaultAuthor.isNotEmpty ? '$defaultAuthor Track' : 'Track';
        }

        var author = defaultAuthor;
        final rows = lvm['metadata']?['lockupMetadataViewModel']?['metadata']
            ?['contentMetadataViewModel']?['metadataRows'];
        if (rows is List && rows.isNotEmpty) {
          final parts = rows[0]?['metadataParts'];
          if (parts is List && parts.isNotEmpty) {
            final a = parts[0]?['text']?['content']?.toString().trim();
            if (a != null && a.isNotEmpty) author = a;
          }
        }

        Duration? duration;
        final overlays = lvm['contentImage']?['thumbnailViewModel']?['overlays'];
        if (overlays is List) {
          for (final ov in overlays) {
            if (ov is! Map<String, dynamic>) continue;
            final badges = ov['thumbnailBottomOverlayViewModel']?['badges'] ??
                ov['thumbnailOverlayBadgeViewModel']?['thumbnailBadges'];
            if (badges is List) {
              for (final b in badges) {
                if (b is! Map<String, dynamic>) continue;
                final text = b['thumbnailBadgeViewModel']?['text']?.toString() ??
                    b['text']?['simpleText']?.toString() ??
                    '';
                if (text.contains(':')) {
                  duration = _parseDuration(text);
                  if (duration != null) break;
                }
              }
            }
            if (duration != null) break;
          }
        }

        var thumb = ThumbnailSet(contentId).mediumResUrl;
        final sources = lvm['contentImage']?['thumbnailViewModel']?['image']?['sources'];
        if (sources is List && sources.isNotEmpty) {
          thumb = sources.last?['url']?.toString() ?? thumb;
        }

        return YoutubeSearchItem(
          id: contentId,
          title: title,
          channelName: author,
          thumbnailUrl: thumb,
          duration: duration,
        );
      }
    } else if (obj.containsKey('videoRenderer')) {
      final vr = obj['videoRenderer'] as Map<String, dynamic>;
      final videoId = vr['videoId']?.toString() ?? '';
      if (videoId.isNotEmpty && seenIds.add(videoId)) {
        final titleObj = vr['title'];
        var title = defaultAuthor.isNotEmpty ? '$defaultAuthor Track' : 'Track';
        if (titleObj is Map<String, dynamic>) {
          if (titleObj['runs'] is List && (titleObj['runs'] as List).isNotEmpty) {
            title = titleObj['runs'][0]['text']?.toString().trim() ?? title;
          } else if (titleObj['simpleText'] != null) {
            title = titleObj['simpleText'].toString().trim();
          }
        }

        var author = defaultAuthor;
        final ownerObj = vr['ownerText'] ?? vr['longBylineText'] ?? vr['shortBylineText'];
        if (ownerObj is Map<String, dynamic> &&
            ownerObj['runs'] is List &&
            (ownerObj['runs'] as List).isNotEmpty) {
          final ownerStr = ownerObj['runs'][0]['text']?.toString().trim();
          if (ownerStr != null && ownerStr.isNotEmpty) author = ownerStr;
        }

        final durationText = vr['lengthText']?['simpleText']?.toString() ?? '';
        final duration = _parseDuration(durationText);

        var thumb = ThumbnailSet(videoId).mediumResUrl;
        final thumbs = vr['thumbnail']?['thumbnails'];
        if (thumbs is List && thumbs.isNotEmpty) {
          thumb = thumbs.last['url']?.toString() ?? thumb;
        }

        return YoutubeSearchItem(
          id: videoId,
          title: title,
          channelName: author,
          thumbnailUrl: thumb,
          duration: duration,
        );
      }
    } else if (obj.containsKey('gridVideoRenderer')) {
      final gvr = obj['gridVideoRenderer'] as Map<String, dynamic>;
      final videoId = gvr['videoId']?.toString() ?? '';
      if (videoId.isNotEmpty && seenIds.add(videoId)) {
        final titleObj = gvr['title'];
        var title = defaultAuthor.isNotEmpty ? '$defaultAuthor Track' : 'Track';
        if (titleObj is Map<String, dynamic>) {
          if (titleObj['runs'] is List && (titleObj['runs'] as List).isNotEmpty) {
            title = titleObj['runs'][0]['text']?.toString().trim() ?? title;
          } else if (titleObj['simpleText'] != null) {
            title = titleObj['simpleText'].toString().trim();
          }
        }

        var author = defaultAuthor;
        final ownerObj = gvr['shortBylineText'] ?? gvr['ownerText'];
        if (ownerObj is Map<String, dynamic> &&
            ownerObj['runs'] is List &&
            (ownerObj['runs'] as List).isNotEmpty) {
          final ownerStr = ownerObj['runs'][0]['text']?.toString().trim();
          if (ownerStr != null && ownerStr.isNotEmpty) author = ownerStr;
        }

        Duration? duration;
        final overlays = gvr['thumbnailOverlays'];
        if (overlays is List) {
          for (final ov in overlays) {
            if (ov is! Map<String, dynamic>) continue;
            final timeStatus = ov['thumbnailOverlayTimeStatusRenderer'];
            if (timeStatus is Map<String, dynamic>) {
              final text = timeStatus['text']?['simpleText']?.toString() ??
                  timeStatus['text']?['runs']?[0]?['text']?.toString() ??
                  '';
              if (text.contains(':')) {
                duration = _parseDuration(text);
                if (duration != null) break;
              }
            }
          }
        }

        var thumb = ThumbnailSet(videoId).mediumResUrl;
        final thumbs = gvr['thumbnail']?['thumbnails'];
        if (thumbs is List && thumbs.isNotEmpty) {
          thumb = thumbs.last?['url']?.toString() ?? thumb;
        }

        return YoutubeSearchItem(
          id: videoId,
          title: title,
          channelName: author,
          thumbnailUrl: thumb,
          duration: duration,
        );
      }
    } else if (obj.containsKey('playlistVideoRenderer')) {
      final pvr = obj['playlistVideoRenderer'] as Map<String, dynamic>;
      final videoId = pvr['videoId']?.toString() ?? '';
      if (videoId.isNotEmpty && seenIds.add(videoId)) {
        final titleObj = pvr['title'];
        var title = 'Track';
        if (titleObj is Map<String, dynamic>) {
          if (titleObj['runs'] is List && (titleObj['runs'] as List).isNotEmpty) {
            title = titleObj['runs'][0]['text']?.toString().trim() ?? 'Track';
          } else if (titleObj['simpleText'] != null) {
            title = titleObj['simpleText'].toString().trim();
          }
        }

        var author = defaultAuthor;
        final byline = pvr['shortBylineText'] ?? pvr['longBylineText'];
        if (byline is Map<String, dynamic> &&
            byline['runs'] is List &&
            (byline['runs'] as List).isNotEmpty) {
          author = byline['runs'][0]['text']?.toString().trim() ?? defaultAuthor;
        }

        final durationText = pvr['lengthText']?['simpleText']?.toString() ?? '';
        final duration = _parseDuration(durationText);

        var thumb = ThumbnailSet(videoId).mediumResUrl;
        final thumbs = pvr['thumbnail']?['thumbnails'];
        if (thumbs is List && thumbs.isNotEmpty) {
          thumb = thumbs.last['url']?.toString() ?? thumb;
        }

        return YoutubeSearchItem(
          id: videoId,
          title: title,
          channelName: author,
          thumbnailUrl: thumb,
          duration: duration,
        );
      }
    }
    return null;
  }


  @visibleForTesting
  static String? getNextSeriesQuery(String title, String channelName) =>
      _getNextSeriesQuery(title, channelName);

  static String? _getNextSeriesQuery(String title, String channelName) {
    // 1. Numerator fraction e.g. "1/6", "01/12", "1 / 6"
    final fractionRegex = RegExp(r'(\b)(\d+)\s*/\s*(\d+)(\b)');
    final fractionMatch = fractionRegex.firstMatch(title);
    if (fractionMatch != null) {
      final numStr = fractionMatch.group(2)!;
      final totalStr = fractionMatch.group(3)!;
      final currentNum = int.tryParse(numStr);
      final total = int.tryParse(totalStr);
      if (currentNum != null && total != null && currentNum < total) {
        final nextNum = currentNum + 1;
        final nextNumStr = nextNum.toString().padLeft(numStr.length, '0');
        final nextTitle = title.replaceRange(
          fractionMatch.start,
          fractionMatch.end,
          '${fractionMatch.group(1)}$nextNumStr/$totalStr${fractionMatch.group(4)}',
        );
        return '$nextTitle $channelName'.trim();
      }
    }

    // 2. Part / Episode / Chapter / Vol / Volume e.g. "Part 1", "Episode 02", "Ch. 3", "Pt. 4", "Vol 1"
    final seriesRegex = RegExp(
      r'\b(part|pt\.?|episode|ep\.?|chapter|ch\.?|vol\.?|volume)\s*[-_:]?\s*(\d+)\b',
      caseSensitive: false,
    );
    final seriesMatch = seriesRegex.firstMatch(title);
    if (seriesMatch != null) {
      final prefix = seriesMatch.group(1)!;
      final numStr = seriesMatch.group(2)!;
      final currentNum = int.tryParse(numStr);
      if (currentNum != null && currentNum < 9999) {
        final nextNum = currentNum + 1;
        final nextNumStr = nextNum.toString().padLeft(numStr.length, '0');
        final nextTitle = title.replaceRange(
          seriesMatch.start,
          seriesMatch.end,
          '$prefix $nextNumStr',
        );
        return '$nextTitle $channelName'.trim();
      }
    }

    // 3. Track / # notation e.g. "#1", "# 01"
    final hashRegex = RegExp(r'#\s*(\d+)\b');
    final hashMatch = hashRegex.firstMatch(title);
    if (hashMatch != null) {
      final numStr = hashMatch.group(1)!;
      final currentNum = int.tryParse(numStr);
      if (currentNum != null && currentNum < 9999) {
        final nextNum = currentNum + 1;
        final nextNumStr = nextNum.toString().padLeft(numStr.length, '0');
        final nextTitle = title.replaceRange(
          hashMatch.start,
          hashMatch.end,
          '#$nextNumStr',
        );
        return '$nextTitle $channelName'.trim();
      }
    }

    return null;
  }

  Future<List<YoutubeSearchItem>> getRelatedVideos(
    YoutubeSearchItem currentItem,
  ) async {
    final results = <YoutubeSearchItem>[];
    final seenIds = <String>{currentItem.id};

    // 1. If this is an episodic/chapter series track, query for the next part first
    final nextSeriesQuery = _getNextSeriesQuery(currentItem.title, currentItem.channelName);
    if (nextSeriesQuery != null) {
      try {
        final seriesResults = await _yt.search
            .searchContent(nextSeriesQuery, filter: TypeFilters.video)
            .timeout(const Duration(seconds: 8));
        for (final v in seriesResults.whereType<SearchVideo>()) {
          if (seenIds.add(v.id.value)) {
            results.add(
              YoutubeSearchItem(
                id: v.id.value,
                title: v.title,
                channelName: v.author,
                thumbnailUrl: ThumbnailSet(v.id.value).mediumResUrl,
                duration: _parseDuration(v.duration),
              ),
            );
          }
        }
      } catch (_) {}
    }

    // 2. Fetch related videos using shared client with strict timeout
    try {
      final video = await _yt.videos.get(currentItem.id).timeout(const Duration(seconds: 7));
      final related = await _yt.videos.getRelatedVideos(video).timeout(const Duration(seconds: 7));
      if (related != null) {
        for (final v in related) {
          if (seenIds.add(v.id.value)) {
            results.add(
              YoutubeSearchItem(
                id: v.id.value,
                title: v.title,
                channelName: v.author,
                thumbnailUrl: ThumbnailSet(v.id.value).mediumResUrl,
                duration: v.duration,
              ),
            );
          }
        }
      }
    } catch (_) {}

    // 3. Fallback search query if no results obtained yet
    if (results.isEmpty) {
      try {
        final query = '${currentItem.title} ${currentItem.channelName}'.trim();
        final searchResults = await _yt.search
            .searchContent(query, filter: TypeFilters.video)
            .timeout(const Duration(seconds: 8));
        for (final v in searchResults.whereType<SearchVideo>()) {
          if (seenIds.add(v.id.value)) {
            results.add(
              YoutubeSearchItem(
                id: v.id.value,
                title: v.title,
                channelName: v.author,
                thumbnailUrl: ThumbnailSet(v.id.value).mediumResUrl,
                duration: _parseDuration(v.duration),
              ),
            );
          }
        }
      } catch (_) {}
    }

    return results;
  }

  static List<YoutubeChannelItem> _extractChannelsFromJson(dynamic data) {
    final channels = <YoutubeChannelItem>[];
    final seenIds = <String>{};

    void extract(dynamic node) {
      if (node is Map) {
        if (node.containsKey('channelRenderer')) {
          final cr = node['channelRenderer'] as Map<String, dynamic>;
          final id = cr['channelId'] as String? ?? '';
          if (id.isNotEmpty && !seenIds.contains(id)) {
            seenIds.add(id);
            final titleMap = cr['title'] as Map<String, dynamic>?;
            final title = titleMap?['simpleText'] as String? ??
                (titleMap?['runs'] as List?)?.firstOrNull?['text'] as String? ??
                '';
            final thumbs = cr['thumbnail']?['thumbnails'] as List?;
            var thumbUrl = thumbs?.isNotEmpty == true
                ? thumbs!.last['url'] as String? ?? ''
                : '';
            if (thumbUrl.startsWith('//')) {
              thumbUrl = 'https:$thumbUrl';
            }

            final videoCountText =
                cr['videoCountText']?['simpleText'] as String? ?? '';
            final subscriberCountText =
                cr['subscriberCountText']?['simpleText'] as String? ?? '';

            int? subscribers;
            int? videos;
            if (videoCountText.toLowerCase().contains('subscriber')) {
              subscribers = _parseSubscribers(videoCountText);
            } else if (videoCountText.toLowerCase().contains('video')) {
              videos = _parseVideos(videoCountText);
            }
            if (subscriberCountText.toLowerCase().contains('subscriber')) {
              subscribers ??= _parseSubscribers(subscriberCountText);
            } else if (subscriberCountText.toLowerCase().contains('video')) {
              videos ??= _parseVideos(subscriberCountText);
            }

            final descRuns = cr['descriptionSnippet']?['runs'] as List?;
            final desc =
                descRuns?.map((r) => r['text'] ?? '').join('') ?? '';

            channels.add(
              YoutubeChannelItem(
                id: id,
                title: title,
                thumbnailUrl: thumbUrl,
                subscriberCount: subscribers,
                videoCount: videos,
                description: desc.isNotEmpty ? desc : null,
              ),
            );
          }
        }
        for (final v in node.values) {
          extract(v);
        }
      } else if (node is List) {
        for (final v in node) {
          extract(v);
        }
      }
    }

    extract(data);
    return channels;
  }

  static int? _parseSubscribers(String text) {
    final clean = text.replaceAll(',', '').trim();
    final match = RegExp(
      r'([\d.]+)\s*([KMBkmb])?\s*(?:subscribers|subscriber)?',
      caseSensitive: false,
    ).firstMatch(clean);
    if (match == null) return null;
    final numVal = double.tryParse(match.group(1) ?? '');
    if (numVal == null) return null;
    final unit = match.group(2)?.toUpperCase();
    if (unit == 'M') return (numVal * 1000000).toInt();
    if (unit == 'K') return (numVal * 1000).toInt();
    if (unit == 'B') return (numVal * 1000000000).toInt();
    return numVal.toInt();
  }

  static int? _parseVideos(String text) {
    final clean = text.replaceAll(',', '').trim();
    final match = RegExp(
      r'([\d.]+)\s*([KMBkmb])?\s*(?:videos|video)?',
      caseSensitive: false,
    ).firstMatch(clean);
    if (match == null) return null;
    final numVal = double.tryParse(match.group(1) ?? '');
    if (numVal == null) return null;
    final unit = match.group(2)?.toUpperCase();
    if (unit == 'M') return (numVal * 1000000).toInt();
    if (unit == 'K') return (numVal * 1000).toInt();
    return numVal.toInt();
  }

  static Duration? _parseDuration(String text) {
    if (text.isEmpty) return null;
    var seconds = 0;
    for (final part in text.split(':')) {
      final value = int.tryParse(part);
      if (value == null) return null;
      seconds = seconds * 60 + value;
    }
    return Duration(seconds: seconds);
  }
}

ChannelUploadsPage _parseChannelUploadsWorker(Map<String, String> params) {
  final body = params['body'] ?? '';
  final channelName = params['channelName'] ?? '';
  final isJson = params['isJson'] == 'true';

  try {
    dynamic data;
    if (isJson) {
      data = jsonDecode(body);
    } else {
      var match = RegExp(
        r'var ytInitialData\s*=\s*(\{.+?\});?\s*<\/script>',
        dotAll: true,
      ).firstMatch(body);
      match ??= RegExp(
        r'window\["ytInitialData"\]\s*=\s*(\{.+?\});?\s*<\/script>',
        dotAll: true,
      ).firstMatch(body);
      if (match == null) {
        return const ChannelUploadsPage(items: []);
      }
      data = jsonDecode(match.group(1)!);
    }
    return YoutubeService._extractChannelUploadsPageFromJson(data, channelName);
  } catch (_) {
    return const ChannelUploadsPage(items: []);
  }
}

ChannelPlaylistsPage _parseChannelPlaylistsWorker(Map<String, String> params) {
  final body = params['body'] ?? '';
  final channelName = params['channelName'] ?? '';
  final isJson = params['isJson'] == 'true';

  try {
    dynamic data;
    if (isJson) {
      data = jsonDecode(body);
    } else {
      var match = RegExp(
        r'var ytInitialData\s*=\s*(\{.+?\});?\s*<\/script>',
        dotAll: true,
      ).firstMatch(body);
      match ??= RegExp(
        r'window\["ytInitialData"\]\s*=\s*(\{.+?\});?\s*<\/script>',
        dotAll: true,
      ).firstMatch(body);
      if (match == null) {
        return const ChannelPlaylistsPage(items: []);
      }
      data = jsonDecode(match.group(1)!);
    }
    return YoutubeService._extractChannelPlaylistsPageFromJson(data, channelName);
  } catch (_) {
    return const ChannelPlaylistsPage(items: []);
  }
}

List<YoutubeSearchItem> _parsePlaylistTracksWorker(Map<String, dynamic> params) {
  final body = params['body'] as String? ?? '';
  final limit = params['limit'] as int? ?? 50;

  try {
    var match = RegExp(
      r'var ytInitialData\s*=\s*(\{.+?\});?\s*<\/script>',
      dotAll: true,
    ).firstMatch(body);
    match ??= RegExp(
      r'window\["ytInitialData"\]\s*=\s*(\{.+?\});?\s*<\/script>',
      dotAll: true,
    ).firstMatch(body);
    if (match == null) return [];

    final data = jsonDecode(match.group(1)!);
    return YoutubeService._extractPlaylistVideosFromJson(data, limit: limit);
  } catch (_) {
    return [];
  }
}

List<YoutubeSearchItem> _parseChannelSearchWorker(Map<String, String> params) {
  final body = params['body'] ?? '';
  final channelName = params['channelName'] ?? '';

  try {
    var match = RegExp(
      r'var ytInitialData\s*=\s*(\{.+?\});?\s*<\/script>',
      dotAll: true,
    ).firstMatch(body);
    match ??= RegExp(
      r'window\["ytInitialData"\]\s*=\s*(\{.+?\});?\s*<\/script>',
      dotAll: true,
    ).firstMatch(body);
    if (match == null) return [];

    final data = jsonDecode(match.group(1)!);
    return YoutubeService._extractChannelVideosFromJson(data, channelName);
  } catch (_) {
    return [];
  }
}

List<YoutubeChannelItem> _parseChannelsWorker(String body) {
  try {
    var match = RegExp(
      r'var ytInitialData\s*=\s*(\{.+?\});?\s*<\/script>',
      dotAll: true,
    ).firstMatch(body);
    match ??= RegExp(
      r'window\["ytInitialData"\]\s*=\s*(\{.+?\});?\s*<\/script>',
      dotAll: true,
    ).firstMatch(body);
    if (match == null) return [];

    final data = jsonDecode(match.group(1)!);
    return YoutubeService._extractChannelsFromJson(data);
  } catch (_) {
    return [];
  }
}


