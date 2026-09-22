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
}
