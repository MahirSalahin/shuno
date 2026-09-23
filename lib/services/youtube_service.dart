import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/youtube_channel_item.dart';
import '../models/youtube_search_item.dart';

class YoutubeService {
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
      final query = channelName ?? channelId;
      final results = await youtube.search
          .searchContent(query, filter: TypeFilters.video)
          .timeout(const Duration(seconds: 20));

      final videos = results
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

      if (videos.isNotEmpty) return videos;

      final pageUploads = await youtube.channels
          .getUploadsFromPage(channelId)
          .timeout(const Duration(seconds: 15));

      return pageUploads
          .map(
            (v) => YoutubeSearchItem(
              id: v.id.value,
              title: v.title.isNotEmpty
                  ? v.title
                  : (channelName != null ? '$channelName Track' : 'Track'),
              channelName: channelName ?? '',
              thumbnailUrl: v.thumbnails.mediumResUrl,
              duration: (v.duration != null && v.duration! > Duration.zero)
                  ? v.duration
                  : null,
            ),
          )
          .toList();
    } catch (_) {
      return [];
    } finally {
      youtube.close();
    }
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
