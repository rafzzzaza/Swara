import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';
import '../services/cloud_service.dart';

/// Profil pengguna. Disimpan di `shared_preferences` (local-first) dan
/// di-sinkronkan ke tabel `users` Supabase bila cloud aktif.
class ProfileProvider extends ChangeNotifier {
  static const _prefsKey = 'swara_profile_v1';

  final SharedPreferences _prefs;
  final CloudService _cloud;
  final String deviceId;

  UserProfile? _profile;

  ProfileProvider(this._prefs, this._cloud, {required this.deviceId});

  UserProfile? get profile => _profile;
  String get userId => _profile?.id ?? deviceId;

  Future<void> load() async {
    final raw = _prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        _profile = UserProfile.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        _profile = _defaultProfile();
      }
    } else {
      _profile = _defaultProfile();
      await _save();
    }
    notifyListeners();
  }

  UserProfile get profileOrPlaceholder =>
      _profile ?? _defaultProfile();

  UserProfile _defaultProfile() => UserProfile(
        id: deviceId,
        displayName: 'Pengguna Swara',
        bio: 'Penikmat musik sejati.',
        email: '',
      );

  Future<void> update({
    String? displayName,
    String? bio,
    String? email,
    String? avatarKey,
    String? favoriteGenre,
  }) async {
    final current = profileOrPlaceholder;
    _profile = current.copyWith(
      displayName: displayName,
      bio: bio,
      email: email,
      avatarKey: avatarKey,
      favoriteGenre: favoriteGenre,
    );
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final p = _profile;
    if (p == null) return;
    await _prefs.setString(_prefsKey, jsonEncode(p.toJson()));
    await _cloud.upsertProfile(p);
  }
}