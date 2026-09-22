class YoutubeSearchItem {
  const YoutubeSearchItem({
    required this.id,
    required this.title,
    required this.channelName,
    required this.thumbnailUrl,
    this.duration,
  });

  final String id;
  final String title;
  final String channelName;
  final String thumbnailUrl;
  final Duration? duration;

  String? get durationLabel {
    final value = duration;
    if (value == null) return null;

    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    if (value.inHours == 0) return '${value.inMinutes}:$seconds';

    final minutes = (value.inMinutes % 60).toString().padLeft(2, '0');
    return '${value.inHours}:$minutes:$seconds';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'channelName': channelName,
    'thumbnailUrl': thumbnailUrl,
    'durationSeconds': duration?.inSeconds,
  };

  factory YoutubeSearchItem.fromJson(Map<String, dynamic> json) {
    return YoutubeSearchItem(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      channelName: json['channelName'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
      duration: json['durationSeconds'] != null
          ? Duration(seconds: json['durationSeconds'] as int)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is YoutubeSearchItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
