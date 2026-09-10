import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../providers/player_provider.dart';
import '../providers/playlist_provider.dart';
import '../widgets/song_tile.dart';

class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlaylistProvider>().refresh();
    });
  }

  Future<void> _createPlaylist() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Playlist baru'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nama playlist'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Buat'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      if (!mounted) return;
      await context.read<PlaylistProvider>().createPlaylist(name.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlaylistProvider>();
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Text('Playlist',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: _createPlaylist,
                  icon: const Icon(Icons.add),
                  label: const Text('Buat'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: provider.playlists.isEmpty
                ? const Center(child: Text('Belum ada playlist. Klik "Buat"'))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: provider.playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = provider.playlists[index];
                      return _PlaylistTile(playlist: playlist);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  final Playlist playlist;

  const _PlaylistTile({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final playlists = context.read<PlaylistProvider>();
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .primary
              .withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.queue_music,
            color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(playlist.name,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${playlist.songCount} lagu'),
      onTap: () {
        playlists.openPlaylist(playlist);
        Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => PlaylistDetailScreen(playlist: playlist)),
        );
      },
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'rename') {
            final controller = TextEditingController(text: playlist.name);
            final name = await showDialog<String>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Ubah nama'),
                content: TextField(
                    controller: controller, autofocus: true),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Batal'),
                  ),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(dialogContext, controller.text),
                    child: const Text('Simpan'),
                  ),
                ],
              ),
            );
            if (name != null && name.trim().isNotEmpty) {
              await playlists.renamePlaylist(playlist.id!, name.trim());
            }
          } else if (value == 'delete') {
            final ok = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Hapus playlist?'),
                content: Text('"${playlist.name}" akan dihapus.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Batal'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Hapus'),
                  ),
                ],
              ),
            );
            if (ok == true) {
              await playlists.deletePlaylist(playlist.id!);
            }
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: Text('Ubah nama')),
          PopupMenuItem(value: 'delete', child: Text('Hapus')),
        ],
      ),
    );
  }
}

class PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final playlists = context.watch<PlaylistProvider>();
    final player = context.read<PlayerProvider>();
    final songs = playlists.currentSongs;
    return Scaffold(
      appBar: AppBar(title: Text(widget.playlist.name)),
      body: songs.isEmpty
          ? const Center(child: Text('Playlist kosong'))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: songs.length,
              itemBuilder: (context, index) {
                final song = songs[index];
                final isCurrent =
                    player.currentSong?.id == song.id && player.hasAny;
                return SongTile(
                  song: song,
                  leading: SizedBox(
                    width: 32,
                    child: Center(
                      child: isCurrent
                          ? Icon(Icons.graphic_eq,
                              color: Theme.of(context).colorScheme.primary,
                              size: 18)
                          : Text('${index + 1}',
                              style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    onPressed: () =>
                        playlists.removeSong(song.id),
                  ),
                );
              },
            ),
      bottomNavigationBar: songs.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () => player.playQueue(songs),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Putar semua'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ),
    );
  }
}