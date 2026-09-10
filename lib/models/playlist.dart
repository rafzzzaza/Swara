class Playlist {
  final int? id;
  final String name;
  final int songCount;

  const Playlist({this.id, required this.name, this.songCount = 0});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as int?,
        name: json['name'] as String,
        songCount: json['song_count'] as int? ?? 0,
      );
}