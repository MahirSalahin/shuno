import 'youtube_search_item.dart';

class DownloadItem {
  const DownloadItem({
    required this.item,
    required this.localPath,
    required this.fileSize,
    required this.downloadedAt,
  });

  final YoutubeSearchItem item;
  final String localPath;
  final int fileSize;
  final DateTime downloadedAt;

  String get formattedSize {
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Map<String, dynamic> toJson() => {
    'item': item.toJson(),
    'localPath': localPath,
    'fileSize': fileSize,
    'downloadedAt': downloadedAt.toIso8601String(),
  };

  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    return DownloadItem(
      item: YoutubeSearchItem.fromJson(json['item'] as Map<String, dynamic>),
      localPath: json['localPath'] as String,
      fileSize: json['fileSize'] as int? ?? 0,
      downloadedAt: json['downloadedAt'] != null
          ? DateTime.tryParse(json['downloadedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
