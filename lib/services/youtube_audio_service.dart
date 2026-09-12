import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/song.dart';

/// Resolves a full-length audio stream from YouTube for a Deezer song.
///
/// Deezer/iTunes only expose 30-second previews, so we search YouTube by
/// title + artist and pick the best audio-only stream. Results are cached
/// in-memory to keep repeated resolves instant.
///
/// Discovery uses YouTube's innerTube `youtubei/v1/search` endpoint (the
/// same API the web/phone app uses) instead of the HTML `/results` page,
/// because ISPs / bots block the latter with `google_abuse=GOOGLE_ABUSE_...`
/// redirects. The innerTube endpoint is far more resilient.
class YoutubeAudioService {
  final YoutubeExplode _yt = YoutubeExplode();
  final Map<String, _Resolved> _cache = {};

  static const _searchTimeout = Duration(seconds: 20);
  static const _searchAttempts = 2;
  static const _manifestTimeout = Duration(seconds: 45);
  static const _manifestAttempts = 1;
  static const _cacheTtl = Duration(hours: 6);
  static const _backoff = Duration(seconds: 2);
  static const _minSearchGap = Duration(milliseconds: 1500);
  static const _minManifestGap = Duration(milliseconds: 1200);
  static const _extraTimeout = Duration(seconds: 12);
  static const _maxCandidates = 5;

  DateTime _lastNetwork = DateTime.fromMillisecondsSinceEpoch(0);

  /// Cookie sesi YouTube (Set-Cookie dari innerTube) — dipakai ulang untuk
  /// request manapun supaya tidak dianggap bot.
  String? _sessionCookie;
  String? get sessionCookie => _sessionCookie;

  /// Kunci cookie yang diamankan dari `Set-Cookie` innerTube.
  static const _cookieNames = {
    'SOCS',
    'CONSENT',
    'VISITOR_INFO1_LIVE',
    'VISITOR_PRIVACY_METADATA',
    'PREF',
    'YSC',
  };

  /// Jeda minimal antar-request jaringan supaya CDN YouTube tidak salah
  /// mendeteksi kita sebagai bot (kalau terkunci, cukup pendingin beberapa
  /// menit lalu kembali normal).
  Future<void> _throttle(Duration gap) async {
    final now = DateTime.now();
    final wait = gap - now.difference(_lastNetwork);
    if (wait > Duration.zero) {
      await Future<void>.delayed(wait);
    }
    _lastNetwork = DateTime.now();
  }

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  /// Returns ordered candidate stream URLs for [song], or empty when the
  /// song has an empty title or the resolution failed/timed out.
  ///
  /// IDENTIK ungkapan kandidat: URL pertama adalah pilihan utama; URL
  /// berikutnya dipakai sebagai cadangan kalau yang utama 403/mati.
  ///
  /// When [cachedOnly] is true, only the in-memory cache is consulted so
  /// callers never block on the network (used for queue builds).
  Future<List<String>> resolve(Song song, {bool cachedOnly = false}) async {
    final title = song.title.trim();
    final artist = song.artist.trim();
    if (title.isEmpty) return const [];

    final key = '${title.toLowerCase()} ${artist.toLowerCase()}';
    final cached = _cache[key];
    if (cached != null) {
      if (cached.expiresAt.isAfter(DateTime.now())) return cached.urls;
      _cache.remove(key);
    }
    if (cachedOnly) return const [];

    List<String> urls = const [];
    for (var attempt = 0; attempt < _searchAttempts && urls.isEmpty; attempt++) {
      try {
        // ignore: avoid_print
        debugPrint('YT: resolve mulai attempt=$attempt titles="$title"');
        urls = await _resolve(title, artist)
            .timeout(const Duration(seconds: 90));
      } catch (e) {
        // ignore: avoid_print
        debugPrint('YT: resolve attempt=$attempt throw: $e');
      }
      if (urls.isEmpty && attempt < _searchAttempts - 1) {
        await Future<void>.delayed(_backoff);
      }
    }
    if (urls.isEmpty) {
      // ignore: avoid_print
      debugPrint('YT: resolve gagal untuk "$title"');
      return const [];
    }

    _cache[key] = _Resolved(urls, DateTime.now().add(_cacheTtl));
    return urls;
  }

