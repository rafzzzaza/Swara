import 'package:flutter/foundation.dart';

import '../models/auth_user.dart';
import '../services/auth_service.dart';

/// State autentikasi aplikasi (login online Supabase / mode tamu).
class AuthProvider extends ChangeNotifier {
  final AuthService _service;

  AuthUser? _user;
  bool _initialized = false; // keputusan pertama sudah diambil / sesi dimuat
  bool _guest = false; // user memilih lanjut tanpa akun
  bool _loading = false;
  String? _error;

  AuthProvider(this._service);

  bool get initialized => _initialized;
  bool get isGuest => _guest;
  bool get loggedIn => _user != null;
  bool get loading => _loading;
  String? get error => _error;
  AuthUser? get user => _user;
  String get userId => _user?.id ?? 'guest';
  bool get onlineEnabled => AuthService.enabled;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    if (onlineEnabled) {
      try {
        _user = await _service.currentUser();
      } catch (_) {
        _user = null;
      }
    }
    _guest = !onlineEnabled;
    _initialized = true;
    _loading = false;
    notifyListeners();
  }

  Future<bool> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    return _run(() => _service.signUp(
          email: email,
          password: password,
          displayName: displayName,
        ));
  }

  Future<bool> login({required String email, required String password}) async {
    return _run(() => _service.signIn(email: email, password: password));
  }

  Future<bool> _run(Future<AuthUser> Function() task) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _user = await task();
      _guest = false;
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error =
          e is SwaraAuthException ? e.message : _friendlyMessage(e.toString());
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// Lanjut memakai aplikasi tanpa akun (data pribadi tersimpan lokal).
  void continueAsGuest() {
    _user = null;
    _guest = true;
    _initialized = true;
    notifyListeners();
  }

  /// Tampilkan pesan error validasi lokal tanpa request jaringan.
  void showInlineError(String message) {
    _error = message;
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await _service.signOut();
    } catch (_) {}
    _user = null;
    _guest = false;
    _initialized = true;
    notifyListeners();
  }

  String _friendlyMessage(String raw) {
    if (raw.toLowerCase().contains('invalid login credentials')) {
      return 'Email atau kata sandi salah.';
    }
    if (raw.toLowerCase().contains('already registered') ||
        raw.toLowerCase().contains('user already')) {
      return 'Email sudah terdaftar. Silakan masuk.';
    }
    if (raw.toLowerCase().contains('rate limit')) {
      return 'Terlalu banyak percobaan. Coba lagi beberapa saat.';
    }
    if (raw.toLowerCase().contains('email not confirmed')) {
      return 'Email belum dikonfirmasi. Cek kotak masuk emailmu.';
    }
    return 'Gagal terhubung ke server. Periksa koneksi lalu coba lagi.';
  }
}