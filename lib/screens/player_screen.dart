import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../widgets/queue_sheet.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  double _volume = 1.0;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final song = player.currentSong;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _DynamicBackground(song: song),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down, size: 30),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text('Sekarang Diputar',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Antrian',
                        icon: const Icon(Icons.queue_music),
                        onPressed: () => showQueueSheet(context),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size =
                          math.min(constraints.maxHeight, constraints.maxWidth - 48);
                      return Center(
                        child: _Artwork(song: song, size: size),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: Column(
                      key: ValueKey(song?.id ?? 'none'),
                      children: [
                        Text(
                          song?.title ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 21, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          song?.album?.isNotEmpty == true
                              ? '${song?.artist ?? ''} • ${song?.album ?? ''}'
                              : song?.artist ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 15,
                              color: Colors.white.withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: _SeekBar(player: player),
                ),
                const SizedBox(height: 4),
                _ControlsRow(player: player),
                _VolumeRow(player: player, volume: _volume,
                    onChanged: (v) {
                      setState(() => _volume = v);
                      player.setVolume(v);
                    }),
                _ChipsRow(player: player),
                const SizedBox(height: 8),
                _NowPlayingPanel(player: player),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DynamicBackground extends StatelessWidget {
  final Song? song;

  const _DynamicBackground({required this.song});

  Future<PaletteGenerator> _palette(String url) {
    return PaletteGenerator.fromImageProvider(
      NetworkImage(url),
      maximumColorCount: 12,
      size: const Size(120, 120),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = song?.artUrl ?? song?.thumbnailUrl;
    if (url == null) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF241A08), kSwaraBg],
          ),
        ),
      );
    }

    return FutureBuilder<PaletteGenerator>(
      future: _palette(url),
      builder: (context, snap) {
        final palette = snap.data;
        Color top = const Color(0xFF241A08);
        Color bottom = kSwaraBg;
        if (palette != null) {
          top = palette.dominantColor?.color ?? top;
          final muted = palette.darkMutedColor?.color;
          if (muted != null) bottom = muted;
          top = Color.lerp(top, Colors.black, 0.25)!;
          bottom = Color.lerp(bottom, Colors.black, 0.55)!;
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [top, bottom],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.25),
                    Colors.black.withValues(alpha: 0.72),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Artwork extends StatelessWidget {
  final Song? song;
  final double size;

  const _Artwork({required this.song, required this.size});

  @override
  Widget build(BuildContext context) {
    final url = song?.artUrl ?? song?.thumbnailUrl;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black, blurRadius: 48, spreadRadius: 6),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: url != null
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(
                    color: Colors.white10,
                    child: const Icon(Icons.music_note, size: 70)),
                errorWidget: (_, _, _) => Container(
                    color: Colors.white10,
                    child: const Icon(Icons.music_note, size: 70)),
              )
            : Container(
                color: Colors.white10,
                child: const Icon(Icons.music_note, size: 70),
              ),
      ),
    );
  }
}

class _SeekBar extends StatelessWidget {
  final PlayerProvider player;

  const _SeekBar({required this.player});

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    if (h > 0) return '$h:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration?>(
      stream: player.durationStream,
      builder: (context, snapshot) {
        final duration = snapshot.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (context, posSnap) {
            final position = posSnap.data ?? Duration.zero;
            final maxMs = duration.inMilliseconds.clamp(1, 1 << 31).toDouble();
            final value =
                position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Slider(
                  value: value,
                  max: maxMs,
                  onChanged: (v) =>
                      player.seek(Duration(milliseconds: v.round())),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(position),
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.8))),
                      Text(_fmt(duration),
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.6))),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ControlsRow extends StatelessWidget {
  final PlayerProvider player;

  const _ControlsRow({required this.player});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: player.playingStream,
      initialData: player.isPlaying,
      builder: (context, playingSnap) {
        final playing = playingSnap.data ?? false;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Sebelumnya',
              onPressed: player.previous,
              icon: const Icon(Icons.skip_previous, size: 38),
              color: Colors.white,
            ),
            const SizedBox(width: 38),
            StreamBuilder<ProcessingState>(
              stream: player.processingStateStream,
              initialData: ProcessingState.idle,
              builder: (context, stateSnap) {
                final buffering =
                    stateSnap.data == ProcessingState.loading ||
                        stateSnap.data == ProcessingState.buffering;
                return SizedBox(
                  width: 88,
                  height: 88,
                  child: IconButton(
                    onPressed: player.togglePlayPause,
                    iconSize: 88,
                    padding: EdgeInsets.zero,
                    icon: buffering
                        ? const SizedBox(
                            width: 40,
                            height: 40,
                            child: CircularProgressIndicator(
                                strokeWidth: 3, color: Colors.white),
                          )
                        : Icon(
                            playing
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                            color: Colors.white,
                          ),
                  ),
                );
              },
            ),
            const SizedBox(width: 38),
            IconButton(
              tooltip: 'Berikutnya',
              onPressed: player.next,
              icon: const Icon(Icons.skip_next, size: 38),
              color: Colors.white,
            ),
          ],
        );
      },
    );
  }
}

