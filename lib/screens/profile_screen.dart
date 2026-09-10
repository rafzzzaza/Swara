import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../providers/history_provider.dart';
import '../providers/playlist_provider.dart';
import '../providers/profile_provider.dart';
import '../services/cloud_service.dart';
import '../services/recommendation_service.dart';
import 'history_screen.dart';

const _avatars = <String, IconData>{
  'person': Icons.person,
  'headphones': Icons.headphones,
  'mic': Icons.mic,
  'piano': Icons.piano,
  'album': Icons.album,
  'star': Icons.star,
  'bolt': Icons.bolt,
  'waves': Icons.waves,
};

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HistoryProvider>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileProvider>();
    final history = context.watch<HistoryProvider>();
    final playlists = context.watch<PlaylistProvider>();
    final rec = context.read<RecommendationService>();

    final favoriteGenres = rec.topGenres(limit: 1);
    final favoriteGenre =
        favoriteGenres.isEmpty ? 'Belum ada' : _capitalize(favoriteGenres.first);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        actions: [
          IconButton(
            tooltip: 'Notifikasi',
            icon: const Icon(Icons.notifications_none),
            onPressed: () {},
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          Center(child: _Avatar(profile: profile)),
          const SizedBox(height: 12),
          Center(
            child: Text(
              profile.profileOrPlaceholder.displayName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          if (profile.profileOrPlaceholder.bio.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Center(
                child: Text(
                  profile.profileOrPlaceholder.bio,
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.6)),
                ),
              ),
            ),
          if (profile.profileOrPlaceholder.email.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Center(
                child: Text(
                  profile.profileOrPlaceholder.email,
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.45)),
                ),
              ),
            ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _StatItem(label: 'Total diputar', value: '${history.totalPlayed}'),
                const SizedBox(width: 10),
                _StatItem(label: 'Genre favorit', value: favoriteGenre),
                const SizedBox(width: 10),
                _StatItem(label: 'Playlist', value: '${playlists.playlists.length}'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Divider(height: 20, thickness: 0.5, color: Colors.white12),
          _MenuTile(
            icon: Icons.edit_outlined,
            title: 'Edit Profil',
            onTap: () => _editProfile(context),
          ),
          _MenuTile(
            icon: Icons.history,
            title: 'Riwayat Pemutaran',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
          _MenuTile(
            icon: Icons.settings_outlined,
            title: 'Pengaturan Aplikasi',
            onTap: () => _appSettings(context),
          ),
          const Divider(height: 8, thickness: 0.5, color: Colors.white12),
          _MenuTile(
            icon: Icons.logout,
            title: 'Keluar',
            iconColor: const Color(0xFFE2334B),
            titleColor: const Color(0xFFE2334B),
            onTap: () => _logout(context),
          ),
        ],
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Future<void> _editProfile(BuildContext context) async {
    final profile = context.read<ProfileProvider>().profileOrPlaceholder;
    final name = TextEditingController(text: profile.displayName);
    final bio = TextEditingController(text: profile.bio);
    final email = TextEditingController(text: profile.email);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Profil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nama pengguna'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: bio,
              decoration: const InputDecoration(labelText: 'Status / bio'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (saved == true && context.mounted) {
      await context.read<ProfileProvider>().update(
            displayName: name.text.trim().isEmpty ? 'Pengguna Swara' : name.text.trim(),
            bio: bio.text.trim(),
            email: email.text.trim(),
          );
    }
  }

  Future<void> _appSettings(BuildContext context) async {
    final cloud = context.read<CloudService>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pengaturan Aplikasi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SettingRow(label: 'Versi', value: '1.0.0'),
            const _SettingRow(label: 'Sumber data', value: 'Deezer + YouTube'),
            const Divider(height: 12, color: Colors.white10),
            Text(
              cloud.enabled
                  ? 'Sinkronisasi cloud: Supabase aktif'
                  : 'Mode lokal (tanpa login). Aktifkan Supabase dengan menyediakan SUPABASE_URL & SUPABASE_ANON_KEY saat build.',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Keluar?'),
        content: const Text(
            'Swara berjalan tanpa login (mode lokal). Data di perangkat tidak dihapus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Keluar', style: TextStyle(color: Color(0xFFE2334B))),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Berhasil keluar.')),
      );
    }
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final String value;

  const _SettingRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13, color: Colors.white.withValues(alpha: 0.6))),
          Text(value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: kSwaraGold)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11, color: Colors.white.withValues(alpha: 0.55))),
          ],
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? titleColor;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.iconColor,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? Colors.white.withValues(alpha: 0.85)),
      title: Text(title,
          style: TextStyle(fontSize: 15, color: titleColor ?? Colors.white)),
      trailing: Icon(Icons.chevron_right,
          size: 20, color: Colors.white.withValues(alpha: 0.4)),
      onTap: onTap,
    );
  }
}

class _Avatar extends StatelessWidget {
  final ProfileProvider profile;

  const _Avatar({required this.profile});

  IconData _icon(String? key) =>
      _avatars[key] ?? _avatars['person']!;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [kSwaraGold, Color(0xFF8A6A1F)],
            ),
          ),
          child: Icon(
            _icon(profile.profileOrPlaceholder.avatarKey),
            size: 46,
            color: Colors.black,
          ),
        ),
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: kSwaraSurfaceHigh,
            shape: BoxShape.circle,
            border: Border.all(color: kSwaraBg, width: 2),
          ),
          child: IconButton(
            tooltip: 'Pilih avatar',
            padding: EdgeInsets.zero,
            iconSize: 16,
            icon: const Icon(Icons.camera_alt_outlined),
            onPressed: () => _pickAvatar(context),
          ),
        ),
      ],
    );
  }

  Future<void> _pickAvatar(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Pilih avatar',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final e in _avatars.entries)
                    InkWell(
                      borderRadius: BorderRadius.circular(40),
                      onTap: () => Navigator.pop(sheetContext, e.key),
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              kSwaraGold.withValues(alpha: 0.35),
                              Colors.white.withValues(alpha: 0.08),
                            ],
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(color: kSwaraGold, width: 1.2),
                        ),
                        child: Icon(e.value, color: kSwaraGold, size: 28),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && context.mounted) {
      await context.read<ProfileProvider>().update(avatarKey: selected);
    }
  }
}