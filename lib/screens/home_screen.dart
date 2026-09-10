import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/album.dart';
import '../models/artist.dart';
import '../models/genre.dart';
import '../models/song.dart';
import '../providers/home_provider.dart';
import '../providers/player_provider.dart';
import '../providers/profile_provider.dart';
import '../widgets/mini_player.dart';
import '../widgets/shimmer.dart';
import 'downloads_screen.dart';
import 'player_screen.dart';
import 'playlist_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

const _avatarIcons = <String, IconData>{
  'person': Icons.person,
  'headphones': Icons.headphones,
  'mic': Icons.mic,
  'piano': Icons.piano,
  'album': Icons.album,
  'star': Icons.star,
  'bolt': Icons.bolt,
  'waves': Icons.waves,
};

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  late final List<Widget> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = const [
      HomeFeed(),
      SearchScreen(),
      PlaylistScreen(),
      DownloadsScreen(),
    ];
  }

  void _openPlayer() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Baca inset keyboard dari atas Scaffold (Scaffold menghapusnya untuk
    // bottomNavigationBar), lalu dorong mini player + nav naik lewat keyboard
    // supaya tidak tertutup saat mengetik di Cari.
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      body: IndexedStack(index: _tab, children: _tabs),
      bottomNavigationBar: AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MiniPlayer(onOpen: _openPlayer),
          Container(
            decoration: const BoxDecoration(
              color: kSwaraSurface,
              border: Border(
                top: BorderSide(color: Colors.white10, width: 0.5),
              ),
            ),
            child: NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) {
                setState(() => _tab = i);
                if (i == 0) {
                  context.read<HomeProvider>().refreshPersonalized();
                }
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Beranda',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search_outlined),
                  selectedIcon: Icon(Icons.search),
                  label: 'Cari',
                ),
                NavigationDestination(
                  icon: Icon(Icons.queue_music_outlined),
                  selectedIcon: Icon(Icons.queue_music),
                  label: 'Playlist',
                ),
                NavigationDestination(
                  icon: Icon(Icons.download_outlined),
                  selectedIcon: Icon(Icons.download),
                  label: 'Offline',
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}

String _greeting() {
  final h = DateTime.now().hour;
  if (h < 11) return 'Selamat pagi';
  if (h < 15) return 'Selamat siang';
  if (h < 19) return 'Selamat sore';
  return 'Selamat malam';
}

class HomeFeed extends StatefulWidget {
  const HomeFeed({super.key});

  @override
  State<HomeFeed> createState() => _HomeFeedState();
}

class _HomeFeedState extends State<HomeFeed> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_started) {
        _started = true;
        context.read<HomeProvider>().load();
      }
    });
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SearchScreen(standalone: true)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeProvider>();

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: home.load,
        color: Theme.of(context).colorScheme.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(greeting: _greeting(), onSearch: _openSearch),
                ],
              ),
            ),
            if (home.loading)
              const SliverToBoxAdapter(child: _HomeSkeleton())
            else if (home.error || home.trending.isEmpty)
              SliverToBoxAdapter(
                child: _ErrorState(onRetry: home.load),
              )
            else
              SliverToBoxAdapter(
                child: _HomeContent(
                  home: home,
                  onGenre: (g) => home.selectGenre(g),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String greeting;
  final VoidCallback onSearch;

  const _Header({required this.greeting, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileProvider>();
    final avatarKey = profile.profileOrPlaceholder.avatarKey;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [kSwaraGold, Color(0xFF8A6A1F)],
                ),
              ),
              child: Icon(
                _avatarIcons[avatarKey] ?? _avatarIcons['person'],
                color: Colors.black,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800),
                ),
                Text(
                  'Musik yang pas untuk harimu',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Notifikasi',
            onPressed: () {},
            icon: const Icon(Icons.notifications_none),
          ),
          IconButton(
            tooltip: 'Cari',
            onPressed: onSearch,
            icon: const Icon(Icons.search),
          ),
        ],
      ),
    );
  }
}

