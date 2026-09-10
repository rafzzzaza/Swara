import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:music_stream_app/models/play_history_entry.dart';
import 'package:music_stream_app/models/song.dart';
import 'package:music_stream_app/models/user_profile.dart';
import 'package:music_stream_app/providers/auth_provider.dart';
import 'package:music_stream_app/services/auth_service.dart';
import 'package:music_stream_app/services/cloud_service.dart';
import 'package:music_stream_app/services/recommendation_service.dart';
import 'package:music_stream_app/utils/time_ago.dart';

Song _song(String id, String title, String artist,
        {String? genre, Duration? duration}) =>
    Song(
      id: id,
      title: title,
      artist: artist,
      genre: genre,
      duration: duration ?? const Duration(seconds: 180),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Song model', () {
    test('copyWith menambah genre tanpa mengubah field lain', () {
      final song = _song('1', 'Lagu A', 'Artis A', genre: 'Pop');
      final updated = song.copyWith(genre: 'Rock');
      expect(updated.genre, 'Rock');
      expect(updated.title, 'Lagu A');
      expect(updated.artist, 'Artis A');
      expect(updated.id, '1');
    });

    test('toJson/fromJson round-trip mempertahankan genre', () {
      final song = _song('2', 'Lagu B', 'Artis B',
          genre: 'Hip-Hop', duration: const Duration(seconds: 210));
      final restored = Song.fromJson(song.toJson());
      expect(restored.id, '2');
      expect(restored.genre, 'Hip-Hop');
      expect(restored.duration, const Duration(seconds: 210));
      expect(restored.isLocal, false);
    });
  });

  group('UserProfile model', () {
    test('copyWith & json round-trip', () {
      final p = const UserProfile(
        id: 'u1',
        displayName: 'Aku',
        bio: 'Bio',
        email: 'a@b.c',
        avatarKey: 'headphones',
        favoriteGenre: 'Pop',
      );
      final json = p.toJson();
      final restored = UserProfile.fromJson(json);
      expect(restored.displayName, 'Aku');
      expect(restored.avatarKey, 'headphones');
      expect(restored.favoriteGenre, 'Pop');

      final edited = p.copyWith(displayName: 'Baru');
      expect(edited.displayName, 'Baru');
      expect(edited.bio, 'Bio');
    });

    test('fromJson pakai default untuk field kosong', () {
      final restored = UserProfile.fromJson({'id': 'u2', 'displayName': 'X'});
      expect(restored.bio, '');
      expect(restored.email, '');
      expect(restored.avatarKey, isNull);
    });
  });

  group('PlayHistoryEntry', () {
    test('round-trip json', () {
      final song = _song('1', 'Lagu', 'Artis');
      final entry = PlayHistoryEntry(
          id: 7,
          song: song,
          playedAt: DateTime(2025, 1, 1, 12, 30));
      final restored =
          PlayHistoryEntry.fromJson({...entry.toJson(), 'id': 7});
      expect(restored.id, 7);
      expect(restored.song.id, '1');
      expect(restored.playedAt, DateTime(2025, 1, 1, 12, 30));
    });
  });

  group('RecommendationService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('pengguna baru: isEmpty true & top list kosong', () async {
      final prefs = await SharedPreferences.getInstance();
      final rec = RecommendationService(prefs);
      expect(rec.isEmpty, true);
      expect(rec.topArtists(), isEmpty);
      expect(rec.topGenres(), isEmpty);
      expect(rec.topSearches(), isEmpty);
    });

    test('recordPlay menambah poin artis & genre', () async {
      final prefs = await SharedPreferences.getInstance();
      final rec = RecommendationService(prefs);
      await rec.recordPlay('Taylor Swift', genre: 'Pop');
      await rec.recordPlay('Taylor Swift', genre: 'Pop');
      expect(rec.topArtists(), ['taylor swift']);
      expect(rec.topGenres(), ['pop']);
      expect(rec.isEmpty, false);
    });

    test('artis favorit diurutkan berdasar poin', () async {
      final prefs = await SharedPreferences.getInstance();
      final rec = RecommendationService(prefs);
      await rec.recordPlay('A', genre: 'Pop');
      await rec.recordPlay('B', genre: 'Rock');
      await rec.recordPlay('A', genre: 'Pop');
      expect(rec.topArtists(), ['a', 'b']);
      expect(rec.topGenres(), ['pop', 'rock']);
    });

    test('genre di-search (recordSearch) digunakan', () async {
      final prefs = await SharedPreferences.getInstance();
      final rec = RecommendationService(prefs);
      // 'Pop' ada di knownGenres → genre Pop ikut tercatat via recordSearch.
      await rec.recordSearch('Pop Indonesia');
      expect(rec.topSearches().contains('pop indonesia'), true);
      expect(rec.topGenres().contains('pop'), true);
    });

    test('clear menghapus semua data', () async {
      final prefs = await SharedPreferences.getInstance();
      final rec = RecommendationService(prefs);
      await rec.recordPlay('A', genre: 'Pop');
      expect(rec.isEmpty, false);
      await rec.clear();
      expect(rec.isEmpty, true);
    });
  });

  group('CloudService (local-first)', () {
    test('tanpa dart-define: disabled & semua operasi no-op', () async {
      final cloud = CloudService();
      expect(cloud.enabled, false);
      const profile = UserProfile(id: 'u1', displayName: 'A');
      await cloud.upsertProfile(profile.copyWith(avatarKey: 'headphones'));
      final history = await cloud.fetchHistory('u1');
      expect(history, isEmpty);
    });
  });

  group('AuthService & AuthProvider (mode offline)', () {
    test('tanpa dart-define: online disabled, currentUser null, signOut no-op',
        () async {
      expect(AuthService.enabled, false);
      final service = AuthService();
      expect(await service.currentUser(), isNull);
      await service.signOut();
    });

    test('load tanpa konfigurasi → langsung jadi guest (aplikasi tetap jalan)',
        () async {
      final provider = AuthProvider(AuthService());
      await provider.load();
      expect(provider.initialized, true);
      expect(provider.isGuest, true);
      expect(provider.loggedIn, false);
      provider.continueAsGuest();
      expect(provider.initialized, true);
    });
  });

  group('timeAgo', () {
    final now = DateTime(2026, 9, 10, 12, 0);

    test('format relatif dalam Bahasa Indonesia', () {
      expect(timeAgo(now.subtract(const Duration(seconds: 10)), now: now),
          'Baru saja');
      expect(timeAgo(now.subtract(const Duration(minutes: 5)), now: now),
          '5 menit yang lalu');
      expect(timeAgo(now.subtract(const Duration(hours: 3)), now: now),
          '3 jam yang lalu');
      expect(timeAgo(now.subtract(const Duration(days: 1)), now: now),
          'Kemarin');
      expect(timeAgo(now.subtract(const Duration(days: 4)), now: now),
          '4 hari yang lalu');
    });

    test('tanggal lama jadi format tanggal', () {
      expect(timeAgo(DateTime(2025, 5, 12, 9, 0), now: now), '12 Mei 2025');
    });
  });
}