  /// Hapus hasil cache untuk [song] (dipakai saat stream lama 403 & mau
  /// resolusi ulang dari nol).
  void invalidate(Song song) {
    final key = '${song.title.trim().toLowerCase()} '
        '${song.artist.trim().toLowerCase()}';
    _cache.remove(key);
  }

  Future<List<String>> _resolve(String title, String artist) async {
    final queries = _buildQueries(title, artist);
    final out = <String>[];

    for (final query in queries) {
      try {
        final candidates = await _searchVideos(query);
        if (candidates.isEmpty) continue;
        candidates.sort((a, b) =>
            _scoreCandidate(b, title, artist)
                .compareTo(_scoreCandidate(a, title, artist)));
        // 1) Kandidat utama: manifest youtube_explode_dart (audio-only).
        final direct = await _tryManifest(candidates.take(3).toList());
        out.addAll(direct);
        // 2) Cadangan RELAY: proxy_stream Piped / latest_version Invidious.
        //    Relay mengunduh lewat server mereka (memegang clearance penuh
        //    YouTube), jadi tembus batas ~1 MiB yang membatasi stream
        //    langsung googlevideo dari IP kita.
        if (direct.isNotEmpty) {
          out.addAll(_relayBackups(candidates.first, direct.first));
        } else {
          out.addAll(await _extraStreams(candidates.take(2).toList()));
        }
        if (out.isNotEmpty) return _dedupe(out);
      } catch (e) {
        // ignore: avoid_print
        debugPrint('YT search gagal q="$query": $e');
        // coba query berikutnya
      }
    }
    return const [];
  }

  /// Hapus URL duplikat, potong ke [_maxCandidates].
  static List<String> _dedupe(List<String> list) {
    final seen = <String>{};
    final out = <String>[];
    for (final u in list) {
      if (u.isEmpty || !seen.add(u)) continue;
      out.add(u);
      if (out.length >= _maxCandidates) break;
    }
    return out;
  }

  /// Built query pencarian dari judul + artis setelah dibersihkan dari
  /// kata/karakter tambahan ("official audio", "lyric video", kurung, dsb.)
  /// agar pencarian tidak terlalu spesifik.
  List<String> _buildQueries(String title, String artist) {
    final cleanTitle = _stripClutter(title);
    final cleanBoth =
        artist.isEmpty ? cleanTitle : _stripClutter('$title $artist');
    final queries = <String>[
      if (cleanBoth.isNotEmpty) '$cleanBoth official audio',
      if (cleanBoth.isNotEmpty && cleanBoth != cleanTitle) cleanBoth,
      if (cleanTitle.isNotEmpty) '$cleanTitle official audio',
      if (cleanTitle.isNotEmpty) cleanTitle,
    ];
    final seen = <String>{};
    return queries.where((q) => seen.add(q)).toList();
  }