class _GenrePills extends StatelessWidget {
  final List<Genre> genres;
  final Genre? active;
  final ValueChanged<Genre> onTap;

  const _GenrePills({
    required this.genres,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: genres.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final genre = genres[index];
          final selected = active?.id == genre.id;
          return Material(
            color: selected
                ? kSwaraGold
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(19),
            child: InkWell(
              borderRadius: BorderRadius.circular(19),
              onTap: () => onTap(genre),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                child: Text(
                  genre.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  final HomeProvider home;
  final ValueChanged<Genre> onGenre;

  const _HomeContent({required this.home, required this.onGenre});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _GenrePills(
          genres: home.genres,
          active: home.activeGenre,
          onTap: onGenre,
        ),
        const SizedBox(height: 20),
        _QuickGrid(songList: home.personalized.take(8).toList()),
        const SizedBox(height: 22),
        if (home.personalized.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _CarouselTitle('Rekomendasi Untukmu'),
          ),
          const SizedBox(height: 4),
          _TrackCarousel(songs: home.personalized),
          const SizedBox(height: 22),
        ],
        if (home.bySearches.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _CarouselTitle('Berdasarkan Musik yang Sering Kamu Cari'),
          ),
          const SizedBox(height: 4),
          _TrackCarousel(songs: home.bySearches),
          const SizedBox(height: 22),
        ],
        _CarouselHeader(
          title: 'Top Charts • Trending Saat Ini',
          onSeeAll: () => _openPlaylist(context, home.trending),
        ),
        _TrackCarousel(songs: home.trending),
        if (home.indonesia.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _CarouselTitle('Top Hits Indonesia'),
          ),
          const SizedBox(height: 4),
          _TrackCarousel(songs: home.indonesia),
        ],
        if (home.global.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _CarouselTitle('Top Global Hits'),
          ),
          const SizedBox(height: 4),
          _TrackCarousel(songs: home.global),
        ],
        const SizedBox(height: 22),
        Row(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: _CarouselTitle(home.moodSectionTitle),
            ),
            if (home.moodLoading)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        _TrackCarousel(songs: home.recommendations),
        const SizedBox(height: 22),
        _CarouselHeader(
          title: 'Rilis Terbaru',
          onSeeAll: () {},
        ),
        _AlbumCarousel(albums: home.newReleases),
        const SizedBox(height: 22),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Artis Populer',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 4),
        _ArtistCarousel(artists: home.artists),
      ],
    );
  }

  void _openPlaylist(BuildContext context, List<Song> songs) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TrackListScreen(title: 'Trending Saat Ini', songs: songs),
      ),
    );
  }
}

class _CarouselHeader extends StatelessWidget {
  final String title;
  final VoidCallback onSeeAll;

  const _CarouselHeader({required this.title, required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          GestureDetector(
            onTap: onSeeAll,
            child: Text(
              'Lihat semua',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CarouselTitle extends StatelessWidget {
  final String title;
  const _CarouselTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800));
  }
}

class _QuickGrid extends StatelessWidget {
  final List<Song> songList;

  const _QuickGrid({required this.songList});

  @override
  Widget build(BuildContext context) {
    if (songList.isEmpty) return const SizedBox.shrink();
    final player = context.read<PlayerProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Sering Diputar',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.35,
          ),
          itemCount: songList.length,
          itemBuilder: (context, index) {
            final song = songList[index];
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => player.playQueue(songList, index: index),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: song.artUrl ?? song.thumbnailUrl ?? '',
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          const ColoredBox(color: Color(0xFF242424)),
                      errorWidget: (_, _, _) =>
                          const ColoredBox(color: Color(0xFF242424)),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _TrackCarousel extends StatelessWidget {
  final List<Song> songs;

  const _TrackCarousel({required this.songs});

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 188,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: songs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          return _TrackCard(song: songs[index], songs: songs);
        },
      ),
    );
  }
}

class _TrackCard extends StatelessWidget {
  final Song song;
  final List<Song> songs;

