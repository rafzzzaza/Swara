import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Proxy HTTP lokal yang meneruskan permintaan audio streaming ke URL
/// remote (mis. googlevideo) memakai stack jaringan Dart.
///
/// ExoPlayer (just_audio) kadang kena HTTP 403 saat minta langsung ke
/// CDN YouTube (quirk Client/IP/CDN), padahal request HTTP biasa ke URL
/// yang sama sukses. Lewat proxy ini, ExoPlayer cukup bicara ke
/// 127.0.0.1 dan service yang meneruskan bytes-nya dengan header browser
/// yang tepat.
///
/// Anti-403 yang diterapkan:
///  - Header replika browser (UA, Accept, Accept-Language, Referer, Origin,
///    Sec-Fetch-*) supaya CDN mengira kita browser asli.
///  - Cookie sesi YouTube (hasil `Set-Cookie` dari innerTube) bila tersedia.
///  - Range SELALU berbatas — CDN googlevideo menolak range yang terlalu
///    besar maupun open-ended ("bytes=N-"). Kalau tetap 403, ukuran window
///    diturunkan bertahap (self-healing).
class AudioPipeService {
  HttpServer? _server;
  Future<int>? _starting;

  /// Satu klien HTTP bersama agar tidak bocor soket (dibuat saat pipe aktif).
  http.Client? _upstream;

  /// Cookie sesi YouTube (SOCS/CONSENT/dll.) yang diambil dari innerTube,
  /// diteruskan ke request stream supaya tidak dianggap bot.
  String? sessionCookie;

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  /// Ukuran window range yang dicoba berurutan (dari paling besar).
  /// Temuan empiris: 8 MB -> 403, 64 KB & 1 KB -> 206. Turun bertahap
  /// sampai server mau melayani.
  static const _windowSteps = [1048575, 262143, 65535, 8191, 1023];

  Future<int> _start() async {
    _upstream ??= http.Client();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
    _server = server;
    return server.port;
  }

  Future<int> get port => (_starting ??= _start());

  /// Variasi header untuk request stream. CDN tertentu menolak kombinasi
  /// Origin/Cookie tertentu — dua mode disediakan (khusus googlevideo).
  /// Host penyedia lain (Audius/archive.org/Jamendo) memakai header netral
  /// tanpa Referer/Origin YouTube agar tidak dicurigai.
  static List<Map<String, String>> _headerVariants(
      String? cookie, bool isYoutube) {
    if (!isYoutube) {
      return [
        {
          'User-Agent': _userAgent,
          'Accept': '*/*',
          'Accept-Language': 'en-US,en;q=0.9',
          'Accept-Encoding': 'identity;q=1.0, *;q=0',
          'Connection': 'keep-alive',
        },
      ];
    }
    final base = <String, String>{
      'User-Agent': _userAgent,
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      'Accept-Encoding': 'identity;q=1.0, *;q=0',
      'Connection': 'keep-alive',
      'Referer': 'https://www.youtube.com/',
      'Sec-Fetch-Dest': 'audio',
      'Sec-Fetch-Mode': 'no-cors',
      'Sec-Fetch-Site': 'cross-site',
    };
    final full = Map<String, String>.of(base)
      ..['Origin'] = 'https://www.youtube.com';
    final bare = Map<String, String>.of(base)..remove('Origin');
    if (cookie != null && cookie.trim().isNotEmpty) {
      full['Cookie'] = cookie.trim();
      bare['Cookie'] = cookie.trim();
    }
    return [full, bare];
  }

  /// Ubah Range menjadi berbatas (bila open-ended atau terlalu besar).
  static String _boundedRangeWith(String incoming, int window) {
    final trimmed = incoming.trim();
    if (trimmed.isEmpty) return 'bytes=0-$window';
    final m = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(trimmed);
    if (m != null) {
      final start = int.parse(m.group(1)!);
      final end = int.parse(m.group(2)!);
      final span = end - start + 1;
      return span <= window + 1 ? trimmed : 'bytes=$start-${start + window}';
    }
    final open = RegExp(r'^bytes=(\d+)-$').firstMatch(trimmed);
    if (open != null) {
      final start = int.parse(open.group(1)!);
      return 'bytes=$start-${start + window}';
    }
    return trimmed;
  }

  /// URL lokal yang memproksi [remoteUrl].
  Future<Uri> wrap(String remoteUrl) async {
    final p = await port;
    return Uri.parse(
        'http://127.0.0.1:$p/proxy?u=${Uri.encodeComponent(remoteUrl)}');
  }

