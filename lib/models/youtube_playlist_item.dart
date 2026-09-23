class YoutubePlaylistItem {
  const YoutubePlaylistItem({
    required this.id,
    required this.title,
    required this.thumbnailUrl,
    this.videoCount,
    this.author,
  });

  final String id;
  final String title;
  final String thumbnailUrl;
  final int? videoCount;
  final String? author;

  String get videoCountLabel {
    if (videoCount == null || videoCount! <= 0) return 'Playlist';
    return '$videoCount ${videoCount == 1 ? 'track' : 'tracks'}';
  }

  factory YoutubePlaylistItem.fromJson(Map<String, dynamic> json) {
    return YoutubePlaylistItem(
      id: json['id'] as String,
      title: json['title'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
      videoCount: json['videoCount'] as int?,
      author: json['author'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'thumbnailUrl': thumbnailUrl,
      if (videoCount != null) 'videoCount': videoCount,
      if (author != null) 'author': author,
    };
  }
}
