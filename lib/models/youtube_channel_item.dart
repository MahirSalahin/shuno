class YoutubeChannelItem {
  const YoutubeChannelItem({
    required this.id,
    required this.title,
    required this.thumbnailUrl,
    this.subscriberCount,
    this.videoCount,
    this.description,
  });

  final String id;
  final String title;
  final String thumbnailUrl;
  final int? subscriberCount;
  final int? videoCount;
  final String? description;

  String? get formattedSubscribers {
    final count = subscriberCount;
    if (count == null || count <= 0) return null;
    if (count >= 1000000) {
      final millions = count / 1000000.0;
      return '${millions.toStringAsFixed(millions >= 10 ? 0 : 1)}M subscribers';
    }
    if (count >= 1000) {
      final thousands = count / 1000.0;
      return '${thousands.toStringAsFixed(thousands >= 10 ? 0 : 1)}K subscribers';
    }
    return '$count subscribers';
  }

  String? get formattedVideoCount {
    final count = videoCount;
    if (count == null || count < 0) return null;
    return '$count videos';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'thumbnailUrl': thumbnailUrl,
        'subscriberCount': subscriberCount,
        'videoCount': videoCount,
        'description': description,
      };

  factory YoutubeChannelItem.fromJson(Map<String, dynamic> json) {
    return YoutubeChannelItem(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
      subscriberCount: json['subscriberCount'] as int?,
      videoCount: json['videoCount'] as int?,
      description: json['description'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is YoutubeChannelItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
