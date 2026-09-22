import 'youtube_search_item.dart';

class Playlist {
  Playlist({
    required this.id,
    required this.title,
    DateTime? createdAt,
    List<YoutubeSearchItem>? items,
  }) : createdAt = createdAt ?? DateTime.now(),
       items = items ?? [];

  final String id;
  String title;
  final DateTime createdAt;
  final List<YoutubeSearchItem> items;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'items': items.map((e) => e.toJson()).toList(),
  };

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as String,
      title: json['title'] as String,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      items: (json['items'] as List<dynamic>? ?? [])
          .map((e) => YoutubeSearchItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
