/// Akun pengguna dari Supabase Auth (database online).
class AuthUser {
  final String id;
  final String email;
  final String displayName;

  const AuthUser({
    required this.id,
    required this.email,
    required this.displayName,
  });

  factory AuthUser.fromIdEmail(String id, String email, {String? rawDisplayName}) =>
      AuthUser(
        id: id,
        email: email,
        displayName: _fallbackName(email, rawDisplayName),
      );

  static String _fallbackName(String email, String? custom) {
    final name = custom?.trim();
    if (name != null && name.isNotEmpty) return name;
    return email.contains('@') ? email.split('@').first : email;
  }
}