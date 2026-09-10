import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/song.dart';
import '../services/music_api_service.dart';
import '../services/recommendation_service.dart';

class SearchProvider extends ChangeNotifier {
  final MusicApiService _api;
  final RecommendationService _rec;

  List<Song> _results = [];
  List<String> _suggestions = [];
  bool _searching = false;
  String _query = '';
  Timer? _debounce;

  SearchProvider(this._api, this._rec);

  List<Song> get results => _results;
  List<String> get suggestions => _suggestions;
  bool get searching => _searching;
  String get query => _query;

  void onQueryChanged(String query) {
    _query = query;
    notifyListeners();
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      _searching = false;
      _results = [];
      notifyListeners();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      _searching = true;
      notifyListeners();
      try {
        _results = await _api.searchSongs(query.trim(), limit: 24);
        await _rec.recordSearch(query.trim());
      } catch (_) {
        _results = [];
      }
      _searching = false;
      notifyListeners();
    });
  }

  Future<void> loadSuggestions() async {
    try {
      final artists = await _api.topArtists(limit: 10);
      _suggestions = [
        for (final a in artists) a.name,
      ];
      if (_suggestions.isEmpty) {
        _suggestions = ['Pop', 'Rock', 'Dangdut', 'Hip-Hop'];
      }
      notifyListeners();
    } catch (_) {
      _suggestions = ['Pop', 'Rock', 'Dangdut', 'Hip-Hop'];
      notifyListeners();
    }
  }

  Future<void> searchNow(String query) async {
    _query = query;
    notifyListeners();
    _searching = true;
    notifyListeners();
    try {
      _results = await _api.searchSongs(query.trim(), limit: 24);
      await _rec.recordSearch(query.trim());
    } catch (_) {
      _results = [];
    }
    _searching = false;
    notifyListeners();
  }

  void clear() {
    _debounce?.cancel();
    _query = '';
    _results = [];
    _searching = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}