  Future<void> _handle(HttpRequest req) async {
    final remote = req.requestedUri.queryParameters['u'];
    if (remote == null || remote.isEmpty) {
      req.response.statusCode = HttpStatus.badRequest;
      await req.response.close();
      return;
    }
    final range = req.headers.value(HttpHeaders.rangeHeader) ?? '';
    if (range.isEmpty) {
      debugPrint('PIPE: req host=${Uri.parse(remote).host} range=$range');
    }

    final remoteUri = Uri.parse(remote);
    final isRelay = remoteUri.path.contains('proxy_stream') ||
        remoteUri.path.contains('latest_version');

    final http.StreamedResponse chosen = isRelay
        ? await _fetchRelay(remoteUri, range)
        : await _fetchWithRetry(remoteUri, range, sessionCookie,
            isYoutube:
                remoteUri.host.contains('googlevideo') ||
                remoteUri.host.contains('youtube'));

    try {
      if (chosen.statusCode != 200 && chosen.statusCode != 206) {
        debugPrint('PIPE: fwd -> ${chosen.statusCode} '
            'cr=${chosen.headers['content-range']} '
            'type=${chosen.headers['content-type']}');
      }

      req.response.statusCode = chosen.statusCode;
      final ct = chosen.headers['content-type'];
      if (ct != null && ct.isNotEmpty) {
        req.response.headers.contentType = ContentType.parse(ct);
      }
      final cl = chosen.contentLength;
      if (cl != null && cl >= 0) {
        req.response.headers.set(HttpHeaders.contentLengthHeader, cl);
      }
      final cr = chosen.headers['content-range'];
      if (cr != null && cr.isNotEmpty) {
        req.response.headers.set(HttpHeaders.contentRangeHeader, cr);
      }
      req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      req.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');

      await req.response.addStream(chosen.stream);
      await req.response.close();
    } catch (e) {
      // ignore: avoid_print
      debugPrint('PIPE: ERR $e');
      try {
        req.response.statusCode = HttpStatus.badGateway;
        await req.response.close();
      } catch (_) {}
    }
  }

  /// Minta [uri] dengan urutan window range yang mengecil. Mengembalikan
  /// respons 200/206 pertama; kalau semua 403, serahkan respons 403 terakhir
  /// supaya lapisan atas bisa memutuskan fallback.
  Future<http.StreamedResponse> _fetchWithRetry(
      Uri uri, String incomingRange, String? cookie,
      {required bool isYoutube}) async {
    final client = _upstream ??= http.Client();
    int fallbackStatus = 503;
    Map<String, String> fallbackHeaders = const {};
    for (final variants in _headerVariants(cookie, isYoutube)) {
      for (final window in _windowSteps) {
        final headers = Map<String, String>.of(variants);
        headers['Range'] = _boundedRangeWith(incomingRange, window);
        final preq = http.Request('GET', uri)..headers.addAll(headers);
        try {
          final presp = await client.send(preq).timeout(const Duration(seconds: 30));
          if (presp.statusCode == 200 || presp.statusCode == 206) {
            return presp;
          }
          if (presp.statusCode != 403) {
            // 404/416/5xx: tidak ada gunanya mencoba range lain.
            return presp;
          }
          fallbackStatus = presp.statusCode;
          fallbackHeaders = Map<String, String>.from(presp.headers);
          debugPrint('PIPE: 403 range=${headers['Range']} -> coba lebih kecil');
          await presp.stream.drain();
        } catch (_) {
          // Timeout/koneksi putus: coba varian berikutnya.
        }
      }
    }
    return http.StreamedResponse(
      const Stream<List<int>>.empty(),
      fallbackStatus,
      headers: fallbackHeaders,
      request: http.Request('GET', uri),
    );
  }

  /// Teruskan SEBAGAI-ADANYA ke relay (Piped proxy_stream / Invidious
  /// latest_version). Relay punya akses penuh; range yang datang dari
  /// pemutar diteruskan tanpa diubah (atau jika relay abaikan Range dan
  /// pulang 200 penuh, ExoPlayer tetap sanggup memainkannya).
  Future<http.StreamedResponse> _fetchRelay(Uri uri, String range) async {
    final client = _upstream ??= http.Client();
    final headers = <String, String>{
      'User-Agent': _userAgent,
      'Accept': '*/*',
      'Accept-Encoding': 'identity;q=1.0, *;q=0',
    };
    if (range.trim().isNotEmpty) headers['Range'] = range.trim();
    final preq = http.Request('GET', uri)..headers.addAll(headers);
    try {
      return await client.send(preq).timeout(const Duration(seconds: 90));
    } catch (_) {
      return http.StreamedResponse(
        const Stream<List<int>>.empty(),
        503,
        headers: const {},
        request: http.Request('GET', uri),
      );
    }
  }

  Future<void> dispose() async {
    final server = _server;
    _server = null;
    _starting = null;
    await server?.close(force: true);
    final upstream = _upstream;
    _upstream = null;
    upstream?.close();
  }
}