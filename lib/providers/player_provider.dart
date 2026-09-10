import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';
import '../services/history_service.dart';
import '../services/music_api_service.dart';
import '../services/recommendation_service.dart';
import '../services/youtube_audio_service.dart';

class PlayerProvider extends ChangeNotifier {
  final MusicApiService _api;
  final YoutubeAudioService _yt;
  final RecommendationService _rec;
  final HistoryService _history;

  late final AudioPlayer _player;

  List<Song> _queue = [];
  List<AudioSource> _children = [];
  int? _currentIndex;
  int _generation = 0;

  List<Song> _recommendations = [];
  bool _recommendationsLoading = false;
  bool _fetchingRecs = false;
  bool _appendingRecs = false;

  bool _autoQueue = false;

  /// Berapa sumber audio YouTube yang boleh di-resolve bersamaan.
  /// Concurrency terbatas mencegah lonjakan request yang bikin lag.
  static const _satelliteConcurrency = 3;

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  PlayerProvider(this._api, this._yt, this._rec, this._history) {
    _player = AudioPlayer();

    _player.currentIndexStream.listen((index) {
      if (index != null && index != _currentIndex) {
        _currentIndex = index;
        notifyListeners();
        if (_autoQueue) _maybeAutoAppend();
      }
    });

    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) notifyListeners();
    });

    _player.playbackEventStream.listen((event) {
      if (event.currentIndex != null) {
        final idx = event.currentIndex!;
        if (idx != _currentIndex) {
          _currentIndex = idx;
          notifyListeners();
          if (_autoQueue) _maybeAutoAppend();
        }
      }
    });
  }

  AudioPlayer get audioPlayer => _player;
  List<Song> get queue => _queue;
  bool get autoQueueEnabled => _autoQueue;
  List<Song> get recommendations => _recommendations;
  bool get recommendationsLoading => _recommendationsLoading;

  Song? get currentSong =>
      (_currentIndex != null && _currentIndex! >= 0 &&
              _currentIndex! < _queue.length)
          ? _queue[_currentIndex!]
          : null;

  List<Song> get upcoming {
    final ci = _currentIndex ?? 0;
    if (ci < 0 || ci >= _queue.length) return const [];
    return _queue.sublist(ci + 1);
  }

  int? get currentIndex => _currentIndex;
  bool get hasAny => _queue.isNotEmpty;
  bool get isPlaying => _player.playing;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<ProcessingState> get processingStateStream =>
      _player.processingStateStream;
  Stream<bool> get playingStream => _player.playingStream;
  Stream<int?> get currentIndexStream => _player.currentIndexStream;
  bool get shuffleModeEnabled => _player.shuffleModeEnabled;
  LoopMode get loopMode => _player.loopMode;
  double get volume => _player.volume;

  /// Jalankan [tasks] dengan maksimal [concurrency] task paralel.
  Future<void> _runWithConcurrency(
    int count,
    int concurrency,
    Future<void> Function(int i) task,
  ) async {
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= count) return;
        await task(i);
      }
    }

    final workers = <Future<void>>[
      for (var w = 0; w < concurrency && w < count; w++) worker(),
    ];
    await Future.wait(workers);
  }

  /// Builds the audio source for [song].
  ///
  /// Priority: local file (full) -> full-length YouTube stream -> Deezer
  /// 30s preview. [cachedOnly] makes the YouTube lookup non-blocking by
  /// only consulting the in-memory resolution cache.
  Future<AudioSource?> _sourceFor(Song song, {bool cachedOnly = false}) async {
    final mediaItem = _toMediaItem(song);

    if (song.isLocal && song.localPath != null) {
      return AudioSource.uri(Uri.file(song.localPath!), tag: mediaItem);
    }

    final ytUrl = await _yt.resolve(song, cachedOnly: cachedOnly);
    if (ytUrl != null) {
      return AudioSource.uri(
        Uri.parse(ytUrl),
        tag: mediaItem,
        headers: const {
          'User-Agent': _userAgent,
          'Accept-Language': 'en-US,en;q=0.9',
        },
      );
    }

    final uri = Uri.tryParse(song.previewUrl ?? '');
    if (uri == null || !uri.hasScheme) return null;
    return AudioSource.uri(uri, tag: mediaItem);
  }

  Future<void> playQueue(List<Song> songs, {int index = 0}) async {
    if (songs.isEmpty) return;
    notifyListeners();

    // 1) Lagu yang di-tap di-resolve penuh dulu (langsung muter full).
    final primarySource = await _sourceFor(songs[index]);
    if (primarySource == null) {
      notifyListeners();
      return;
    }

    // 2) Sisa queue di-resolve dari cache (cepat) agar build tidak nge-blok.
    final satIdx = <int>[];
    for (var i = 0; i < songs.length; i++) {
      if (i != index) satIdx.add(i);
    }
    final satFutures = <Future<AudioSource?>>[
      for (final i in satIdx) _sourceFor(songs[i], cachedOnly: true),
    ];
    final satResults = await Future.wait(satFutures);

    // 3) Rakit ulang urutan asli.
    final children = <AudioSource>[];
    final resolvedSongs = <Song>[];
    var satK = 0;
    for (var i = 0; i < songs.length; i++) {
      AudioSource? src;
      if (i == index) {
        src = primarySource;
      } else {
        src = satResults[satK++];
      }
      if (src == null) continue;
      resolvedSongs.add(songs[i]);
      children.add(src);
      if (i == index) index = resolvedSongs.length - 1;
    }
    if (children.isEmpty) {
      notifyListeners();
      return;
    }

    _queue = List.of(resolvedSongs);
    _children = children;
    index = index.clamp(0, _queue.length - 1);
    final gen = ++_generation;

    try {
      await _player.stop();
      await _player.setAudioSources(_children, initialIndex: index);
      _currentIndex = index;
      await _player.play();
    } catch (_) {}
    notifyListeners();

    _recordActivity(resolvedSongs[index]);
    unawaited(loadRecommendations());
    if (_autoQueue) _maybeAutoAppend();

    // 4) Upgrade seluruh queue ke full-length YouTube di background,
    //    tanpa memblokir pemutaran.
    unawaited(_upgradeQueueFull(gen, _queue.length));
  }

  /// Mencatat aktivitas pemutaran lokal (rekomendasi + riwayat).
  Future<void> _recordActivity(Song song) async {
    try {
      await _rec.recordPlay(song.artist, genre: song.genre);
      await _history.record(song);
    } catch (_) {}
  }

  /// Upgrade semua indeks queue menjadi full-length (bukan preview 30 detik).
  Future<void> _upgradeQueueFull(int gen, int length) async {
    await _runWithConcurrency(length, _satelliteConcurrency, (i) async {
      await _upgradeIndex(gen, i);
    });
  }

  Future<void> _upgradeIndex(int gen, int i) async {
    if (i < 0 || i >= _queue.length || i >= _children.length) return;
    final song = _queue[i];
    if (song.isLocal && song.localPath != null) return;
    final full = await _sourceFor(song);
    if (full == null) return;
    if (gen != _generation) return;
    if (i >= _children.length || identical(_children[i], full)) return;
    _children[i] = full;
    try {
      final ci = (_currentIndex ?? 0).clamp(0, _children.length - 1);
      await _player.setAudioSources(_children, initialIndex: ci);
    } catch (_) {}
  }

  Future<void> playSong(Song song) async {
    if (song.isLocal && song.localPath != null) {
      await _playLocal(song);
      return;
    }
    final existing = _queue.indexWhere((s) => s.id == song.id);
    if (existing == _currentIndex && _currentIndex != null) {
      await resume();
      notifyListeners();
      return;
    }
    if (existing >= 0) {
      await _player.seek(Duration.zero, index: existing);
      _currentIndex = existing;
      await _player.play();
      notifyListeners();
      unawaited(_recordActivity(song));
      return;
    }
    await playQueue([song], index: 0);
  }

  Future<void> _playLocal(Song song) async {
    if (song.localPath == null) return;
    await _player.stop();
    try {
      final src = AudioSource.uri(
        Uri.file(song.localPath!),
        tag: _toMediaItem(song),
      );
      _children = [src];
      await _player.setAudioSource(src);
      _queue = [song];
      _currentIndex = 0;
      await _player.play();
    } catch (_) {}
    notifyListeners();
    unawaited(_recordActivity(song));
  }

  Future<void> insertNext(Song song) async {
    if (_queue.isEmpty) {
      await playQueue([song], index: 0);
      return;
    }
    final gen = ++_generation;
    final source = await _sourceFor(song, cachedOnly: true);
    if (source == null) return;
    final insertAt = (_currentIndex ?? 0).clamp(0, _queue.length);
    try {
      await _player.insertAudioSource(insertAt + 1, source);
      _children.insert(insertAt + 1, source);
      _queue.insert(insertAt + 1, song);
    } catch (_) {
      return;
    }
    notifyListeners();
    unawaited(_upgradeIndex(gen, insertAt + 1));
  }

  Future<void> addToQueue(Song song) async {
    if (_queue.isEmpty) {
      await playQueue([song], index: 0);
      return;
    }
    final gen = ++_generation;
    final source = await _sourceFor(song, cachedOnly: true);
    if (source == null) return;
    try {
      await _player.addAudioSources([source]);
      _children.add(source);
      _queue.add(song);
    } catch (_) {
      return;
    }
    notifyListeners();
    unawaited(_upgradeIndex(gen, _children.length - 1));
  }

  Future<void> skipTo(int index) async {
    if (index < 0 || index >= _queue.length) return;
    await _player.seek(Duration.zero, index: index);
    _currentIndex = index;
    notifyListeners();
  }

  Future<void> loadRecommendations({int limit = 10}) async {
    final base = currentSong;
    if (base == null || _fetchingRecs) return;
    _fetchingRecs = true;
    _recommendationsLoading = true;
    notifyListeners();

    final seen = <String>{
      for (final s in _queue) s.id,
      for (final s in _recommendations) s.id,
    };

    var results = <Song>[];
    try {
      final query =
          base.artist.isNotEmpty ? base.artist : base.title.trim();
      results = await _api.searchSongs(query, limit: 24);
      if (results.length < 3 && base.artist.isNotEmpty) {
        results = await _api.searchSongs('${base.artist} hits', limit: 24);
      }
    } catch (_) {
      results = [];
    }

    _recommendations = results
        .where((s) => !seen.contains(s.id))
        .take(limit)
        .toList();

    _fetchingRecs = false;
    _recommendationsLoading = false;
    notifyListeners();
  }

  Future<void> _appendRecommendationsToQueue() async {
    if (_appendingRecs || _queue.isEmpty) return;
    _appendingRecs = true;
    try {
      if (_recommendations.isEmpty) {
        await loadRecommendations();
      }
      if (_recommendations.isEmpty) return;
      final used = <String>{for (final s in _queue) s.id};
      final pick =
          _recommendations.where((s) => !used.contains(s.id)).take(8).toList();
      if (pick.isNotEmpty) {
        final gen = ++_generation;
        final sources = <AudioSource>[];
        for (final s in pick) {
          final src = await _sourceFor(s, cachedOnly: true);
          if (src != null) sources.add(src);
        }
        if (sources.isNotEmpty) {
          await _player.addAudioSources(sources);
          _children.addAll(sources);
          _queue.addAll(pick);
          notifyListeners();
          unawaited(_runWithConcurrency(
            sources.length,
            _satelliteConcurrency,
            (k) async {
              final i = _children.length - sources.length + k;
              await _upgradeIndex(gen, i);
            },
          ));
        }
      }
    } catch (_) {}
    _appendingRecs = false;
  }

  Future<void> _maybeAutoAppend() async {
    if (!_autoQueue) return;
    final ci = _currentIndex;
    if (ci == null || _queue.isEmpty) return;
    if (_queue.length - ci - 1 <= 2) {
      await _appendRecommendationsToQueue();
    }
  }

  Future<void> setAutoQueue(bool value) async {
    _autoQueue = value;
    notifyListeners();
    if (value) {
      if (_recommendations.isEmpty) unawaited(loadRecommendations());
      unawaited(_maybeAutoAppend());
    }
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> resume() async {
    if (_queue.isEmpty) return;
    await _player.play();
    notifyListeners();
  }

  Future<void> pause() async {
    await _player.pause();
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
    notifyListeners();
  }

  Future<void> next() async {
    _player
        .seek(Duration.zero, index: (_currentIndex ?? 0) + 1)
        .catchError((_) {});
    notifyListeners();
  }

  Future<void> previous() async {
    final position = _player.position;
    if (position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      notifyListeners();
      return;
    }
    _player
        .seek(Duration.zero, index: ((_currentIndex ?? 1) - 1).clamp(0, 1 << 30));
    notifyListeners();
  }

  Future<void> toggleShuffle() async {
    await _player.setShuffleModeEnabled(!_player.shuffleModeEnabled);
    notifyListeners();
  }

  Future<void> cycleLoopMode() async {
    final modes = [LoopMode.off, LoopMode.all, LoopMode.one];
    final current = modes.indexOf(_player.loopMode);
    await _player.setLoopMode(modes[(current + 1) % modes.length]);
    notifyListeners();
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
    notifyListeners();
  }

  MediaItem _toMediaItem(Song song) => MediaItem(
        id: song.id,
        title: song.title,
        artist: song.artist,
        album: song.album?.isNotEmpty == true ? song.album! : 'Swara',
        duration: song.duration,
        artUri: song.artUrl != null
            ? Uri.tryParse(song.artUrl!)
            : (song.thumbnailUrl != null
                ? Uri.tryParse(song.thumbnailUrl!)
                : null),
      );

  @override
  void dispose() {
    _player.dispose();
    _yt.dispose();
    super.dispose();
  }
}