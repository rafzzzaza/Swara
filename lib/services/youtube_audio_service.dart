import 'dart:async';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/song.dart';

/// Resolves a full-length audio stream from YouTube for a Deezer song.
///
/// Deezer/iTunes only expose 30-second previews, so we search YouTube
/// by title + artist and pick the best audio-only stream. Results are
/// cached in-memory to keep repeated resolves instant.
class YoutubeAudioService {
  final YoutubeExplode _yt = YoutubeExplode();
  final Map<String, _Resolved> _cache = {};

  static const _searchTimeout = Duration(seconds: 10);
  static const _cacheTtl = Duration(hours: 6);

  /// Returns a direct audio stream URL for [song], or null when the
  /// song has an empty title or the resolution failed/timed out.
  ///
  /// When [cachedOnly] is true, only the in-memory cache is consulted
  /// so callers never block on the network (used for queue builds).
  Future<String?> resolve(Song song, {bool cachedOnly = false}) async {
    final title = song.title.trim();
    final artist = song.artist.trim();
    if (title.isEmpty) return null;

    final key = '${title.toLowerCase()} ${artist.toLowerCase()}';
    final cached = _cache[key];
    if (cached != null) {
      if (cached.expiresAt.isAfter(DateTime.now())) return cached.url;
      _cache.remove(key);
    }
    if (cachedOnly) return null;

    try {
      final url = await _resolveKey(title, artist)
          .timeout(_searchTimeout * 2);
      if (url == null) return null;
      _cache[key] =
          _Resolved(url, DateTime.now().add(_cacheTtl));
      return url;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveKey(String title, String artist) async {
    final query = artist.isNotEmpty
        ? '$title $artist official audio'
        : '$title official audio';

    final results = (await _yt.search
        .search(query)
        .timeout(_searchTimeout))
        .whereType<SearchVideo>()
        .take(3)
        .toList();

    if (results.isEmpty) return null;

    final manifest = await _yt.videos.streamsClient
        .getManifest(results.first.id)
        .timeout(_searchTimeout);

    AudioOnlyStreamInfo? best;
    for (final s in manifest.audioOnly) {
      final kbps = s.bitrate.kiloBitsPerSecond;
      if (best == null ||
          (kbps <= 160 && kbps > best.bitrate.kiloBitsPerSecond)) {
        best = s;
      }
    }
    if (best == null) return null;
    return best.url.toString();
  }

  /// Number of cached resolutions (handy for debugging / tests).
  int get cacheSize => _cache.length;

  void dispose() {
    _cache.clear();
    _yt.close();
  }
}

class _Resolved {
  final String url;
  final DateTime expiresAt;

  _Resolved(this.url, this.expiresAt);
}