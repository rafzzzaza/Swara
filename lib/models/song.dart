class Song {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final Duration? duration;
  final String? thumbnailUrl;
  final String? artUrl;
  final String? previewUrl;
  final String? genre;
  final bool isLocal;
  final String? localPath;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.duration,
    this.thumbnailUrl,
    this.artUrl,
    this.previewUrl,
    this.genre,
    this.isLocal = false,
    this.localPath,
  });

  String get subtitle => artist;

  Song copyWith({
    String? title,
    String? artist,
    String? album,
    Duration? duration,
    String? thumbnailUrl,
    String? artUrl,
    String? previewUrl,
    String? genre,
    bool? isLocal,
    String? localPath,
  }) =>
      Song(
        id: id,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        album: album ?? this.album,
        duration: duration ?? this.duration,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        artUrl: artUrl ?? this.artUrl,
        previewUrl: previewUrl ?? this.previewUrl,
        genre: genre ?? this.genre,
        isLocal: isLocal ?? this.isLocal,
        localPath: localPath ?? this.localPath,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'duration_ms': duration?.inMilliseconds,
        'thumbnail': thumbnailUrl,
        'art_url': artUrl,
        'preview': previewUrl,
        'genre': genre,
        'is_local': isLocal ? 1 : 0,
      };

  factory Song.fromJson(Map<String, dynamic> json) => Song(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        album: json['album'] as String?,
        duration: json['duration_ms'] != null
            ? Duration(milliseconds: json['duration_ms'] as int)
            : null,
        thumbnailUrl: json['thumbnail'] as String?,
        artUrl: json['art_url'] as String?,
        previewUrl: json['preview'] as String?,
        genre: json['genre'] as String?,
        isLocal: (json['is_local'] as int? ?? 0) == 1,
      );

  @override
  bool operator ==(Object other) =>
      other is Song && other.id == id && other.title == title;

  @override
  int get hashCode => Object.hash(id, title);
}