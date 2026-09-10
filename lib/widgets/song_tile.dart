import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../providers/download_provider.dart';
import '../providers/player_provider.dart';
import '../providers/playlist_provider.dart';
import 'playlist_picker_sheet.dart';

class SongTile extends StatelessWidget {
  final Song song;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? leading;

  const SongTile({
    super.key,
    required this.song,
    this.onTap,
    this.trailing,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final downloads = context.watch<DownloadProvider>();
    final isCurrent =
        player.currentSong?.id == song.id && player.hasAny;
    final downloading = downloads.isDownloading(song.id);

    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap ??
          () {
            player.playSong(song);
          },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 10),
            ],
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 46,
                height: 46,
                child: song.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: song.thumbnailUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => _placeholder(theme),
                        errorWidget: (_, _, _) => _placeholder(theme),
                      )
                    : _placeholder(theme),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? theme.colorScheme.primary : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            if (downloading) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
            const SizedBox(width: 4),
            _trailing(context),
          ],
        ),
      ),
    );
  }

  Widget _trailing(BuildContext context) {
    if (trailing != null) return trailing!;
    return IconButton(
      icon: const Icon(Icons.more_vert, size: 20),
      onPressed: () => _showMenu(context),
      constraints: const BoxConstraints(),
      padding: const EdgeInsets.all(8),
    );
  }

  Widget _placeholder(ThemeData theme) => Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.music_note,
          color: Colors.white.withValues(alpha: 0.4),
        ),
      );

  void _showMenu(BuildContext context) {
    final player = context.read<PlayerProvider>();
    final playlists = context.read<PlaylistProvider>();
    final downloads = context.read<DownloadProvider>();

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(song.artist,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: const Text('Putar sekarang'),
              onTap: () {
                Navigator.pop(sheetContext);
                player.playSong(song);
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Tambahkan ke Playlist'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await playlists.refresh();
                if (!sheetContext.mounted) return;
                showPlaylistPicker(sheetContext, song);
              },
            ),
            if (!downloads.isDownloading(song.id) &&
                !(downloads
                    .downloads
                    .any((d) => d.songId == song.id)))
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Download'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  try {
                    await downloads.startDownload(song);
                    if (!sheetContext.mounted) return;
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      const SnackBar(content: Text('Download selesai')),
                    );
                  } catch (_) {
                    if (!sheetContext.mounted) return;
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      const SnackBar(content: Text('Download gagal')),
                    );
                  }
                },
              ),
            if (downloads.downloads.any((d) => d.songId == song.id))
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('Sudah di download'),
                enabled: false,
              ),
          ],
        ),
      ),
    );
  }
}