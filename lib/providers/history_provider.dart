import 'package:flutter/foundation.dart';

import '../models/play_history_entry.dart';
import '../models/song.dart';
import '../services/history_service.dart';

class HistoryProvider extends ChangeNotifier {
  final HistoryService _service;

  List<PlayHistoryEntry> _history = [];
  bool _loading = false;

  HistoryProvider(this._service);

  List<PlayHistoryEntry> get history => _history;
  bool get loading => _loading;
  int get totalPlayed => _history.length;

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    try {
      _history = await _service.latest();
    } catch (_) {
      _history = [];
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> record(Song song) async {
    await _service.record(song);
    await refresh();
  }

  Future<void> clear() async {
    await _service.clear();
    _history = [];
    notifyListeners();
  }
}