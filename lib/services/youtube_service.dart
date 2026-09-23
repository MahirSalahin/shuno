import 'dart:convert';
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

class YoutubeService {
  YoutubeExplode? _client;
  YoutubeExplode get _yt => _client ??= YoutubeExplode();

  void dispose() {
    _client?.close();
    _client = null;
  }

  Future<Uri> resolveAudioUrl(String videoId, {bool highQuality = true}) async {
    final youtube = YoutubeExplode();
    try {
      final manifest = await youtube.videos.streamsClient
          .getManifest(videoId)
          .timeout(const Duration(seconds: 30));

      // Prioritize Stream 18 (universal 360p MP4 with AAC stereo audio, ratebypass=yes, unthrottled)
      final stream18 = manifest.muxed.where((s) => s.tag == 18).firstOrNull;
      if (stream18 != null) {
        return stream18.url;
      }

      if (manifest.audioOnly.isEmpty) {
        if (manifest.muxed.isNotEmpty) {
          return manifest.muxed.first.url;
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
      return stream.url;
    } finally {
      youtube.close();
    }
  }

  Future<List<Uri>> resolveAudioUrls(String videoId, {bool highQuality = true}) async {
    final single = await resolveAudioUrl(videoId, highQuality: highQuality);
    return [single];
  }

  Future<List<YoutubeSearchItem>> search(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return [];

    final youtube = YoutubeExplode();
    try {
      final results = await youtube.search
          .searchContent(trimmedQuery, filter: TypeFilters.video)
          .timeout(const Duration(seconds: 20));

      return results
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
    } finally {
      youtube.close();
    }
  }

  Future<List<YoutubeChannelItem>> searchChannels(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return [];

    final youtube = YoutubeExplode();
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
    } finally {
      youtube.close();
    }
  }

  Future<YoutubeChannelItem?> getChannel(String channelId) async {
    if (channelId.trim().isEmpty) return null;
    final youtube = YoutubeExplode();
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
    } finally {
      youtube.close();
    }
  }

