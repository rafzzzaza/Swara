import 'song.dart';

class DownloadRecord {
  final String songId;
  final String title;
  final String artist;
  final String filePath;
  final String? thumbnailUrl;
  final DateTime createdAt;

  const DownloadRecord({
    required this.songId,
    required this.title,
    required this.artist,
    required this.filePath,
    this.thumbnailUrl,
    required this.createdAt,
  });

  Song get asSong => Song(
        id: songId,
        title: title,
        artist: artist,
        thumbnailUrl: thumbnailUrl,
        isLocal: true,
        localPath: filePath,
      );

  Map<String, dynamic> toJson() => {
        'song_id': songId,
        'title': title,
        'artist': artist,
        'file_path': filePath,
        'thumbnail': thumbnailUrl,
        'created_at': createdAt.toIso8601String(),
      };

  factory DownloadRecord.fromJson(Map<String, dynamic> json) =>
      DownloadRecord(
        songId: json['song_id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        filePath: json['file_path'] as String,
        thumbnailUrl: json['thumbnail'] as String?,
        createdAt:
            DateTime.parse(json['created_at'] as String),
      );
}