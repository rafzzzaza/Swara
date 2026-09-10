import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';

Future<void> showQueueSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: kSwaraSurface,
    showDragHandle: true,
    builder: (_) => const QueueSheet(),
  );
}

class QueueSheet extends StatelessWidget {
  const QueueSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final upcoming = player.upcoming;
    final recommendations = player.recommendations;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  const Text('Antrian',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Muat ulang rekomendasi',
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: () => player.loadRecommendations(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Tambahkan otomatis',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    'Swara menambahkan lagu rekomendasi ke antrian',
                    style: TextStyle(fontSize: 11)),
                value: player.autoQueueEnabled,
                onChanged: (v) => player.setAutoQueue(v),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 6),
              child: Text('Lagu berikutnya',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white54)),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  if (upcoming.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Text(
                        'Tidak ada lagu berikutnya. Aktifkan tambah otomatis agar antrian terus terisi.',
                        style: TextStyle(fontSize: 12, color: Colors.white54),
                      ),
                    )
                  else
                    for (var i = 0; i < upcoming.length; i++)
                      _UpcomingTile(
                        song: upcoming[i],
                        index: (player.currentIndex ?? 0) + 1 + i,
                        onTap: () => player.skipTo(
                            (player.currentIndex ?? 0) + 1 + i),
                      ),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 6),
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome,
                            size: 16, color: kSwaraGold),
                        SizedBox(width: 8),
                        Text('Rekomendasi untukmu',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: kSwaraGold)),
                      ],
                    ),
                  ),
                  if (player.recommendationsLoading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                          child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2))),
                    )
                  else if (recommendations.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      child: Text(
                        'Nyalakan playback untuk melihat rekomendasi.',
                        style:
                            TextStyle(fontSize: 12, color: Colors.white54),
                      ),
                    )
                  else
                    for (final song in recommendations)
                      _RecommendationTile(song: song),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Art extends StatelessWidget {
  final Song song;
  final double size;

  const _Art({required this.song, required this.size});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: size,
        height: size,
        child: song.thumbnailUrl != null
            ? CachedNetworkImage(
                imageUrl: song.thumbnailUrl!,
                fit: BoxFit.cover,
                placeholder: (_, _) => const ColoredBox(color: Colors.black26),
                errorWidget: (_, _, _) =>
                    const ColoredBox(color: Colors.black26),
              )
            : const ColoredBox(
                color: Colors.black26, child: Icon(Icons.music_note)),
      ),
    );
  }
}

class _UpcomingTile extends StatelessWidget {
  final Song song;
  final int index;
  final VoidCallback onTap;

  const _UpcomingTile(
      {required this.song, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 22,
        child: Text('$index',
            style: TextStyle(
                fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
      ),
      title: Text(song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 12, color: Colors.white.withValues(alpha: 0.6))),
      onTap: onTap,
    );
  }
}

class _RecommendationTile extends StatelessWidget {
  final Song song;

  const _RecommendationTile({required this.song});

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerProvider>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          _Art(song: song, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                Text(song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.6))),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Putar berikutnya',
            iconSize: 20,
            icon: const Icon(Icons.playlist_add),
            onPressed: () => player.insertNext(song),
          ),
          IconButton(
            tooltip: 'Tambah ke antrian',
            iconSize: 20,
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => player.addToQueue(song),
          ),
        ],
      ),
    );
  }
}