  Future<List<YoutubeSearchItem>> getChannelVideos(
    String channelId, {
    String? channelName,
  }) async {
    final youtube = YoutubeExplode();
    try {
      final pageUploads = await youtube.channels
          .getUploadsFromPage(channelId)
          .timeout(const Duration(seconds: 15));

      final videos = pageUploads
          .map(
            (v) => YoutubeSearchItem(
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
          )
          .toList();

      if (videos.isNotEmpty) return videos;

      // Fallback: dedicated uploads stream for this channel
      final uploadsStream = youtube.channels.getUploads(channelId).take(30);
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
      return streamVideos;
    } catch (_) {
      return [];
    } finally {
      youtube.close();
    }
  }

  Future<ChannelUploadsPage> getChannelUploadsPage(
    String channelId, {
    String? channelName,
    dynamic continuation,
  }) async {
    try {
      if (continuation != null) {
        if (continuation is ChannelUploadsList) {
          final nextUploads = await continuation
              .nextPage()
              .timeout(const Duration(seconds: 15));
          if (nextUploads != null && nextUploads.isNotEmpty) {
            final videos = nextUploads
                .map(
                  (v) => YoutubeSearchItem(
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
                )
                .toList();
            return ChannelUploadsPage(
              items: videos,
              hasMore: true,
              continuation: nextUploads,
            );
          }
          return const ChannelUploadsPage(items: [], hasMore: false);
        }
      }

      // Initial page: strictly query channel uploads from official uploads page
      final pageUploads = await _yt.channels
          .getUploadsFromPage(channelId)
          .timeout(const Duration(seconds: 15));

      final videos = pageUploads
          .map(
            (v) => YoutubeSearchItem(
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

  Future<List<YoutubePlaylistItem>> getChannelPlaylists(
    String channelName, {
    String? channelId,
  }) async {
    final id = channelId?.trim() ?? '';
    if (id.isEmpty) return [];

    try {
      final playlistsUrl = 'https://www.youtube.com/channel/$id/playlists?hl=en';
      final response = await http.get(
        Uri.parse(playlistsUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return [];

      final match = RegExp(
        r'var ytInitialData = (\{.+?\});<\/script>',
        dotAll: true,
      ).firstMatch(response.body);
      if (match == null) return [];

      final data = jsonDecode(match.group(1)!);
      return _extractChannelPlaylistsFromJson(data, channelName);
    } catch (_) {
      return [];
    }
  }

  List<YoutubePlaylistItem> _extractChannelPlaylistsFromJson(
    dynamic node,
    String defaultAuthor,
  ) {
    final results = <YoutubePlaylistItem>[];
    final seenIds = <String>{};

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
    return results;
  }

  Future<List<YoutubeSearchItem>> getPlaylistTracks(
    String playlistId, {
    int limit = 50,
  }) async {
    if (playlistId.trim().isEmpty) return [];
    try {
      final videoStream = _yt.playlists.getVideos(playlistId).take(limit);
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
      final searchUrl =
          'https://www.youtube.com/channel/$id/search?query=${Uri.encodeComponent(trimmedQuery)}&hl=en';
      final response = await http.get(
        Uri.parse(searchUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return [];

      final match = RegExp(
        r'var ytInitialData = (\{.+?\});<\/script>',
        dotAll: true,
      ).firstMatch(response.body);
      if (match == null) return [];

      final data = jsonDecode(match.group(1)!);
      return _extractChannelVideosFromJson(data, channelName ?? '');
    } catch (_) {
      return [];
    }
  }

  List<YoutubeSearchItem> _extractChannelVideosFromJson(
    dynamic node,
    String defaultAuthor,
  ) {
    final results = <YoutubeSearchItem>[];
    final seenIds = <String>{};

    void walk(dynamic obj) {
      if (obj is Map<String, dynamic>) {
        if (obj.containsKey('videoRenderer')) {
          final vr = obj['videoRenderer'] as Map<String, dynamic>;
          final videoId = vr['videoId']?.toString() ?? '';
          if (videoId.isNotEmpty && seenIds.add(videoId)) {
            final titleObj = vr['title'];
            var title = 'Track';
            if (titleObj is Map<String, dynamic>) {
              if (titleObj['runs'] is List && (titleObj['runs'] as List).isNotEmpty) {
                title = titleObj['runs'][0]['text']?.toString() ?? 'Track';
              } else if (titleObj['simpleText'] != null) {
                title = titleObj['simpleText'].toString();
              }
            }

            var author = defaultAuthor;
            final ownerObj = vr['ownerText'] ?? vr['longBylineText'] ?? vr['shortBylineText'];
            if (ownerObj is Map<String, dynamic> &&
                ownerObj['runs'] is List &&
                (ownerObj['runs'] as List).isNotEmpty) {
              final ownerStr = ownerObj['runs'][0]['text']?.toString();
              if (ownerStr != null && ownerStr.isNotEmpty) author = ownerStr;
            }

            final durationText = vr['lengthText']?['simpleText']?.toString() ?? '';
            final duration = _parseDuration(durationText);

            var thumb = ThumbnailSet(videoId).mediumResUrl;
            final thumbs = vr['thumbnail']?['thumbnails'];
            if (thumbs is List && thumbs.isNotEmpty) {
              thumb = thumbs.last['url']?.toString() ?? thumb;
            }

            results.add(
              YoutubeSearchItem(
                id: videoId,
                title: title,
                channelName: author,
                thumbnailUrl: thumb,
                duration: duration,
              ),
            );
          }
        } else if (obj.containsKey('lockupViewModel')) {
          final lvm = obj['lockupViewModel'] as Map<String, dynamic>;
          final contentType = lvm['contentType']?.toString() ?? '';
          final contentId = lvm['contentId']?.toString() ?? '';
          if (contentType == 'LOCKUP_CONTENT_TYPE_VIDEO' &&
              contentId.isNotEmpty &&
              seenIds.add(contentId)) {
            final titleMeta = lvm['metadata']?['lockupMetadataViewModel']?['title'];
            final title = titleMeta?['content']?.toString() ?? 'Track';
            results.add(
              YoutubeSearchItem(
                id: contentId,
                title: title,
                channelName: defaultAuthor,
                thumbnailUrl: ThumbnailSet(contentId).mediumResUrl,
                duration: null,
              ),
            );
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
    return results;
  }


  Future<List<YoutubeSearchItem>> getRelatedVideos(
    YoutubeSearchItem currentItem,
  ) async {
    final youtube = YoutubeExplode();
    try {
      try {
        final video = await youtube.videos.get(currentItem.id);
        final related = await youtube.videos.getRelatedVideos(video);
        if (related != null && related.isNotEmpty) {
          return related
              .where((v) => v.id.value != currentItem.id)
              .map(
                (v) => YoutubeSearchItem(
                  id: v.id.value,
                  title: v.title,
                  channelName: v.author,
                  thumbnailUrl: ThumbnailSet(v.id.value).mediumResUrl,
                  duration: v.duration,
                ),
              )
              .toList();
        }
      } catch (_) {
        // Fallback to query below
      }

      final query = '${currentItem.title} ${currentItem.channelName}';
      final results = await youtube.search
          .searchContent(query, filter: TypeFilters.video)
          .timeout(const Duration(seconds: 15));

      return results
          .whereType<SearchVideo>()
          .where((v) => v.id.value != currentItem.id)
          .map(
            (v) => YoutubeSearchItem(
              id: v.id.value,
              title: v.title,
              channelName: v.author,
              thumbnailUrl: ThumbnailSet(v.id.value).mediumResUrl,
              duration: _parseDuration(v.duration),
            ),
          )
          .toList();
    } finally {
      youtube.close();
    }
  }

  Duration? _parseDuration(String text) {
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
