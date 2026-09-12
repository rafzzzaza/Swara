import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';
import '../services/audio_pipe_service.dart';
import '../services/audio_resolver.dart';
import '../services/history_service.dart';
import '../services/music_api_service.dart';
import '../services/recommendation_service.dart';

class PlayerProvider extends ChangeNotifier {
  final MusicApiService _api;
  final AudioResolver _resolver;
  final RecommendationService _rec;
  final HistoryService _history;
  final AudioPipeService _pipe;

  late final AudioPlayer _player;

  List<Song> _queue = [];
  List<AudioSource> _children = [];
  int? _currentIndex;
  int _generation = 0;

  List<Song> _recommendations = [];
  bool _recommendationsLoading = false;
  bool _fetchingRecs = false;
  bool _appendingRecs = false;
  bool _preparing = false;
  bool _handlingError = false;

  bool _autoQueue = false;

  /// Sumber cadangan per lagu (URL stream alternatif) — dipakai saat URL
  /// utama kena 403 / mati agar antrean tidak berhenti.
  final Map<String, List<String>> _altsBySongId = {};

  /// Hitung berapa kali lagu restart gara-gara stream terputus. Kalau sudah
  /// 2× tapi masih macet (biasanya karena dinding 1 MiB googlevideo), skip
  /// ke lagu berikutnya supaya tidak restart-loops selamanya.
  final Map<String, int> _restartsBySong = {};

  final StreamController<String> _errors = StreamController.broadcast();
  Stream<String> get errorStream => _errors.stream;
  bool get isPreparing => _preparing;

  /// Watchdog anti-stream-buntung: ExoPlayer kadang tidak mengeluarkan
  /// error saat HTTP 403 membekukan playhead (state tetap PLAYING). Bila
  /// posisi tidak bergerak selama ~10 detik padahal statusnya playing,
  /// force `_handlePlaybackError()` supaya fallback berlapis berjalan.
  Timer? _watch;
  Duration _lastPos = Duration.zero;
  int _frozenTicks = 0;

  void _watchStall(Timer _) {
    if (_handlingError || _preparing || !_player.playing || _queue.isEmpty) {
      return;
    }
    try {
      final pos = _player.position;
      final started = pos > const Duration(milliseconds: 700);
      final moved = pos - _lastPos;
      if (started &&
          _lastPos > Duration.zero &&
          moved < const Duration(milliseconds: 700)) {
        _frozenTicks++;
      } else {
        _frozenTicks = 0;
        final s = currentSong;
        if (s != null) _restartsBySong.remove(s.id);
      }
      _lastPos = pos;
      if (_frozenTicks >= 5) {
        _frozenTicks = 0;
        // ignore: avoid_print
        debugPrint('YT: playhead beku di $pos -> tangani error stream');
        unawaited(_handlePlaybackError());
      }
    } catch (_) {
      _frozenTicks = 0;
    }
  }

