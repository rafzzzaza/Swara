import 'package:supabase/supabase.dart';

import '../models/play_history_entry.dart';
import '../models/user_profile.dart';

/// Lapisan cloud berbasis Supabase (Postgres + Auth) — mode local-first.
///
/// Aktif HANYA bila kredensial diberikan saat build:
///   flutter build apk --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
/// Tanpa kredensial, [enabled] bernilai false dan seluruh metode menjadi no-op,
/// sehingga aplikasi tetap berjalan penuh secara lokal.
class CloudService {
  static const _url = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const _anonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  static const _usersTable = 'users';
  static const _historyTable = 'play_history';

  SupabaseClient? _client;

  /// True bila kredensial Supabase tersedia di build ini.
  bool get enabled => _url.isNotEmpty && _anonKey.isNotEmpty;

  SupabaseClient? get client {
    if (!enabled) return null;
    return _client ??= SupabaseClient(_url, _anonKey);
  }

  /// Menyimpan profil ke tabel `users` (upsert by user_id).
  Future<void> upsertProfile(UserProfile profile) async {
    final c = client;
    if (c == null) return;
    try {
      await c.from(_usersTable).upsert({
        'user_id': profile.id,
        'display_name': profile.displayName,
        'bio': profile.bio,
        'email': profile.email,
        'avatar_key': profile.avatarKey,
        'favorite_genre': profile.favoriteGenre,
      });
    } catch (_) {
      // Local-first: kegagalan sync tidak mengganggu sesi lokal.
    }
  }

  /// Menyimpan satu riwayat pemutaran ke tabel `play_history`.
  Future<void> pushHistory(PlayHistoryEntry entry, String userId) async {
    final c = client;
    if (c == null) return;
    try {
      await c.from(_historyTable).insert({
        'user_id': userId,
        'song_id': entry.song.id,
        'title': entry.song.title,
        'artist': entry.song.artist,
        'cover_url': entry.song.artUrl ?? entry.song.thumbnailUrl,
        'played_at': entry.playedAt.toIso8601String(),
      });
    } catch (_) {
      // no-op
    }
  }

  /// Mengambil riwayat terbaru dari cloud (opsional, dipakai saat penelusuran).
  Future<List<Map<String, dynamic>>> fetchHistory(String userId,
      {int limit = 50}) async {
    final c = client;
    if (c == null) return const [];
    try {
      final rows = await c
          .from(_historyTable)
          .select()
          .eq('user_id', userId)
          .order('played_at', ascending: false)
          .limit(limit);
      return rows;
    } catch (_) {
      return const [];
    }
  }
}