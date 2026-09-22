import 'youtube_search_item.dart';

class DownloadItem {
  const DownloadItem({
    required this.item,
    required this.localPath,
    required this.fileSize,
    required this.downloadedAt,
    this.lastPositionMs = 0,
    this.lastPlayedAt,
  });

  final YoutubeSearchItem item;
  final String localPath;
  final int fileSize;
  final DateTime downloadedAt;
  final int lastPositionMs;
  final DateTime? lastPlayedAt;

  Duration get lastPosition => Duration(milliseconds: lastPositionMs);

  double get playbackProgress {
    final totalMs = item.duration?.inMilliseconds ?? 0;
    if (totalMs <= 0 || lastPositionMs <= 0) return 0.0;
    return (lastPositionMs / totalMs).clamp(0.0, 1.0);
  }

  /// True if the user has played more than 3 seconds and is not within the last 5 seconds.
  bool get hasPlaybackProgress {
    if (lastPositionMs < 3000) return false;
    final totalMs = item.duration?.inMilliseconds ?? 0;
    if (totalMs > 0 && lastPositionMs >= totalMs - 5000) return false;
    return true;
  }

  bool get isCompleted => true;
  YoutubeSearchItem toSearchItem() => item;

  String get formattedSize {
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get formattedLastPosition {
    final d = lastPosition;
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  DownloadItem copyWith({
    YoutubeSearchItem? item,
    String? localPath,
    int? fileSize,
    DateTime? downloadedAt,
    int? lastPositionMs,
    DateTime? lastPlayedAt,
  }) {
    return DownloadItem(
      item: item ?? this.item,
      localPath: localPath ?? this.localPath,
      fileSize: fileSize ?? this.fileSize,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      lastPositionMs: lastPositionMs ?? this.lastPositionMs,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'item': item.toJson(),
    'localPath': localPath,
    'fileSize': fileSize,
    'downloadedAt': downloadedAt.toIso8601String(),
    'lastPositionMs': lastPositionMs,
    if (lastPlayedAt != null) 'lastPlayedAt': lastPlayedAt!.toIso8601String(),
  };

  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    return DownloadItem(
      item: YoutubeSearchItem.fromJson(json['item'] as Map<String, dynamic>),
      localPath: json['localPath'] as String,
      fileSize: json['fileSize'] as int? ?? 0,
      downloadedAt: json['downloadedAt'] != null
          ? DateTime.tryParse(json['downloadedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      lastPositionMs: json['lastPositionMs'] as int? ?? 0,
      lastPlayedAt: json['lastPlayedAt'] != null
          ? DateTime.tryParse(json['lastPlayedAt'] as String)
          : null,
    );
  }
}
