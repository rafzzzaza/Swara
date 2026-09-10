import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../providers/history_provider.dart';
import '../providers/player_provider.dart';
import '../utils/time_ago.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HistoryProvider>().refresh();
    });
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus riwayat?'),
        content: const Text('Seluruh riwayat pemutaran akan dihapus dari perangkat ini.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus', style: TextStyle(color: Color(0xFFE2334B))),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<HistoryProvider>().clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<HistoryProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Pemutaran'),
        actions: [
          IconButton(
            tooltip: 'Hapus riwayat',
            onPressed: history.history.isEmpty ? null : _confirmClear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _buildBody(history),
    );
  }

  Widget _buildBody(HistoryProvider history) {
    if (history.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (history.history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 52, color: kSwaraGold.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            const Text('Belum ada riwayat pemutaran.'),
            const SizedBox(height: 4),
            Text(
              'Lagu yang kamu putar akan muncul di sini.',
              style: TextStyle(
                  fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
            ),
          ],
        ),
      );
    }
    final player = context.read<PlayerProvider>();
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: history.history.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final entry = history.history[index];
        final song = entry.song;
        final isCurrent = player.currentSong?.id == song.id && player.hasAny;
        return InkWell(
          onTap: () => player.playSong(song),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: CachedNetworkImage(
                      imageUrl: song.artUrl ?? song.thumbnailUrl ?? '',
                      fit: BoxFit.cover,
placeholder: (_, _) =>
                        const ColoredBox(color: Color(0xFF242424)),
                    errorWidget: (_, _, _) =>
                        const ColoredBox(color: Color(0xFF242424)),
                    ),
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
                          color: isCurrent ? kSwaraGold : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  timeAgo(entry.playedAt),
                  style: TextStyle(
                      fontSize: 11, color: Colors.white.withValues(alpha: 0.45)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}