/// Profil pengguna Swara (local-first; disinkronkan ke Supabase bila aktif).
class UserProfile {
  final String id;
  final String displayName;
  final String bio;
  final String email;
  final String? avatarKey;
  final String? favoriteGenre;

  const UserProfile({
    required this.id,
    required this.displayName,
    this.bio = '',
    this.email = '',
    this.avatarKey,
    this.favoriteGenre,
  });

  UserProfile copyWith({
    String? displayName,
    String? bio,
    String? email,
    String? avatarKey,
    String? favoriteGenre,
  }) =>
      UserProfile(
        id: id,
        displayName: displayName ?? this.displayName,
        bio: bio ?? this.bio,
        email: email ?? this.email,
        avatarKey: avatarKey ?? this.avatarKey,
        favoriteGenre: favoriteGenre ?? this.favoriteGenre,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'bio': bio,
        'email': email,
        'avatarKey': avatarKey,
        'favoriteGenre': favoriteGenre,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        displayName: (json['displayName'] as String?) ?? 'Pengguna Swara',
        bio: (json['bio'] as String?) ?? '',
        email: (json['email'] as String?) ?? '',
        avatarKey: json['avatarKey'] as String?,
        favoriteGenre: json['favoriteGenre'] as String?,
      );
}