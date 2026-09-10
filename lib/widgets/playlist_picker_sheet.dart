import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../providers/playlist_provider.dart';

/// Shows a bottom sheet to pick (or create) a playlist for a song.
Future<void> showPlaylistPicker(BuildContext context, Song song) async {
  final playlists = context.read<PlaylistProvider>();
  final playlistsList = playlists.playlists;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Tambahkan ke playlist',
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text('Buat playlist baru'),
            onTap: () async {
              final nameController = TextEditingController();
              final name = await _promptPlaylistName(sheetContext,
                  controller: nameController);
              if (name != null && name.trim().isNotEmpty) {
                final id = await playlists.createPlaylist(name.trim());
                await playlists.refresh();
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);
                await playlists.addSong(
                    playlists.playlists
                        .firstWhere((p) => p.id == id),
                    song);
                if (!sheetContext.mounted) return;
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(content: Text('Ditambahkan ke "$name"')),
                );
              }
            },
          ),
          const Divider(height: 1),
          Flexible(
            child: playlistsList.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Belum ada playlist'),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: playlistsList.length,
                    itemBuilder: (context, index) {
                      final playlist = playlistsList[index];
                      return ListTile(
                        leading: const Icon(Icons.queue_music),
                        title: Text(playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text('${playlist.songCount} lagu'),
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          await playlists.addSong(playlist, song);
                          if (!sheetContext.mounted) return;
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            SnackBar(
                                content: Text(
                                    'Ditambahkan ke "${playlist.name}"')),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}

Future<String?> _promptPlaylistName(BuildContext context,
    {TextEditingController? controller}) async {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Nama playlist'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'contoh: Lagi Healing'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller!.text),
          child: const Text('Buat'),
        ),
      ],
    ),
  );
}