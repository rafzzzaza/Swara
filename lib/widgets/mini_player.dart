import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../providers/player_provider.dart';
import 'marquee_text.dart';
import 'queue_sheet.dart';

class MiniPlayer extends StatelessWidget {
  final VoidCallback onOpen;

  const MiniPlayer({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final song = player.currentSong;

    if (song == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      decoration: BoxDecoration(
        color: kSwaraSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kSwaraGold.withValues(alpha: 0.25)),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onOpen,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StreamBuilder<Duration?>(
                  stream: player.durationStream,
                  builder: (context, durSnap) {
                    final duration = durSnap.data ?? Duration.zero;
                    return StreamBuilder<Duration>(
                      stream: player.positionStream,
                      builder: (context, posSnap) {
                        final position = posSnap.data ?? Duration.zero;
                        final progress = duration.inMilliseconds == 0
                            ? 0.0
                            : (position.inMilliseconds /
                                    duration.inMilliseconds)
                                .clamp(0.0, 1.0);
                        return LinearProgressIndicator(
                          value: progress,
                          minHeight: 2,
                          backgroundColor: Colors.white10,
                          color: kSwaraGold,
                        );
                      },
                    );
                  },
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 42,
                          height: 42,
                          child: song.artUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: song.artUrl!,
                                  fit: BoxFit.cover,
                                  placeholder: (_, _) =>
                                      const ColoredBox(color: Colors.black26),
                                  errorWidget: (_, _, _) => CachedNetworkImage(
                                        imageUrl: song.thumbnailUrl ?? '',
                                        fit: BoxFit.cover,
                                        errorWidget: (_, _, _) =>
                                            const ColoredBox(
                                                color: Colors.black26),
                                      ),
                                )
                              : const ColoredBox(color: Colors.black26),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MarqueeText(
                              text: song.title,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Antrian',
                        icon: const Icon(Icons.queue_music, size: 22),
                        onPressed: () => showQueueSheet(context),
                      ),
                      StreamBuilder<bool>(
                        stream: player.playingStream,
                        initialData: player.isPlaying,
                        builder: (context, snapshot) {
                          final playing = snapshot.data ?? false;
                          return IconButton(
                            icon: Icon(
                              playing
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_filled,
                              size: 40,
                              color: kSwaraGold,
                            ),
                            onPressed: () => player.togglePlayPause(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}