  /// Hapus noise umum dari judul lagu/query pencarian.
  static String _stripClutter(String s) {
    var v = s
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
        .replaceAll(
            RegExp(r'\bofficial\s+(music\s+)?(audio|video|lyrics?)\b',
                caseSensitive: false),
            ' ')
        .replaceAll(
            RegExp(r'\b(lyrics?|music\s*video|official)\b',
                caseSensitive: false),
            ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return v;
  }

  /// Nilai kecocokan kandidat dengan judul + artis lagu. Lebih tinggi =
  /// lebih relevan (cegah lagu yang salah diputar).
  int _scoreCandidate(_Candidate c, String title, String artist) {
    final t = c.title.toLowerCase();
    final tl = title.toLowerCase();
    final al = artist.toLowerCase();
    var score = 0;
    if (tl.isNotEmpty && t.contains(tl)) {
      score += 3;
      for (final w
          in tl.split(RegExp(r'\W+')).where((w) => w.length >= 3)) {
        if (t.contains(w)) score += 1;
      }
    }
    if (al.isNotEmpty && t.contains(al)) score += 1;
    if (c.title.trim().toLowerCase().contains('official')) score += 1;
    return score;
  }

  static const _pipedInstances = [
    'https://pipedapi.kavin.rocks',
    'https://pipedapi.reallyaweso.me',
    'https://pipedapi.adminforge.de',
    'https://pipedapi.drgns.space',
    'https://pipedapi.nosebs.ru',
  ];

  /// Searches YouTube via the innerTube web API. Returns the video
  /// candidates (id + title) from the rendered search results.
  ///
  /// When innerTube returns nothing (langka, tapi bisa), fall back ke Piped
  /// API yang mirip untuk tetap mendapat video ID.
  Future<List<_Candidate>> _searchVideos(String query) async {
    await _throttle(_minSearchGap);
    final client = http.Client();
    try {
      final body = jsonEncode({
        'context': {
          'client': {'clientName': 'WEB', 'clientVersion': '2.20240701.00.00'},
        },
        'query': query,
        'params': 'EgIQAQ%3D%3D',
      });
      final resp = await client
          .post(
            Uri.parse('https://www.youtube.com/youtubei/v1/search'),
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': _userAgent,
              'Cookie': ?_sessionCookie,
            },
            body: body,
          )
          .timeout(_searchTimeout);

      _captureSessionCookie(resp);

      final decoded = utf8.decode(_decodeUtf8(resp));
      final json = jsonDecode(decoded);
      final candidates = _parseSearch(json);
      if (candidates.isEmpty) {
        // ignore: avoid_print
        debugPrint('YT: innerTube kosong utk q="$query", fallback Piped/Invidious');
        final alt = await _searchPiped(query, client);
        if (alt.isNotEmpty) return alt;
        return await _searchInvidious(query, client);
      }
      return candidates;
    } finally {
      client.close();
    }
  }

  /// Simpan cookie sesi dari header respons YouTube untuk dipakai pada
  /// request berikutnya (stream, search, dll).
  void _captureSessionCookie(http.BaseResponse resp) {
    try {
      final setCookies = resp.headers['set-cookie'];
      if (setCookies == null || setCookies.isEmpty) return;
      final parts = <String>[];
      final seen = <String>{};
      for (final header in setCookies.split(',')) {
        final first = header.trim().split(';').first;
        final eq = first.indexOf('=');
        if (eq <= 0) continue;
        final name = first.substring(0, eq).trim();
        if (!_cookieNames.contains(name)) continue;
        final value = first.substring(eq + 1).trim();
        if (value.isEmpty || !seen.add(name)) continue;
        parts.add('$name=$value');
      }
      if (parts.isNotEmpty) {
        _sessionCookie = parts.join('; ');
        // ignore: avoid_print
        debugPrint('YT: cookie sesi diperbarui (${parts.join(', ')})');
      }
    } catch (_) {
      // jangan sampai gagal parse menghalangi resolve
    }
  }

  Future<List<_Candidate>> _searchPiped(
      String query, http.Client client) async {
    for (final base in _pipedInstances) {
      try {
        final uri = Uri.parse('$base/search').replace(queryParameters: {
          'q': query,
          'filter': 'music_songs',
        });
        final resp = await client
            .get(uri,
                headers: {
                  'User-Agent': _userAgent,
                  'Accept': 'application/json',
                })
            .timeout(_searchTimeout);
        final list = jsonDecode(resp.body);
        if (list is! List) continue;
        final out = <_Candidate>[];
        for (final item in list) {
          final map = _asMap(item);
          if (map == null) continue;
          final id = map['videoId'];
          if (id is! String || id.isEmpty) continue;
          final title = map['title'];
          if (title is! String || title.trim().isEmpty) continue;
          final duration = map['duration'];
          if (duration is num && duration < 75) continue;
          out.add(_Candidate(VideoId(id), title.trim()));
        }
        if (out.isNotEmpty) return out;
      } catch (_) {
        // coba instance berikutnya
      }
    }
    // ignore: avoid_print
    debugPrint('YT: Piped kosong utk q="$query"');
    return const [];
  }

  static const _invidiousInstances = [
    'https://inv.nadeko.net',
    'https://invidious.f5.si',
    'https://invidious.tiekoetter.com',
    'https://invidious.nerdvpn.de',
  ];

