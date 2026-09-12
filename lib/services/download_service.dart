import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';
import 'audio_resolver.dart';

/// Downloads the full-length audio (multi-provider: Audius/IA/Jamendo/YT)
/// of a song to local storage. Deezer previews are NOT used (30 detik).
class DownloadService {
  final AudioResolver _resolver;
  final Dio _dio;
  final Map<String, double> _progress = {};
  final Map<String, bool> _cancelled = {};

  DownloadService(this._resolver)
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
        ));

  double? progressFor(String songId) => _progress[songId];

  void cancel(String songId) {
    _cancelled[songId] = true;
  }

  /// Downloads the given song and returns the local file path.
  /// Returns null if cancelled.
  Future<String?> download(Song song,
      {void Function(double progress)? onProgress}) async {
    final urls = await _resolver.resolve(song);
    if (urls.isEmpty) {
      throw Exception(
          'Lagu "${song.title}" tidak bisa diunduh (audio penuh tidak ditemukan).');
    }

    final dir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory(p.join(dir.path, 'downloads'));
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }

    final path = p.join(downloadDir.path, '${song.id}.m4a');
    final tempPath = '$path.part';

    _cancelled[song.id] = false;
    _progress[song.id] = 0;

    Object? lastError;
    try {
      for (final url in urls) {
        if (_cancelled[song.id] == true) return null;
        CancelToken cancelToken = CancelToken();
        try {
          var headers = <String, String>{
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          };
          final host = Uri.tryParse(url)?.host ?? '';
          if (host.contains('googlevideo') || host.contains('youtube')) {
            headers = {...headers, 'Referer': 'https://www.youtube.com/'};
          }
          await _dio.download(
            url,
            tempPath,
            cancelToken: cancelToken,
            options: Options(headers: headers),
            onReceiveProgress: (received, total) {
              if (_cancelled[song.id] == true) {
                cancelToken.cancel();
                return;
              }
              final value =
                  (total > 0) ? (received / total).clamp(0.0, 1.0) : 0.0;
              _progress[song.id] = value;
              onProgress?.call(value);
            },
          );
          if (_cancelled[song.id] == true) {
            try {
              await File(tempPath).delete();
            } catch (_) {}
            return null;
          }
          await File(tempPath).rename(path);
          _progress[song.id] = 1.0;
          return path;
        } on DioException catch (e) {
          lastError = e;
          if (CancelToken.isCancel(e)) {
            try {
              await File(tempPath).delete();
            } catch (_) {}
            return null;
          }
          final code = e.response?.statusCode ?? 0;
          if (code == 403 || code == 416 || code == 404) {
            // URL mati/diblokir: coba URL cadangan berikutnya.
            try {
              await File(tempPath).delete();
            } catch (_) {}
            continue;
          }
        }
      }
    } finally {
      _cancelled.remove(song.id);
    }
    if (lastError is DioException) throw lastError;
    throw Exception(
        'Lagu "${song.title}" gagal diunduh (semua sumber dimatikan).');
  }
}