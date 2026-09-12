import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/song.dart';

/// Penyedia audio FULL-LENGTH gratis & legal dari Internet Archive
/// (archive.org) — koleksi rekaman, album domain-publik, dan live.
///
/// - Cari: `GET /advancedsearch.php?q=title:(... ) AND mediatype:audio`
/// - File: `GET /metadata/{identifier}` → daftar berkas audio
/// - Stream: `GET /download/{identifier}/{file}` (dukung HTTP Range penuh)
///
/// Katalog IA tidak mainstream; bila kosong, lapisan berikutnya (YouTube)
/// yang bertugas.
class ArchiveService {
  static const _timeout = Duration(seconds: 6);
  static const _metaTimeout = Duration(seconds: 5);
  static const _maxCandidates = 2;
  static const _minScore = 3;
  static const _ua = 'Swara/1.0 (open source music player)';

  Future<List<String>> resolve(Song song) async {
    final title = song.title.trim();
    if (title.isEmpty) return const [];
    final artist = song.artist.trim();

    final words = title
        .split(RegExp(r'\W+'))
        .where((w) => w.length >= 3 && w.toLowerCase() != 'the')
        .toList();
    if (words.isEmpty) return const [];

    final client = http.Client();
    try {
      final q = 'title:(${words.join(' AND ')}) AND mediatype:audio';
      final uri = Uri.parse('https://archive.org/advancedsearch.php').replace(
        queryParameters: {
          'q': q,
          'fl': 'identifier,title,creator,downloads', // ignored; fl[] dipakai
          'fl[]': 'identifier,title,creator,downloads',
          'rows': '15',
          'sort[]': 'downloads desc',
          'output': 'json',
        },
      );
      final resp = await client
          .get(uri, headers: {'User-Agent': _ua})
          .timeout(_timeout);
      if (resp.statusCode != 200) return const [];

      final json = jsonDecode(resp.body);
      final response = json is Map<String, dynamic> ? json['response'] : null;
      final docs = response is Map<String, dynamic> ? response['docs'] : null;
      if (docs is! List) return const [];

      final items = <_ArchiveItem>[];
      for (final raw in docs) {
        if (raw is! Map<String, dynamic>) continue;
        final id = raw['identifier'];
        final t = raw['title'];
        if (id is! String || id.isEmpty || t is! String || t.isEmpty) continue;
        final creator = raw['creator'];
        final cr = creator is String
            ? creator
            : (creator is List && creator.isNotEmpty && creator.first is String
                ? creator.first as String
                : '');
        items.add(_ArchiveItem(id, t.trim(), cr.trim()));
      }
      if (items.isEmpty) return const [];

      items.sort((a, b) =>
          _score(b, title, artist).compareTo(_score(a, title, artist)));

      final out = <String>[];
      for (final item in items.take(_maxCandidates + 1)) {
        try {
          final audioFile = await _pickAudioFile(client, item);
          if (audioFile != null) {
            final fname = Uri.encodeComponent(audioFile);
            out.add('https://archive.org/download/${item.id}/$fname');
            if (out.length >= _maxCandidates) break;
          }
        } catch (_) {
          // coba item berikut
        }
      }
      if (out.isNotEmpty) {
        // ignore: avoid_print
        debugPrint('Archive.org: ${out.length} kandidat utk "$title"');
      }
      return out;
    } catch (e) {
      // ignore: avoid_print
      debugPrint('Archive.org: resolve gagal "$title": $e');
      return const [];
    } finally {
      client.close();
    }
  }

  /// Tentukan berkas MP3 terbesar dalam item (hindari artefak `.jpg`,
  /// thumbnail, dsb).
  Future<String?> _pickAudioFile(http.Client client, _ArchiveItem item) async {
    if (_score(item, item.title, '') < _minScore) return null;
    final uri = Uri.parse('https://archive.org/metadata/${item.id}');
    final resp = await client
        .get(uri, headers: {'User-Agent': _ua})
        .timeout(_metaTimeout);
    if (resp.statusCode != 200) return null;

    final json = jsonDecode(resp.body);
    final files = json is Map<String, dynamic> ? json['files'] : null;
    if (files is! List) return null;

    String? bestName;
    int bestSize = 0;
    for (final raw in files) {
      if (raw is! Map<String, dynamic>) continue;
      final name = raw['name'];
      final format = raw['format'];
      if (name is! String || name.isEmpty) continue;
      final isAudio = format is String &&
          (format.contains('MP3') ||
              format.contains('Ogg') ||
              format.contains('VBR'));
      final extMp3 = name.toLowerCase().endsWith('.mp3');
      if (!isAudio && !extMp3) continue;
      final size = raw['size'];
      final sz = size is num ? size.toInt() : 0;
      if (sz < 50000) continue;
      if (sz > bestSize) {
        bestSize = sz;
        bestName = name;
      }
    }
    if (bestName == null && files.isNotEmpty) {
      for (final raw in files) {
        if (raw is! Map<String, dynamic>) continue;
        final name = raw['name'];
        if (name is String && name.toLowerCase().endsWith('.mp3')) {
          bestName = name;
          break;
        }
      }
    }
    return bestName;
  }

  int _score(_ArchiveItem c, String title, String artist) {
    final t = c.title.toLowerCase();
    final tl = title.toLowerCase();
    final al = artist.toLowerCase();
    var score = 0;
    if (t.contains(tl)) {
      score += 6;
      for (final w in tl.split(RegExp(r'\W+')).where((w) => w.length >= 3)) {
        if (t.contains(w)) score += 1;
      }
    } else {
      for (final w in tl.split(RegExp(r'\W+')).where((w) => w.length >= 3)) {
        if (t.contains(w)) score += 1;
      }
    }
    if (al.isNotEmpty && c.creator.isNotEmpty && c.creator.contains(al)) {
      score += 2;
    }
    return score;
  }
}

class _ArchiveItem {
  final String id;
  final String title;
  final String creator;

  _ArchiveItem(this.id, this.title, this.creator);
}