import 'package:supabase_flutter/supabase_flutter.dart'
    hide AuthUser;

import '../models/auth_user.dart';

/// Error ramah untuk ditampilkan ke pengguna (login/pendaftaran).
class SwaraAuthException implements Exception {
  final String message;
  const SwaraAuthException(this.message);

  @override
  String toString() => message;
}

/// Autentikasi ONLINE via Supabase Auth (user database di cloud, bukan lokal).
///
/// Aktif HANYA bila kredensial diberikan saat build:
///   flutter run/build --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
/// Tanpa kredensial, aplikasi berjalan sebagai tamu (offline) — akun online
/// dan login tidak tersedia.
class AuthService {
  static const _url = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const _anonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  static const _usersTable = 'users';

  /// True bila Supabase terkonfigurasi (login online tersedia).
  static bool get enabled => _url.isNotEmpty && _anonKey.isNotEmpty;

  SupabaseClient get _client {
    if (!enabled) {
      throw StateError('Supabase belum dikonfigurasi (dart-define).');
    }
    return Supabase.instance.client;
  }

  /// Inisialisasi Supabase sekali di awal aplikasi. No-op tanpa kredensial.
  static Future<void> initialize() async {
    if (!enabled) return;
    await Supabase.initialize(url: _url, publishableKey: _anonKey);
  }

  /// Akun yang sedang login, atau null bila belum ada sesi.
  Future<AuthUser?> currentUser() async {
    if (!enabled) return null;
    final auth = _client.auth;
    final user = auth.currentUser;
    if (user == null) return null;
    return AuthUser.fromIdEmail(
      user.id,
      user.email ?? '',
      rawDisplayName: (user.userMetadata?['display_name'] as String?) ?? '',
    );
  }

  Future<AuthUser> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final res = await _client.auth.signUp(
      email: email.trim().toLowerCase(),
      password: password,
      data: {'display_name': displayName.trim()},
    );
    final user = res.user;
    if (user == null) {
      throw const SwaraAuthException(
        'Pendaftaran berhasil. Buka email untuk konfirmasi akun, lalu masuk kembali.',
      );
    }
    return AuthUser.fromIdEmail(
      user.id,
      user.email ?? '',
      rawDisplayName: displayName,
    );
  }

  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    final res = await _client.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    final user = res.user;
    if (user == null) {
      throw const SwaraAuthException('Email atau kata sandi salah.');
    }
    return AuthUser.fromIdEmail(
      user.id,
      user.email ?? '',
      rawDisplayName:
          (user.userMetadata?['display_name'] as String?) ?? '',
    );
  }

  Future<void> signOut() async {
    if (!enabled) return;
    await _client.auth.signOut();
  }

  /// Sinkronkan data profil akun ke tabel `users` online.
  Future<void> upsertProfile(AuthUser user, {String? bio, String? avatarKey}) async {
    if (!enabled) return;
    try {
      await _client.from(_usersTable).upsert({
        'id': user.id,
        'email': user.email,
        'display_name': user.displayName,
        'bio': bio,
        'avatar_key': avatarKey,
      });
    } catch (_) {
      // no-op: tetap pakai data lokal bila sync gagal.
    }
  }
}