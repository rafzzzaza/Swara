import 'song.dart';

/// Satu entri riwayat pemutaran (lagu + waktu diputar).
class PlayHistoryEntry {
  /// Primary key lokal (SQLite). Null sebelum disimpan.
  final int? id;

  final Song song;
  final DateTime playedAt;

  const PlayHistoryEntry({
    this.id,
    required this.song,
    required this.playedAt,
  });

  PlayHistoryEntry copyWith({
    int? id,
    Song? song,
    DateTime? playedAt,
  }) =>
      PlayHistoryEntry(
        id: id ?? this.id,
        song: song ?? this.song,
        playedAt: playedAt ?? this.playedAt,
      );

  Map<String, dynamic> toJson() => {
        'song': song.toJson(),
        'played_at': playedAt.toIso8601String(),
      };

  factory PlayHistoryEntry.fromJson(Map<String, dynamic> json) =>
      PlayHistoryEntry(
        id: json['id'] as int?,
        song: Song.fromJson(
            (json['song'] as Map).cast<String, dynamic>()),
        playedAt: DateTime.tryParse(json['played_at'] as String? ?? '') ??
            DateTime.now(),
      );
}