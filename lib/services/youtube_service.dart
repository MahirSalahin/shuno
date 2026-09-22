import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/youtube_search_item.dart';

class YoutubeService {
  Future<List<YoutubeSearchItem>> search(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return [];

    final youtube = YoutubeExplode();
    try {
      // Fetch only the first page for this milestone.
      // searchContent avoids the upload-date parsing in search(), which can
      // fail on "Streamed ..." dates. Shuno does not need upload dates.
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
