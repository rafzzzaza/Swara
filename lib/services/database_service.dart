import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/download_record.dart';
import '../models/play_history_entry.dart';
import '../models/playlist.dart';
import '../models/song.dart';

class DatabaseService {
  static const _dbName = 'musik_app.db';
  static const _dbVersion = 2;

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final path = join(await getDatabasesPath(), _dbName);
    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _db!;
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE play_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          song_id TEXT NOT NULL,
          title TEXT NOT NULL,
          artist TEXT NOT NULL,
          cover_url TEXT,
          played_at TEXT NOT NULL,
          song_json TEXT NOT NULL
        )
      ''');
      await db.execute(
          'CREATE INDEX idx_play_history_played ON play_history(played_at)');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE playlist_songs (
        playlist_id INTEGER NOT NULL,
        song_order INTEGER NOT NULL,
        song_json TEXT NOT NULL,
        PRIMARY KEY (playlist_id, song_order)
      )
    ''');
    await db.execute('''
      CREATE TABLE downloads (
        song_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        file_path TEXT NOT NULL,
        thumbnail TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_playlist_songs ON playlist_songs(playlist_id)');
  }

  // ---------------- Downloads ----------------

  Future<List<DownloadRecord>> getDownloads() async {
    final db = await database;
    final rows = await db.query('downloads', orderBy: 'created_at DESC');
    return rows.map(DownloadRecord.fromJson).toList();
  }

  Future<DownloadRecord?> getDownload(String songId) async {
    final db = await database;
    final rows =
        await db.query('downloads', where: 'song_id = ?', whereArgs: [songId]);
    if (rows.isEmpty) return null;
    return DownloadRecord.fromJson(rows.first);
  }

  Future<void> insertDownload(DownloadRecord record) async {
    final db = await database;
    await db.insert(
      'downloads',
      record.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> removeDownload(String songId) async {
    final db = await database;
    return db.delete('downloads', where: 'song_id = ?', whereArgs: [songId]);
  }

  // ---------------- Playlists ----------------

  Future<List<Playlist>> getPlaylists() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT p.id, p.name, COUNT(ps.song_order) as song_count
      FROM playlists p
      LEFT JOIN playlist_songs ps ON ps.playlist_id = p.id
      GROUP BY p.id
      ORDER BY p.id DESC
    ''');
    return rows.map(Playlist.fromJson).toList();
  }

  Future<int> createPlaylist(String name) async {
    final db = await database;
    return db.insert('playlists', {'name': name});
  }

  Future<void> deletePlaylist(int id) async {
    final db = await database;
    await db.delete('playlists', where: 'id = ?', whereArgs: [id]);
    await db
        .delete('playlist_songs', where: 'playlist_id = ?', whereArgs: [id]);
  }

  Future<void> renamePlaylist(int id, String name) async {
    final db = await database;
    await db.update('playlists', {'name': name},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Song>> getPlaylistSongs(int playlistId) async {
    final db = await database;
    final rows = await db.query(
      'playlist_songs',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'song_order ASC',
    );
    return rows
        .map((r) => Song.fromJson(
            jsonDecode(r['song_json'] as String) as Map<String, dynamic>))
        .toList();
  }

  Future<void> addSongToPlaylist(int playlistId, Song song) async {
    final db = await database;
    final count = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM playlist_songs WHERE playlist_id = ?',
        [playlistId]))!;
    await db.insert('playlist_songs', {
      'playlist_id': playlistId,
      'song_order': count,
      'song_json': jsonEncode(song.toJson()),
    });
  }

  Future<bool> isSongInPlaylist(int playlistId, String songId) async {
    final songs = await getPlaylistSongs(playlistId);
    return songs.any((s) => s.id == songId);
  }

  // ---------------- Play history ----------------

  Future<int> addHistory(PlayHistoryEntry entry) async {
    final db = await database;
    return db.insert('play_history', {
      'song_id': entry.song.id,
      'title': entry.song.title,
      'artist': entry.song.artist,
      'cover_url': entry.song.artUrl ?? entry.song.thumbnailUrl,
      'played_at': entry.playedAt.toIso8601String(),
      'song_json': jsonEncode(entry.song.toJson()),
    });
  }

  Future<List<PlayHistoryEntry>> getHistory({int limit = 200}) async {
    final db = await database;
    final rows = await db.query(
      'play_history',
      orderBy: 'played_at DESC',
      limit: limit,
    );
    return rows
        .map((r) => PlayHistoryEntry(
              id: r['id'] as int,
              song: Song.fromJson(
                  jsonDecode(r['song_json'] as String) as Map<String, dynamic>),
              playedAt:
                  DateTime.parse(r['played_at'] as String),
            ))
        .toList();
  }

  Future<void> clearHistory() async {
    final db = await database;
    await db.delete('play_history');
  }

  Future<void> removeSongFromPlaylist(int playlistId, String songId) async {
    final db = await database;
    final rows = await db.query('playlist_songs',
        where: 'playlist_id = ?', whereArgs: [playlistId]);
    for (final row in rows) {
      final song = Song.fromJson(
          jsonDecode(row['song_json'] as String) as Map<String, dynamic>);
      if (song.id == songId) {
        final order = row['song_order'] as int;
        await db.delete('playlist_songs',
            where: 'playlist_id = ? AND song_order = ?',
            whereArgs: [playlistId, order]);
        await db.rawUpdate(
            'UPDATE playlist_songs SET song_order = song_order - 1 WHERE playlist_id = ? AND song_order > ?',
            [playlistId, order]);
        break;
      }
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}