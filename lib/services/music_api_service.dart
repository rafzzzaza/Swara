import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/album.dart';
import '../models/artist.dart';
import '../models/genre.dart';
import '../models/song.dart';

/// Fetches real music data from the free Deezer public API.
class MusicApiService {
  static const _base = 'https://api.deezer.com';
  static const _timeout = Duration(seconds: 20);

  Future<dynamic> _get(String path,
      {Map<String, String>? query}) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final res = await http.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('Deezer ${res.statusCode} for $path');
    }
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  // ---------- Track parsing ----------

  Song _songFrom(Map<String, dynamic> j) {
    final album = (j['album'] as Map?)?.cast<String, dynamic>();
    final artist = (j['artist'] as Map?)?.cast<String, dynamic>();
    final coverXl = album?['cover_xl'] as String?;
    final coverBig = album?['cover_big'] as String?;
    final coverMedium = album?['cover_medium'] as String?;
    return Song(
      id: (j['id'] is int ? j['id'] : int.tryParse('${j['id']}') ?? 0)
          .toString(),
      title: (j['title'] as String?) ?? 'Tanpa Judul',
      artist: (artist?['name'] as String?) ?? (_artistName(j) ?? 'Tidak Diketahui'),
      album: (album?['title'] as String?) ?? (j['album_base'] as String?),
      duration: j['duration'] is int
          ? Duration(seconds: j['duration'] as int)
          : null,
      thumbnailUrl: coverMedium ?? coverBig ?? coverXl,
      artUrl: coverXl ?? coverBig ?? coverMedium,
      previewUrl: j['preview'] as String?,
    );
  }

  String? _artistName(Map<String, dynamic> j) {
    final contributors =
        (j['contributors'] as List?)?.cast<Map<String, dynamic>>();
    if (contributors != null && contributors.isNotEmpty) {
      return contributors.first['name'] as String?;
    }
    return null;
  }

  // ---------- Top charts ----------

  Future<List<Song>> chartTracks({int limit = 20, int offset = 0}) async {
    final j = await _get('/chart', query: {
      'limit': '$limit',
      'index': '$offset',
    });
    final data = ((j['tracks']?['data'] as List?) ?? [])
        .cast<Map<String, dynamic>>();
    return data.map(_songFrom).where((s) => s.previewUrl != null).toList();
  }

  Future<List<Album>> newAlbums({int limit = 20}) async {
    final j = await _get('/chart', query: {'limit': '$limit'});
    final data = ((j['albums']?['data'] as List?) ?? [])
        .cast<Map<String, dynamic>>();
    return data.map(_albumFrom).toList();
  }

  Future<List<Artist>> topArtists({int limit = 20}) async {
    final j = await _get('/chart', query: {'limit': '$limit'});
    final data = ((j['artists']?['data'] as List?) ?? [])
        .cast<Map<String, dynamic>>();
    return data.map(_artistFrom).toList();
  }

  // ---------- Genres & mood ----------

  Future<List<Genre>> genres() async {
    final j = await _get('/genre');
    final data = (j['data'] as List).cast<Map<String, dynamic>>();
    return data
        .map((g) => Genre(
              id: (g['id'] as int?) ?? 0,
              name: (g['name'] as String?) ?? '',
              pictureUrl: g['picture_medium'] as String?,
            ))
        .where((g) => g.id != 0 && g.name.isNotEmpty)
        .toList();
  }

  Future<List<Song>> genreTracks(String genreName, {int limit = 20}) async {
    return searchSongs('$genreName top', limit: limit, order: 'RATING_DESC');
  }

  // ---------- Search ----------

  Future<List<Song>> searchSongs(
    String query, {
    int limit = 24,
    String? order,
  }) async {
    final j = await _get('/search', query: {
      'q': query,
      'limit': '$limit',
      'order': ?order,
    });
    final data = (j['data'] as List).cast<Map<String, dynamic>>();
    return data.map(_songFrom).where((s) => s.previewUrl != null).toList();
  }

  // ---------- Regional hits (Indonesia & Global) ----------

  /// Lagu populer Indonesia dari beberapa query, dideduplikasi by id.
  Future<List<Song>> indonesiaHits({int limit = 20}) async {
    return _mergeUnique([
      await searchSongs('Indonesia top', limit: 14),
      await searchSongs('Pop Indonesia', limit: 14),
      await searchSongs('Indonesia hits', limit: 14),
    ], limit: limit);
  }

  /// Lagu hits global / barat dari beberapa query, dideduplikasi by id.
  Future<List<Song>> globalHits({int limit = 20}) async {
    return _mergeUnique([
      await searchSongs('top 50 global', limit: 14),
      await searchSongs('top english pop songs', limit: 14),
      await searchSongs('best english hits', limit: 14),
    ], limit: limit);
  }

  List<Song> _mergeUnique(List<List<Song>> groups, {int limit = 20}) {
    final seen = <String>{};
    final out = <Song>[];
    for (final group in groups) {
      for (final song in group) {
        if (seen.add(song.id)) out.add(song);
        if (out.length >= limit) return out;
      }
    }
    return out;
  }

  // ---------- Album & artist collections ----------

  Future<List<Song>> albumTracks(Album album, {int limit = 40}) async {
    final j = await _get('/album/${album.id}', query: {'limit': '$limit'});
    final coverXl = j['cover_xl'] as String?;
    final coverBig = j['cover_big'] as String?;
    final coverMedium = j['cover_medium'] as String?;
    final albumTitle = (j['title'] as String?) ?? album.title;
    final artistName = (j['artist']?['name'] as String?) ?? album.artist;
    final data = (j['tracks']?['data'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    return data.map((t) {
      final s = _songFrom(t);
      return Song(
        id: s.id,
        title: s.title,
        artist: artistName,
        album: albumTitle,
        duration: s.duration,
        thumbnailUrl: coverMedium ?? coverBig ?? coverXl,
        artUrl: coverXl ?? coverBig ?? coverMedium,
        previewUrl: s.previewUrl,
      );
    }).where((s) => s.previewUrl != null).toList();
  }

  Future<List<Song>> artistTracks(Artist artist, {int limit = 15}) async {
    final j = await _get('/artist/${artist.id}/top',
        query: {'limit': '$limit'});
    final data = (j['data'] as List).cast<Map<String, dynamic>>();
    return data
        .map((t) {
          final s = _songFrom(t);
          return Song(
            id: s.id,
            title: s.title,
            artist: artist.name,
            album: s.album,
            duration: s.duration,
            thumbnailUrl: s.thumbnailUrl,
            artUrl: s.artUrl,
            previewUrl: s.previewUrl,
          );
        })
        .where((s) => s.previewUrl != null)
        .toList();
  }

  // ---------- Internal ----------

  Album _albumFrom(Map<String, dynamic> j) {
    final artist = (j['artist'] as Map?)?.cast<String, dynamic>();
    return Album(
      id: (j['id'] is int ? j['id'] : int.tryParse('${j['id']}') ?? 0)
          .toString(),
      title: (j['title'] as String?) ?? 'Tanpa Judul',
      artist: (artist?['name'] as String?) ?? (j['label'] as String? ?? ''),
      pictureUrl: (j['cover_big'] as String?) ?? (j['cover_xl'] as String?),
      pictureMedium: j['cover_medium'] as String?,
    );
  }

  Artist _artistFrom(Map<String, dynamic> j) => Artist(
        id: (j['id'] is int ? j['id'] : int.tryParse('${j['id']}') ?? 0)
            .toString(),
        name: (j['name'] as String?) ?? 'Tidak Diketahui',
        pictureUrl: (j['picture_medium'] as String?) ??
            (j['picture_big'] as String?),
      );
}