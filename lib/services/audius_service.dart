import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/song.dart';

/// Penyedia audio FULL-LENGTH gratis, legal, tanpa akun: Audius
/// (open music catalog, platform decentralized).
///
/// - Search: `GET /v1/tracks/search?query=...&limit=N`
/// - Stream: `GET /v1/tracks/{id}/stream` → 302 ke URL CDN bertanda tangan
///   (OpenAudioValidator). CDN-nya mendukung HTTP Range penuh tanpa tembok
///   1 MiB yang membatasi googlevideo, jadi lagu bisa diputar sampai habis.
///
/// Catatan katalog: Audius mayoritas berisi karya indie/EDM/electronic.
/// Untuk lagu mainstream (pop Indonesia misalnya) biasanya kosong — itu
/// normal; biarkan lapisan berikutnya (YouTube) yang menanganinya.
class AudiusService {
  AudiusService({this.base = 'https://api.audius.co'});

  final String base;

  static const _timeout = Duration(seconds: 6);
  static const _maxCandidates = 3;
  static const _ua = 'Swara/1.0 (open source music player)';

  /// Skor minimum agar kandidat diterima (cegah lagu salah diputar saat
  /// judul panjang hanya cocok sebagian).
  static const _minScore = 3;

  /// Cari lagu [song] di Audius; kembalikan URL `stream` (full MP3) untuk
  /// kandidat terbaik, atau kosong bila tidak ditemukan.
  Future<List<String>> resolve(Song song) async {
    final title = song.title.trim();
    if (title.isEmpty) return const [];
    final artist = song.artist.trim();
    final query = artist.isEmpty ? title : '$title $artist';

    final client = http.Client();
    try {
      final uri = Uri.parse('$base/v1/tracks/search').replace(
        queryParameters: {'query': query, 'limit': '15', 'offset': '0'},
      );
      final resp = await client
          .get(uri,
              headers: {'User-Agent': _ua, 'Accept': 'application/json'})
          .timeout(_timeout);
      if (resp.statusCode != 200) return const [];

      final json = jsonDecode(resp.body);
      final data = json is Map<String, dynamic> ? json['data'] : null;
      if (data is! List) return const [];

      final items = <_AudiusTrack>[];
      for (final raw in data) {
        if (raw is! Map<String, dynamic>) continue;
        final id = raw['id'];
        final t = raw['title'];
        if (id is! String || id.isEmpty || t is! String || t.trim().isEmpty) {
          continue;
        }
        final user = raw['user'];
        final name =
            user is Map<String, dynamic> && user['name'] is String
                ? user['name'] as String
                : '';
        items.add(_AudiusTrack(id, t.trim(), name.trim()));
      }
      if (items.isEmpty) return const [];

      items.sort((a, b) =>
          _score(b, title, artist).compareTo(_score(a, title, artist)));

      final out = <String>[];
      for (final it in items) {
        if (_score(it, title, artist) < _minScore) continue;
        out.add('$base/v1/tracks/${it.id}/stream');
        if (out.length >= _maxCandidates) break;
      }
      // ignore: avoid_print
      debugPrint('Audius: ${out.length} kandidat utk "$title"');
      return out;
    } catch (e) {
      // ignore: avoid_print
      debugPrint('Audius: resolve gagal "$title": $e');
      return const [];
    } finally {
      client.close();
    }
  }

  /// Semakin tinggi = semakin relevan dengan judul + artis yang dicari.
  int _score(_AudiusTrack c, String title, String artist) {
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
    if (al.isNotEmpty && c.artist.contains(al)) score += 3;
    return score;
  }
}

class _AudiusTrack {
  final String id;
  final String title;
  final String artist;

  _AudiusTrack(this.id, this.title, this.artist);
}