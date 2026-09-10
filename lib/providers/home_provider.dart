import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/album.dart';
import '../models/artist.dart';
import '../models/genre.dart';
import '../models/song.dart';
import '../services/music_api_service.dart';
import '../services/recommendation_service.dart';

class HomeProvider extends ChangeNotifier {
  final MusicApiService _api;
  final RecommendationService _rec;

  List<Song> _trending = [];
  List<Album> _newReleases = [];
  List<Artist> _artists = [];
  List<Genre> _genres = [];
  Genre? _activeGenre;
  List<Song> _moodTracks = [];
  List<Song> _defaultRecs = [];

  List<Song> _personalized = [];
  List<Song> _bySearches = [];
  List<Song> _indonesia = [];
  List<Song> _global = [];

  bool _loading = true;
  bool _error = false;
  bool _moodLoading = false;

  HomeProvider(this._api, this._rec);

  List<Song> get trending => _trending;
  List<Album> get newReleases => _newReleases;
  List<Song> get recommendations =>
      _moodTracks.isEmpty ? _defaultRecs : _moodTracks;
  List<Artist> get artists => _artists;
  List<Genre> get genres => _genres;
  Genre? get activeGenre => _activeGenre;
  List<Song> get personalized => _personalized;
  List<Song> get bySearches => _bySearches;
  List<Song> get indonesia => _indonesia;
  List<Song> get global => _global;
  bool get loading => _loading;
  bool get error => _error;
  bool get moodLoading => _moodLoading;
  String get moodSectionTitle =>
      _activeGenre == null ? 'Rekomendasi Musik' : _activeGenre!.name;

  Future<void> load() async {
    _loading = true;
    _error = false;
    notifyListeners();
    try {
      await Future.wait([
        _api.chartTracks(limit: 24).then((v) => _trending = v),
        _api.newAlbums(limit: 20).then((v) => _newReleases = v),
        _api.topArtists(limit: 20).then((v) => _artists = v),
        _loadGenres(),
      ]);
      if (_defaultRecs.isEmpty) {
        _defaultRecs = await _api.searchSongs('pop top', limit: 20);
      }
    } catch (_) {
      _error = true;
    }
    _loading = false;
    if (!_error) {
      await Future.wait([
        _loadPersonalized(),
        _loadRegional(),
      ]);
    }
    notifyListeners();
  }

  /// Re-run personalisasi saja (dipanggil tiap Beranda dibuka kembali).
  Future<void> refreshPersonalized() async {
    if (_loading) return;
    await _loadPersonalized();
    notifyListeners();
  }

  Future<void> _loadRegional() async {
    await Future.wait([
      _safeSearch(() => _api.indonesiaHits(limit: 20), (v) => _indonesia = v),
      _safeSearch(() => _api.globalHits(limit: 20), (v) => _global = v),
    ]);
  }

  Future<void> _loadPersonalized() async {
    final artists = _rec.topArtists(limit: 3);
    final genres = _rec.topGenres(limit: 3);
    final searches = _rec.topSearches(limit: 3);
    final hasHistory = artists.isNotEmpty || genres.isNotEmpty;

    // Pengguna baru: rekomendasi default = lagu trending umum.
    if (!hasHistory) {
      _personalized = _trending.isEmpty ? _defaultRecs : _trending;
    } else {
      final groups = <Future<List<Song>>>[
        for (final a in artists)
          _safeSearchValue(() => _api.searchSongs('$a top', limit: 10)),
        for (final g in genres)
          _safeSearchValue(() => _api.genreTracks(g, limit: 10)),
      ];
      final results = List.of(await Future.wait(groups))..removeWhere((l) => l.isEmpty);
      _personalized = _mergeUnique(results).take(20).toList();
      if (_personalized.isEmpty) {
        _personalized = _trending;
      }
    }

    if (searches.isEmpty) {
      _bySearches = [];
    } else {
      final groups = [
        for (final s in searches)
          _safeSearchValue(() => _api.searchSongs(s, limit: 10)),
      ];
      final results = List.of(await Future.wait(groups))..removeWhere((l) => l.isEmpty);
      _bySearches = _mergeUnique(results).take(20).toList();
    }
  }

  Future<void> _safeSearch(Future<List<Song>> Function() task,
      void Function(List<Song>) setter) async {
    final v = await _safeSearchValue(task);
    setter(v);
  }

  Future<List<Song>> _safeSearchValue(
      Future<List<Song>> Function() task) async {
    try {
      return await task();
    } catch (_) {
      return const [];
    }
  }

  List<Song> _mergeUnique(List<List<Song>> groups) {
    final seen = <String>{};
    final out = <Song>[];
    for (final group in groups) {
      for (final song in group) {
        if (seen.add(song.id)) out.add(song);
      }
    }
    return out;
  }

  Future<void> _loadGenres() async {
    final all = await _api.genres();
    const keywords = [
      'Pop', 'Rock', 'Hip-Hop', 'Electro', 'Rap',
      'Metal', 'Jazz', 'Classique', 'Country', 'Blues', 'Dance', 'Alternative',
    ];
    final picked = <Genre>[];
    for (final kw in keywords) {
      Genre? match;
      for (final g in all) {
        if (g.name.contains(kw)) {
          match = g;
          break;
        }
      }
      if (match != null && !picked.any((p) => p.id == match?.id)) {
        picked.add(match);
      }
    }
    _genres = picked.isEmpty ? all.take(10).toList() : picked.take(9).toList();
  }

  Future<void> selectGenre(Genre genre) async {
    if (_activeGenre?.id == genre.id) {
      _activeGenre = null;
      _moodTracks = [];
      notifyListeners();
      return;
    }
    _activeGenre = genre;
    _moodLoading = true;
    notifyListeners();
    try {
      final tracks = await _api.genreTracks(genre.name, limit: 24);
      _moodTracks = [
        for (final t in tracks) t.copyWith(genre: genre.name),
      ];
    } catch (_) {
      _moodTracks = [];
    }
    _moodLoading = false;
    notifyListeners();
  }

  Future<List<Song>> albumSongs(Album album) => _api.albumTracks(album);

  Future<List<Song>> artistSongs(Artist artist) => _api.artistTracks(artist);
}