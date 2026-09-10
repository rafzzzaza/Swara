import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';

/// Downloads the Deezer preview (small mp3) of a song to local storage.
class DownloadService {
  final Dio _dio;
  final Map<String, double> _progress = {};
  final Map<String, bool> _cancelled = {};

  DownloadService()
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
    final url = song.previewUrl;
    if (url == null || url.isEmpty) {
      throw Exception('Lagu "${song.title}" tidak memiliki URL audio.');
    }

    final dir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory(p.join(dir.path, 'downloads'));
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }

    final path = p.join(downloadDir.path, '${song.id}.mp3');
    final tempPath = '$path.part';

    _cancelled[song.id] = false;
    _progress[song.id] = 0;

    CancelToken cancelToken = CancelToken();
    try {
      await _dio.download(
        url,
        tempPath,
        cancelToken: cancelToken,
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
      if (CancelToken.isCancel(e)) {
        try {
          await File(tempPath).delete();
        } catch (_) {}
        return null;
      }
      rethrow;
    } finally {
      _cancelled.remove(song.id);
    }
  }
}