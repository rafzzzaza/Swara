import 'package:flutter/foundation.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import '../services/database_service.dart';

class PlaylistProvider extends ChangeNotifier {
  final DatabaseService _db;

  PlaylistProvider(this._db);

  List<Playlist> _playlists = [];
  List<Song> _currentSongs = [];
  Playlist? _currentPlaylist;

  List<Playlist> get playlists => _playlists;
  List<Song> get currentSongs => _currentSongs;
  Playlist? get currentPlaylist => _currentPlaylist;

  Future<void> refresh() async {
    _playlists = await _db.getPlaylists();
    notifyListeners();
  }

  Future<int> createPlaylist(String name) async {
    final id = await _db.createPlaylist(name);
    await refresh();
    return id;
  }

  Future<void> deletePlaylist(int id) async {
    await _db.deletePlaylist(id);
    if (_currentPlaylist?.id == id) {
      _currentPlaylist = null;
      _currentSongs = [];
    }
    await refresh();
  }

  Future<void> renamePlaylist(int id, String name) async {
    await _db.renamePlaylist(id, name);
    await refresh();
  }

  Future<void> openPlaylist(Playlist playlist) async {
    _currentPlaylist = playlist;
    _currentSongs = await _db.getPlaylistSongs(playlist.id!);
    notifyListeners();
  }

  Future<void> addSong(Playlist playlist, Song song) async {
    await _db.addSongToPlaylist(playlist.id!, song);
    if (_currentPlaylist?.id == playlist.id) {
      await openPlaylist(playlist);
    }
    await refresh();
  }

  Future<void> removeSong(String songId) async {
    final playlist = _currentPlaylist;
    if (playlist == null) return;
    await _db.removeSongFromPlaylist(playlist.id!, songId);
    await openPlaylist(playlist);
    await refresh();
  }

  Future<bool> isInPlaylist(int playlistId, String songId) =>
      _db.isSongInPlaylist(playlistId, songId);

  Future<void> clearCurrent() async {
    _currentPlaylist = null;
    _currentSongs = [];
    notifyListeners();
  }
}