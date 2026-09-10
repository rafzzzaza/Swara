import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/album.dart';
import '../models/artist.dart';
import '../models/genre.dart';
import '../models/song.dart';
import '../services/music_api_service.dart';

class HomeProvider extends ChangeNotifier {
  final MusicApiService _api;

  List<Song> _trending = [];
  List<Album> _newReleases = [];
  List<Artist> _artists = [];
  List<Genre> _genres = [];
  Genre? _activeGenre;
  List<Song> _moodTracks = [];
  List<Song> _defaultRecs = [];

  bool _loading = true;
  bool _error = false;
  bool _moodLoading = false;

  HomeProvider(this._api);

  List<Song> get trending => _trending;
  List<Album> get newReleases => _newReleases;
  List<Song> get recommendations =>
      _moodTracks.isEmpty ? _defaultRecs : _moodTracks;
  List<Artist> get artists => _artists;
  List<Genre> get genres => _genres;
  Genre? get activeGenre => _activeGenre;
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
    notifyListeners();
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
      _moodTracks = await _api.genreTracks(genre.name, limit: 24);
    } catch (_) {
      _moodTracks = [];
    }
    _moodLoading = false;
    notifyListeners();
  }

  Future<List<Song>> albumSongs(Album album) => _api.albumTracks(album);

  Future<List<Song>> artistSongs(Artist artist) => _api.artistTracks(artist);
}