  /// Fallback pencarian video via API Invidious bila innerTube & Piped
  /// keduanya kosong/gagal.
  Future<List<_Candidate>> _searchInvidious(
      String query, http.Client client) async {
    for (final base in _invidiousInstances) {
      try {
        final uri = Uri.parse('$base/api/v1/search').replace(queryParameters: {
          'q': query,
          'type': 'video',
        });
        final resp = await client
            .get(uri,
                headers: {'User-Agent': _userAgent, 'Accept': 'application/json'})
            .timeout(_extraTimeout);
        final list = jsonDecode(resp.body);
        if (list is! List) continue;
        final out = <_Candidate>[];
        for (final item in list) {
          final map = _asMap(item);
          if (map == null) continue;
          final id = map['videoId'];
          if (id is! String || id.isEmpty) continue;
          final title = map['title'];
          if (title is! String || title.trim().isEmpty) continue;
          final dur = map['lengthSeconds'];
          if (dur is num && dur < 75) continue;
          out.add(_Candidate(VideoId(id), title.trim()));
        }
        if (out.isNotEmpty) return out;
      } catch (_) {
        // coba instance berikutnya
      }
    }
    return const [];
  }

  /// URL cadangan RELAY untuk [video] memakai URL stream langsung [directUrl]
  /// sebagai dasar. Relay (Piped `proxy_stream`, Invidious `latest_version`)
  /// mengunduh dari sisi server mereka sendiri sehingga tidak terkena batas
  /// ~1 MiB googlevideo yang membatasi IP kita. Dikembalikan apa adanya
  /// (tanpa dicek) supaya resolve tetap cepat; kekalahan ditangani saat
  /// pemutaran lewat fallback berlapis.
  List<String> _relayBackups(_Candidate video, String directUrl) {
    final enc = Uri.encodeComponent(directUrl);
    final relays = <String>[
      for (final base in _pipedInstances)
        '$base/proxy_stream/${video.id}?video=$enc&audio=true',
      for (final base in _invidiousInstances)
        '$base/latest_version?id=${video.id}&itag=140&local=true',
    ];
    // ignore: avoid_print
    debugPrint('YT: kandidat relay ${relays.length} utk ${video.id}');
    return relays;
  }

  /// Cadangan URL stream langsung dari API Invidious/Piped bila manifest
  /// youtube_explode_dart gagal. Best-effort, timeout pendek.
  Future<List<String>> _extraStreams(List<_Candidate> candidates) async {
    final client = http.Client();
    final out = <String>[];
    try {
      for (final video in candidates) {
        for (final base in _invidiousInstances) {
          try {
            final uri = Uri.parse('$base/api/v1/videos/${video.id}');
            final resp = await client
                .get(uri,
                    headers: {
                      'User-Agent': _userAgent,
                      'Accept': 'application/json',
                    })
                .timeout(_extraTimeout);
            final json = _asMap(jsonDecode(resp.body));
            final formats = json?['adaptiveFormats'];
            if (formats is! List) continue;
            for (final f in formats) {
              final m = _asMap(f);
              final type = m?['type'];
              if (type is! String || !type.contains('audio')) continue;
              final url = m?['url'];
              if (url is String && url.isNotEmpty) out.add(url);
              if (out.length >= _maxCandidates) break;
            }
          } catch (_) {
            // instance berikut / video berikut
          }
          if (out.isNotEmpty) return out;
        }
        if (out.isNotEmpty) return out;
      }
      // Terakhir: Piped /streams bila Invidious tidak ada hasil.
      for (final video in candidates) {
        for (final base in _pipedInstances) {
          try {
            final uri = Uri.parse('$base/streams/${video.id}');
            final resp = await client
                .get(uri,
                    headers: {
                      'User-Agent': _userAgent,
                      'Accept': 'application/json',
                    })
                .timeout(_extraTimeout);
            final json = _asMap(jsonDecode(resp.body));
            final streams = json?['audioStreams'];
            if (streams is! List) continue;
            for (final s in streams) {
              final m = _asMap(s);
              final url = m?['url'];
              if (url is String && url.isNotEmpty) out.add(url);
              if (out.length >= _maxCandidates) break;
            }
          } catch (_) {
            // instance berikut
          }
          if (out.isNotEmpty) return out;
        }
      }
    } finally {
      client.close();
    }
    return out;
  }

  Map<String, dynamic>? _asMap(dynamic value) =>
      value is Map<String, dynamic> ? value : null;

