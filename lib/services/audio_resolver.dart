import 'package:flutter/foundation.dart';

import '../models/song.dart';
import 'archive_service.dart';
import 'audius_service.dart';
import 'jamendo_service.dart';
import 'youtube_audio_service.dart';

/// Pemilih penyedia stream FULL-LENGTH untuk sebuah lagu, berurutan:
///
///   1. [AudiusService]  — gratis, legal, full MP3, tanpa akun
///   2. [JamendoService] — Creative Commons (butuh key, opsional)
///   3. [ArchiveService] — domain-publik / rekaman (Internet Archive)
///   4. [YoutubeAudioService] — fallback terakhir untuk lagu mainstream
///
/// Semua URL kandidat dikembalikan berurutan: yang pertama adalah utama,
/// berikutnya cadangan. Cache in-memory membuat resolve berikutnya instan.
/// Pendekatan multi-penyedia membuat aplikasi tidak bergantung pada satu
/// layanan (YouTube) yang ketat anti-scrape-nya berubah-ubah.
class AudioResolver {
  AudioResolver({required this.youtube}) {
    audius = AudiusService();
    jamendo = JamendoService();
    archive = ArchiveService();
  }

  final YoutubeAudioService youtube;
  late final AudiusService audius;
  late final JamendoService jamendo;
  late final ArchiveService archive;

  final Map<String, _Resolved> _cache = {};

  static const _cacheTtl = Duration(hours: 6);

  /// Cookie sesi YouTube (dipakai pipe bila streamnya dari googlevideo).
  String? get sessionCookie => youtube.sessionCookie;

  Future<List<String>> resolve(Song song, {bool cachedOnly = false}) async {
    final key = _key(song);
    final cached = _cache[key];
    if (cached != null) {
      if (cached.expiresAt.isAfter(DateTime.now())) return cached.urls;
      _cache.remove(key);
    }
    if (cachedOnly) return const [];

    final urls = await _resolveFresh(song);
    if (urls.isNotEmpty) {
      _cache[key] = _Resolved(urls, DateTime.now().add(_cacheTtl));
    } else {
      // ignore: avoid_print
      debugPrint('Resolver: semua penyedia kosong utk "${song.title}"');
    }
    return urls;
  }

  Future<List<String>> _resolveFresh(Song song) async {
    var urls = await audius.resolve(song);
    if (urls.isNotEmpty) {
      debugPrint('Resolver: memakai Audius utk "${song.title}"');
      return urls;
    }
    urls = await jamendo.resolve(song);
    if (urls.isNotEmpty) {
      debugPrint('Resolver: memakai Jamendo utk "${song.title}"');
      return urls;
    }
    urls = await archive.resolve(song);
    if (urls.isNotEmpty) {
      debugPrint('Resolver: memakai Internet Archive utk "${song.title}"');
      return urls;
    }
    final yt = await youtube.resolve(song);
    if (yt.isNotEmpty) {
      debugPrint('Resolver: memakai YouTube utk "${song.title}"');
    }
    return yt;
  }

  void invalidate(Song song) {
    _cache.remove(_key(song));
    youtube.invalidate(song);
  }

  static String _key(Song song) =>
      '${song.title.trim().toLowerCase()} ${song.artist.trim().toLowerCase()}';

  int get cacheSize => _cache.length;

  void dispose() {
    _cache.clear();
    youtube.dispose();
  }
}

class _Resolved {
  final List<String> urls;
  final DateTime expiresAt;

  _Resolved(this.urls, this.expiresAt);
}