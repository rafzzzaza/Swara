import 'dart:async';

import '../models/play_history_entry.dart';
import '../models/song.dart';
import 'cloud_service.dart';
import 'database_service.dart';

/// Mengatur pencatatan riwayat pemutaran: selalu tersimpan di SQLite lokal,
/// lalu di-sync ke Supabase bila koneksi cloud aktif (best-effort).
class HistoryService {
  final DatabaseService _db;
  final CloudService _cloud;
  final String userId;

  PlayHistoryEntry? _last;
  DateTime? _lastAt;

  HistoryService(this._db, this._cloud, this.userId);

  Future<void> record(Song song) async {
    final now = DateTime.now();
    if (_last != null &&
        _last!.song.id == song.id &&
        now.difference(_lastAt!).inSeconds < 30) {
      return;
    }
    _lastAt = now;
    _last = PlayHistoryEntry(song: song, playedAt: now);
    final id = await _db.addHistory(_last!);
    final entry = _last!.copyWith(id: id);
    _last = entry;
    unawaited(_cloud.pushHistory(entry, userId));
  }

  Future<List<PlayHistoryEntry>> latest({int limit = 200}) =>
      _db.getHistory(limit: limit);

  Future<void> clear() async {
    await _db.clearHistory();
    _last = null;
    _lastAt = null;
  }
}