import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/song.dart';

/// Penyedia audio FULL-LENGTH gratis & legal dari Jamendo
/// (musik Creative Commons).
///
/// - Search: `GET /v3.0/tracks?client_id=...&search=...&format=json`
/// - Stream (MP3 penuh): `https://mp3l.jamendo.com/?trackid={id}&format=mp31`
///
/// API Jamendo butuh `JAMENDO_CLIENT_ID` (gratis didapat di
/// developer.jamendo.com). Bila key kosong, layanan menyerah diam-diam
/// (cadangan berikutnya yang jalan), jadi aplikasi tidak pernah error
/// karenanya.
class JamendoService {
  /// Set via `--dart-define=JAMENDO_CLIENT_ID=xxx` saat build.
  static const _clientId = String.fromEnvironment('JAMENDO_CLIENT_ID');

  static const _timeout = Duration(seconds: 8);
  static const _maxCandidates = 3;

  Future<List<String>> resolve(Song song) async {
    if (_clientId.isEmpty) return const [];
    final title = song.title.trim();
    if (title.isEmpty) return const [];
    final artist = song.artist.trim();

    final client = http.Client();
    try {
      final uri = Uri.parse('https://api.jamendo.com/v3.0/tracks/').replace(
        queryParameters: {
          'client_id': _clientId,
          'format': 'json',
          'search': artist.isEmpty ? title : '$title $artist',
          'limit': '10',
          'audioDownload': '1',
        },
      );
      final resp = await client
          .get(uri, headers: {'User-Agent': 'Swara/1.0'})
          .timeout(_timeout);
      if (resp.statusCode != 200) return const [];

      final json = jsonDecode(resp.body);
      final results = json is Map<String, dynamic> ? json['results'] : null;
      if (results is! List) return const [];

      final items = <_JamendoTrack>[];
      for (final raw in results) {
        if (raw is! Map<String, dynamic>) continue;
        final id = raw['id'];
        final name = raw['name'];
        if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
          continue;
        }
        final an = raw['artist_name'];
        items.add(_JamendoTrack(id, name.trim(), an is String ? an.trim() : ''));
      }
      if (items.isEmpty) return const [];

      items.sort((a, b) =>
          _score(b, title, artist).compareTo(_score(a, title, artist)));

      final out = <String>[];
      for (final it in items) {
        out.add(
            'https://mp3l.jamendo.com/?trackid=${it.id}&format=mp31');
        if (out.length >= _maxCandidates) break;
      }
      // ignore: avoid_print
      debugPrint('Jamendo: ${out.length} kandidat utk "$title"');
      return out;
    } catch (e) {
      // ignore: avoid_print
      debugPrint('Jamendo: resolve gagal "$title": $e');
      return const [];
    } finally {
      client.close();
    }
  }

  int _score(_JamendoTrack c, String title, String artist) {
    final t = c.title.toLowerCase();
    final tl = title.toLowerCase();
    final al = artist.toLowerCase();
    var score = 0;
    if (t == tl) {
      score += 10;
    } else if (tl.isNotEmpty && t.contains(tl)) {
      score += 5;
      for (final w in tl.split(RegExp(r'\W+')).where((w) => w.length >= 3)) {
        if (t.contains(w)) score += 1;
      }
    }
    if (al.isNotEmpty && c.artist.contains(al)) score += 2;
    return score;
  }
}

class _JamendoTrack {
  final String id;
  final String title;
  final String artist;

  _JamendoTrack(this.id, this.title, this.artist);
}