class _VolumeRow extends StatelessWidget {
  final PlayerProvider player;
  final double volume;
  final ValueChanged<double> onChanged;

  const _VolumeRow(
      {required this.player,
      required this.volume,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.volume_down,
              size: 18, color: Colors.white.withValues(alpha: 0.7)),
          Expanded(
            child: Slider(
              value: volume,
              onChanged: onChanged,
              inactiveColor: Colors.white.withValues(alpha: 0.25),
              activeColor: Colors.white,
              thumbColor: Colors.white,
            ),
          ),
          Icon(Icons.volume_up,
              size: 18, color: Colors.white.withValues(alpha: 0.7)),
        ],
      ),
    );
  }
}

class _ChipsRow extends StatelessWidget {
  final PlayerProvider player;

  const _ChipsRow({required this.player});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(
            icon: Icons.queue_music,
            label: 'Antrian',
            onTap: () => showQueueSheet(context),
          ),
          _ActionButton(
            icon: Icons.skip_next,
            label: 'Berikutnya',
            onTap: player.next,
          ),
          _ToggleButton(
            icon: Icons.auto_awesome,
            label: 'Otomatis',
            active: player.autoQueueEnabled,
            onTap: () =>
                player.setAutoQueue(!player.autoQueueEnabled),
          ),
          _ToggleButton(
            icon: player.loopMode != LoopMode.off
                ? Icons.repeat
                : Icons.repeat,
            label: _loopLabel(player.loopMode),
            active: player.loopMode != LoopMode.off,
            onTap: player.cycleLoopMode,
          ),
          _ToggleButton(
            icon: Icons.shuffle,
            label: 'Shuffle',
            active: player.shuffleModeEnabled,
            onTap: player.toggleShuffle,
          ),
        ],
      ),
    );
  }

  String _loopLabel(LoopMode mode) {
    switch (mode) {
      case LoopMode.off:
        return 'Ulangi';
      case LoopMode.all:
        return 'Ulangi semua';
      case LoopMode.one:
        return 'Ulangi 1';
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = Colors.white;
    final iconColor = Colors.white.withValues(alpha: 0.85);
    return Material(
      color: fg.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: iconColor),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ToggleButton(
      {required this.icon,
      required this.label,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = active ? kSwaraGold : Colors.white;
    final fg = active ? Colors.black : Colors.white;
    final iconColor = active ? Colors.black : Colors.white.withValues(alpha: 0.85);
    return Material(
      color: bg.withValues(alpha: active ? 1 : 0.13),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: iconColor),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NowPlayingPanel extends StatefulWidget {
  final PlayerProvider player;

  const _NowPlayingPanel({required this.player});

  @override
  State<_NowPlayingPanel> createState() => _NowPlayingPanelState();
}

class _NowPlayingPanelState extends State<_NowPlayingPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 28),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            kSwaraGold.withValues(alpha: 0.18),
            Colors.white.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kSwaraGold.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => _PulseBars(value: _controller.value),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: StreamBuilder<Duration?>(
              stream: widget.player.durationStream,
              builder: (context, snap) {
                final full = (snap.data ?? Duration.zero).inSeconds >= 60;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Row(
                        key: ValueKey(full),
                        children: [
                          Icon(
                            full ? Icons.play_circle_outline : Icons.graphic_eq,
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              full
                                  ? 'Full audio · Aliran YouTube'
                                  : 'Preview 30 detik · Deezer',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withValues(alpha: 0.75)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      full
                          ? 'Memutar versi lengkap lagu tanpa potongan.'
                          : 'Full audio tidak ditemukan, memutar cuplikan.',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.white.withValues(alpha: 0.45)),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseBars extends StatelessWidget {
  final double value;

  const _PulseBars({required this.value});

  @override
  Widget build(BuildContext context) {
    const phases = [0.0, 1.2, 0.5, 1.9, 0.9];
    return SizedBox(
      width: 26,
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final phase in phases)
            Container(
              width: 3,
              height: 8 + (math.sin((value * math.pi + phase)).abs() * 14),
              decoration: BoxDecoration(
                color: kSwaraGold.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}