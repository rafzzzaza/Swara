import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Sistem rekomendasi lokal (client-side, tanpa backend).
///
/// Mencatat frekuensi interaksi pengguna — pencarian, klik artis, dan genre
/// lagu yang diputar — lalu menyimpannya di `shared_preferences`. Top artis /
/// genre / kata kunci dipakai Beranda untuk menyusun seksi personalisasi.
class RecommendationService {
  static const _prefsKey = 'swara_recommendations_v1';

  /// Genre yang dikenal untuk menebak genre dari kata kunci pencarian.
  static const knownGenres = [
    'pop', 'rock', 'hip hop', 'hiphop', 'electro', 'rap', 'metal', 'jazz',
    'classique', 'classical', 'country', 'blues', 'dance', 'alternative',
    'dangdut', 'chill', 'focus', 'fonky', 'kpop', 'r&b', 'randb', 'indie',
    'reggae', 'house', 'edm', 'senja',
  ];

  final SharedPreferences _prefs;

  late Map<String, num> _artists;
  late Map<String, num> _genres;
  late Map<String, num> _searches;

  RecommendationService(this._prefs) {
    _load();
  }

  void _load() {
    final raw = _prefs.getString(_prefsKey);
    _artists = {};
    _genres = {};
    _searches = {};
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _artists = _asMap(j['artists']);
      _genres = _asMap(j['genres']);
      _searches = _asMap(j['searches']);
    } catch (_) {
      _artists = {};
      _genres = {};
      _searches = {};
    }
  }

  Map<String, num> _asMap(dynamic value) {
    if (value is! Map) return {};
    return value.map((k, v) => MapEntry('$k', (v is num) ? v : 0));
  }

  String _norm(String s) => s.trim().toLowerCase();

  Future<void> _save() async {
    await _prefs.setString(
      _prefsKey,
      jsonEncode({
        'artists': _artists,
        'genres': _genres,
        'searches': _searches,
      }),
    );
  }

  // ---------------- Recording ----------------

  /// Mencatat pencarian; kata kunci yang mirip genre ikut meningkatkan genre.
  Future<void> recordSearch(String keyword) async {
    final k = _norm(keyword);
    if (k.isEmpty) return;
    _searches[k] = (_searches[k] ?? 0) + 1;
    final genre = _genreFromQuery(k);
    if (genre != null) await recordGenreInternal(genre);
    await _save();
  }

  Future<void> recordArtist(String artist, {num points = 2}) async {
    final k = _norm(artist);
    if (k.isEmpty) return;
    _artists[k] = (_artists[k] ?? 0) + points;
    await _save();
  }

  Future<void> recordGenreInternal(String genre, {num points = 1}) async {
    final k = _norm(genre);
    if (k.isEmpty) return;
    _genres[k] = (_genres[k] ?? 0) + points;
    await _save();
  }

  /// Mencatat lagu yang diputar (artis dibobot lebih tinggi).
  Future<void> recordPlay(String artist, {String? genre}) async {
    await recordArtist(artist, points: 3);
    if (genre != null && genre.trim().isNotEmpty) {
      await recordGenreInternal(genre, points: 2);
    }
  }

  String? _genreFromQuery(String query) {
    for (final g in knownGenres) {
      if (query.contains(g)) return g;
    }
    return null;
  }

  // ---------------- Top lists ----------------

  List<String> topArtists({int limit = 3}) =>
      _topKeys(_artists, limit);

  List<String> topGenres({int limit = 3}) => _topKeys(_genres, limit);

  List<String> topSearches({int limit = 3}) => _topKeys(_searches, limit);

  List<String> _topKeys(Map<String, num> map, int limit) {
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).map((e) => e.key).toList();
  }

  /// Apakah belum ada data pengguna sama sekali (pengguna baru).
  bool get isEmpty =>
      _artists.isEmpty && _genres.isEmpty && _searches.isEmpty;

  /// Menghapus seluruh data preferensi.
  Future<void> clear() async {
    _artists = {};
    _genres = {};
    _searches = {};
    await _save();
  }
}