  _Candidate? _parseVideo(Map<String, dynamic>? video) {
    if (video == null) return null;
    final id = video['videoId'];
    if (id is! String || id.isEmpty) return null;
    final titleNode = _asMap(video['title']);
    final runs = titleNode == null ? null : titleNode['runs'] as List?;
    if (runs == null || runs.isEmpty) return null;
    final text = _asMap(runs.first)?['text'];
    if (text is! String || text.trim().isEmpty) return null;
    final dur = _parseDuration(video['lengthText']);
    if (dur != null && dur < 75) return null;
    if (_isLive(video)) return null;
    return _Candidate(VideoId(id), text.trim());
  }

  int? _parseDuration(dynamic lengthText) {
    final label = _asMap(lengthText)?['simpleText'];
    if (label is! String) return null;
    final m = RegExp(r'(\d+):(\d{1,2})').firstMatch(label);
    if (m == null) return null;
    return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }

  bool _isLive(Map<String, dynamic> video) {
    final badges = video['badges'];
    if (badges is List) {
      for (final b in badges) {
        final label = _asMap(_asMap(_asMap(b)?['metadataBadgeRenderer'])
            ?['label']);
        if (label != null) return true;
      }
    }
    return false;
  }

  List<_Candidate> _parseSearch(dynamic json) {
    final out = <_Candidate>[];
    final contents = _asMap(_asMap(json)?['contents']);
    final twoCol = contents == null
        ? null
        : _asMap(contents['twoColumnSearchResultsRenderer']);
    final primary = twoCol == null
        ? null
        : _asMap(twoCol['primaryContents']);
    final sectionList = primary == null
        ? null
        : _asMap(primary['sectionListRenderer']);
    final sections = sectionList == null ? null : sectionList['contents'] as List?;
    if (sections == null) return out;
    for (final section in sections) {
      final itemSection = _asMap(_asMap(section)?['itemSectionRenderer']);
      final items = itemSection == null ? null : itemSection['contents'] as List?;
      if (items == null) continue;
      for (final item in items) {
        final video = _parseVideo(_asMap(_asMap(item)?['videoRenderer']));
        if (video != null) out.add(video);
      }
    }
    return out;
  }

  List<int> _decodeUtf8(http.Response resp) {
    final bytes = resp.bodyBytes;
    const utf8Bom = [0xEF, 0xBB, 0xBF];
    if (bytes.length >= 3 &&
        bytes[0] == utf8Bom[0] &&
        bytes[1] == utf8Bom[1] &&
        bytes[2] == utf8Bom[2]) {
      return bytes.sublist(3);
    }
    return bytes;
  }

  Future<List<String>> _tryManifest(List<_Candidate> candidates) async {
    final out = <String>[];
    for (final video in candidates) {
      for (var attempt = 0; attempt < _manifestAttempts; attempt++) {
        try {
          await _throttle(_minManifestGap);
          final manifest = await _yt.videos.streamsClient
              .getManifest(video.id)
              .timeout(_manifestTimeout);
          final url = _pickAudioUrl(manifest);
          if (url != null) {
            // ignore: avoid_print
            debugPrint('YT: manifest OK ${video.id} (${video.title})');
            out.add(url);
            break;
          }
        } catch (e) {
          // ignore: avoid_print
          debugPrint('YT: manifest gagal ${video.id} $e');
        }
      }
    }
    return out;
  }

  /// Pilih aliran audio murni (itag audio-only) berkualitas terbaik ≤160 kbps.
  String? _pickAudioUrl(StreamManifest manifest) {
    AudioOnlyStreamInfo? best;
    for (final s in manifest.audioOnly) {
      final kbps = s.bitrate.kiloBitsPerSecond;
      if (best == null ||
          (kbps <= 160 && kbps > best.bitrate.kiloBitsPerSecond)) {
        best = s;
      }
    }
    return best?.url.toString();
  }

  /// Number of cached resolutions (handy for debugging / tests).
  int get cacheSize => _cache.length;

  void dispose() {
    _cache.clear();
    _yt.close();
  }
}

class _Candidate {
  final VideoId id;
  final String title;

  _Candidate(this.id, this.title);
}

class _Resolved {
  final List<String> urls;
  final DateTime expiresAt;

  _Resolved(this.urls, this.expiresAt);
}