  /// Berapa stream YouTube yang boleh di-resolve bersamaan.
  /// Concurrency terbatas mencegah lonjakan request yang bikin lag.
  static const _resolveConcurrency = 4;

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  PlayerProvider(
    this._api,
    this._resolver,
    this._rec,
    this._history, {
    AudioPipeService? pipe,
  })  : _pipe = pipe ?? AudioPipeService() {
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

    _player.errorStream.listen((e) {
      // ignore: avoid_print
      debugPrint('YT: errorStream $e');
      unawaited(_handlePlaybackError());
    });

    _watch = Timer.periodic(const Duration(seconds: 2), _watchStall);
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

  /// Resolve [count] item secara paralel (maks [concurrency]) dan kembalikan
  /// hasil per indeks. Item yang gagal bernilai null.
  Future<List<T?>> _collectConcurrency<T>(
    int count,
    int concurrency,
    Future<T?> Function(int i) resolve,
  ) async {
    final results = List<T?>.filled(count, null);
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= count) return;
        results[i] = await resolve(i);
      }
    }

    final workers = <Future<void>>[
      for (var w = 0; w < concurrency && w < count; w++) worker(),
    ];
    await Future.wait(workers);
    return results;
  }

  /// Builds the audio source for [song].
  ///
  /// Sumber audio PENUH: file lokal -> stream full-length YouTube.
  /// Deezer preview TIDAK dipakai lagi (API Deezer permanen 30 detik).
  /// [cachedOnly] membatasi pencarian YouTube hanya ke cache in-memory
  /// (cepat, non-blokir) — tetap tidak pernah memakai preview.
  Future<AudioSource?> _sourceFor(Song song, {bool cachedOnly = false}) async {
    final mediaItem = _toMediaItem(song);

    if (song.isLocal && song.localPath != null) {
      return AudioSource.uri(Uri.file(song.localPath!), tag: mediaItem);
    }

    final ytUrls = await _resolver.resolve(song, cachedOnly: cachedOnly);
    if (ytUrls.isEmpty) return null;
    final uri = await _pipe.wrap(ytUrls.first);
    _pipe.sessionCookie = _resolver.sessionCookie;
    if (ytUrls.length > 1) {
      _altsBySongId[song.id] = ytUrls.sublist(1);
    }
    return AudioSource.uri(
      uri,
      tag: mediaItem,
      headers: const {
        'User-Agent': _userAgent,
        'Accept-Language': 'en-US,en;q=0.9',
      },
    );
  }

  Future<void> playQueue(List<Song> songs, {int index = 0}) async {
    if (songs.isEmpty) return;
    notifyListeners();

    // 1) Lagu yang di-tap di-resolve PENUH dulu (blocking ~1-3 detik).
    //    Cari stream full-length YouTube "Judul + Artis" lalu putar lewat
    //    just_audio. Tidak ada fallback preview 30 detik.
    final gen = ++_generation;
    final desired = List<Song>.of(songs);
    _preparing = true;
    notifyListeners();
    final primary = await _sourceFor(desired[index]);
    if (primary == null) {
      _preparing = false;
      _errors.add(
          'Audio penuh tidak ditemukan untuk "${desired[index].title}".');
      notifyListeners();
      return;
    }

    // 2) Putar lagu pertama segera (full audio).
    _queue = [desired[index]];
    _children = [primary];
    try {
      await _player.stop();
      await _player.setAudioSources(_children, initialIndex: 0);
      _currentIndex = 0;
      await _player.play();
    } catch (_) {}
    _preparing = false;
    notifyListeners();

    _recordActivity(desired[index]);
    unawaited(loadRecommendations());
    if (_autoQueue) _maybeAutoAppend();

    // 3) Sisa antrean di-resolve penuh di background, lalu disisipkan
    //    berurutan tanpa menghentikan lagu yang sedang diputar.
    unawaited(_fillQueueRest(gen, desired));
  }

  /// Resolve & masukkan sisa [desired] (setelah lagu pertama) ke antrean.
  Future<void> _fillQueueRest(int gen, List<Song> desired) async {
    if (desired.length <= 1) return;
    final count = desired.length - 1;
    final srcs = await _collectConcurrency<AudioSource?>(
      count,
      _resolveConcurrency,
      (k) => _sourceFor(desired[k + 1]),
    );
    if (gen != _generation || _queue.isEmpty) return;

    final newQueue = <Song>[_queue.first];
    final newChildren = <AudioSource>[_children.first];
    for (var k = 0; k < count; k++) {
      final src = srcs[k];
      if (src == null) continue;
      newQueue.add(desired[k + 1]);
      newChildren.add(src);
    }
    _queue = newQueue;
    _children = newChildren;
    await _applyChildrenSwap();
  }

  /// Mencatat aktivitas pemutaran lokal (rekomendasi + riwayat).
  Future<void> _recordActivity(Song song) async {
    try {
      await _rec.recordPlay(song.artist, genre: song.genre);
      await _history.record(song);
    } catch (_) {}
  }

  /// Menerapkan daftar sumber ke player tanpa menginterupsi lagu yang
  /// sedang diputar (posisi & status dipilih kembali).
  Future<void> _applyChildrenSwap() async {
    if (_children.isEmpty) return;
    final ci = (_currentIndex ?? 0).clamp(0, _children.length - 1);
    final wasPlaying = _player.playing;
    final pos = _player.position;
    try {
      await _player.setAudioSources(_children, initialIndex: ci);
      await _player.seek(pos);
      if (wasPlaying && !_player.playing) {
        await _player.play();
      }
    } catch (_) {}
  }

  /// Dipanggil saat stream yang sedang diputar error (403/timeout/expired).
  /// Urutan: URL cadangan -> resolve ulang -> skip ke lagu berikutnya.
  Future<void> _handlePlaybackError() async {
    if (_handlingError) return;
    final ci = _currentIndex;
    if (ci == null || ci < 0 || ci >= _queue.length) return;
    final song = _queue[ci];
    _handlingError = true;
    try {
      final alts = _altsBySongId[song.id];
      if (alts != null && alts.isNotEmpty) {
        final url = alts.removeAt(0);
        // ignore: avoid_print
        debugPrint('YT: stream utama gagal, coba URL cadangan "${song.title}"');
        await _swapSourceAt(ci, url, song);
        await _player.play();
        return;
      }

      // Semua cadangan habis: invalidate cache & resolve ulang sekali.
      // Maksimal 2× restart; kalau masih macet (dinding 1 MiB), skip.
      _resolver.invalidate(song);
      final fresh = await _resolver.resolve(song);
      if (fresh.isNotEmpty) {
        final restarts = (_restartsBySong[song.id] ?? 0) + 1;
        _restartsBySong[song.id] = restarts;
        if (restarts < 3) {
          _altsBySongId[song.id] = fresh.sublist(1);
          // ignore: avoid_print
          debugPrint('YT: resolve ulang "${song.title}" restart#=$restarts');
          await _swapSourceAt(ci, fresh.first, song);
          await _player.play();
          return;
        }
      }

      _errors.add('Gagal memuat audio "${song.title}".');
      if (ci + 1 < _children.length) {
        await _player.seek(Duration.zero, index: ci + 1);
        await _player.play();
      } else {
        await _player.stop();
      }
    } catch (_) {} finally {
      _handlingError = false;
    }
  }

  /// Ganti sumber pada [index] dengan URL stream baru, tanpa menghentikan
  /// antrean (posisi & status dipilih kembali oleh [_applyChildrenSwap]).
  Future<void> _swapSourceAt(int index, String ytUrl, Song song) async {
    final mediaItem = _toMediaItem(song);
    final uri = await _pipe.wrap(ytUrl);
    final src = AudioSource.uri(
      uri,
      tag: mediaItem,
      headers: const {
        'User-Agent': _userAgent,
        'Accept-Language': 'en-US,en;q=0.9',
      },
    );
    if (index >= 0 && index < _children.length) {
      _children[index] = src;
    } else {
      _children = [src];
    }
    await _applyChildrenSwap();
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

  Future<void> insertNext(Song song) async {
    if (_queue.isEmpty) {
      await playQueue([song], index: 0);
      return;
    }
    ++_generation;
    final source = await _sourceFor(song);
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
  }

  Future<void> addToQueue(Song song) async {
    if (_queue.isEmpty) {
      await playQueue([song], index: 0);
      return;
    }
    ++_generation;
    final source = await _sourceFor(song);
    if (source == null) return;
    try {
      await _player.addAudioSources([source]);
      _children.add(source);
      _queue.add(song);
    } catch (_) {
      return;
    }
    notifyListeners();
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
        final srcs = await _collectConcurrency<AudioSource?>(
          pick.length,
          _resolveConcurrency,
          (k) => _sourceFor(pick[k]),
        );
        if (gen != _generation || _queue.isEmpty) return;
        final songs = <Song>[];
        final sources = <AudioSource>[];
        for (var k = 0; k < pick.length; k++) {
          final src = srcs[k];
          if (src == null) continue;
          songs.add(pick[k]);
          sources.add(src);
        }
        if (sources.isNotEmpty) {
          await _player.addAudioSources(sources);
          _children.addAll(sources);
          _queue.addAll(songs);
          notifyListeners();
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
    _watch?.cancel();
    _player.dispose();
    _resolver.dispose();
    _pipe.dispose();
    _errors.close();
    super.dispose();
  }
}