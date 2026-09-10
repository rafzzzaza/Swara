import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/download_provider.dart';
import '../widgets/song_tile.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DownloadProvider>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<DownloadProvider>();
    final songs = downloads.songs;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Text('Download',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (songs.isNotEmpty)
                  IconButton(
                    tooltip: 'Hapus semua',
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: () => downloads.removeAll(),
                  ),
              ],
            ),
          ),
          Expanded(
            child: songs.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.offline_bolt_outlined,
                              size: 56, color: Colors.white38),
                          SizedBox(height: 12),
                          Text(
                            'Belum ada lagu di-download.\nGunakan menu titik tiga di lagu mana pun untuk download.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: songs.length,
                    itemBuilder: (context, index) {
                      final song = songs[index];
                      return SongTile(
                        song: song,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () async {
                            final record = await downloads
                                .getRecord(song.id);
                            if (record != null) {
                              await downloads.removeDownload(record);
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}