  const _TrackCard({required this.song, required this.songs});

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerProvider>();
    return SizedBox(
      width: 138,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => player.playQueue(songs, index: songs.indexOf(song)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AspectRatio(
                    aspectRatio: 1,
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
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: kSwaraGold,
                      shape: BoxShape.circle,
                      boxShadow: const [
                        BoxShadow(color: Colors.black45, blurRadius: 6),
                      ],
                    ),
                    child: const Icon(Icons.play_arrow,
                        color: Colors.black, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              song.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11, color: Colors.white.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumCarousel extends StatelessWidget {
  final List<Album> albums;

  const _AlbumCarousel({required this.albums});

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) return const SizedBox.shrink();
    final player = context.read<PlayerProvider>();
    return SizedBox(
      height: 190,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: albums.length,
        itemBuilder: (context, index) {
          final album = albums[index];
          final home = context.read<HomeProvider>();
          return Padding(
            padding: const EdgeInsets.only(right: 14),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                final songs = await home.albumSongs(album);
                if (!context.mounted) return;
                if (songs.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Tidak ada lagu dari album ini')));
                  return;
                }
                player.playQueue(songs, index: 0);
              },
              child: SizedBox(
                width: 138,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: CachedNetworkImage(
                          imageUrl:
                              album.pictureUrl ?? album.pictureMedium ?? '',
                          fit: BoxFit.cover,
                          placeholder: (_, _) =>
                              const ColoredBox(color: Color(0xFF242424)),
                          errorWidget: (_, _, _) =>
                              const ColoredBox(color: Color(0xFF242424)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      album.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      album.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ArtistCarousel extends StatelessWidget {
  final List<Artist> artists;

  const _ArtistCarousel({required this.artists});

  @override
  Widget build(BuildContext context) {
    if (artists.isEmpty) return const SizedBox.shrink();
    final player = context.read<PlayerProvider>();
    return SizedBox(
      height: 132,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: artists.length,
        itemBuilder: (context, index) {
          final artist = artists[index];
          final home = context.read<HomeProvider>();
          return Padding(
            padding: const EdgeInsets.only(right: 16),
            child: InkWell(
              borderRadius: BorderRadius.circular(52),
              onTap: () async {
                final songs = await home.artistSongs(artist);
                if (!context.mounted) return;
                if (songs.isEmpty) return;
                player.playQueue(songs, index: 0);
              },
              child: Column(
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 90,
                      height: 90,
                      child: CachedNetworkImage(
                        imageUrl: artist.pictureUrl ?? '',
                        fit: BoxFit.cover,
                        placeholder: (_, _) =>
                            const ColoredBox(color: Color(0xFF242424)),
                        errorWidget: (_, _, _) => const ColoredBox(
                            color: Color(0xFF242424),
                            child: Icon(Icons.person, color: Colors.white38)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 96,
                    child: Text(
                      artist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                const ShimmerBox(width: 84, height: 36, radius: 18),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: ShimmerBox(width: 150, height: 20),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 2; i++) ...[
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.42,
                  child: ShimmerBox(height: 120, radius: 10),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: ShimmerBox(width: 200, height: 20),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 5,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, _) => const ShimmerBox(width: 138, height: 138),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          const Icon(Icons.cloud_off, size: 48, color: kSwaraGold),
          const SizedBox(height: 12),
          const Text('Gagal memuat musik. Periksa koneksi internetmu.'),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ],
      ),
    );
  }
}

class _TrackListScreen extends StatelessWidget {
  final String title;
  final List<Song> songs;

  const _TrackListScreen({required this.title, required this.songs});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];
          return ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 44,
                height: 44,
                child: CachedNetworkImage(
                  imageUrl: song.artUrl ?? song.thumbnailUrl ?? '',
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) =>
                      const ColoredBox(color: Color(0xFF242424)),
                ),
              ),
            ),
            title: Text(song.title,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(song.artist,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () =>
                context.read<PlayerProvider>().playQueue(songs, index: index),
          );
        },
      ),
    );
  }
}