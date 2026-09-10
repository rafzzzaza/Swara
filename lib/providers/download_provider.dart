import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/download_record.dart';
import '../models/song.dart';
import '../services/database_service.dart';
import '../services/download_service.dart';

class DownloadProvider extends ChangeNotifier {
  final DownloadService _service;
  final DatabaseService _db;

  List<DownloadRecord> _downloads = [];
  final Map<String, double> _progress = {};
  final Map<String, bool> _downloading = {};

  DownloadProvider(this._service, this._db);

  List<DownloadRecord> get downloads => _downloads;
  List<Song> get songs =>
      _downloads.map((d) => d.asSong).toList();
  bool isDownloading(String id) => _downloading[id] ?? false;
  double? progress(String id) => _progress[id];

  Future<void> refresh() async {
    _downloads = await _db.getDownloads();
    notifyListeners();
  }

  Future<bool> isDownloaded(String songId) async {
    return await _db.getDownload(songId) != null;
  }

  Future<DownloadRecord?> getRecord(String songId) =>
      _db.getDownload(songId);

  Future<void> startDownload(Song song) async {
    if (_downloading[song.id] == true) return;
    _downloading[song.id] = true;
    _progress[song.id] = 0;
    notifyListeners();
    try {
      final path = await _service.download(song,
          onProgress: (value) {
            _progress[song.id] = value;
            notifyListeners();
          });
      if (path == null) {
        _downloading.remove(song.id);
        _progress.remove(song.id);
        notifyListeners();
        return;
      }
      final record = DownloadRecord(
        songId: song.id,
        title: song.title,
        artist: song.artist,
        filePath: path,
        thumbnailUrl: song.thumbnailUrl,
        createdAt: DateTime.now(),
      );
      await _db.insertDownload(record);
      _downloading.remove(song.id);
      _progress.remove(song.id);
      await refresh();
    } catch (e) {
      _downloading.remove(song.id);
      _progress.remove(song.id);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> cancelDownload(Song song) async {
    _service.cancel(song.id);
  }

  Future<void> removeDownload(DownloadRecord record) async {
    await _db.removeDownload(record.songId);
    final file = File(record.filePath);
    if (await file.exists()) {
      try { await file.delete(); } catch (_) {}
    }
    await refresh();
  }

  Future<void> removeAll() async {
    for (final record in List.of(_downloads)) {
      await removeDownload(record);
    }
  }
}