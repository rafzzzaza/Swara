import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/player_provider.dart';
import '../providers/search_provider.dart';
import '../widgets/song_tile.dart';

class SearchScreen extends StatefulWidget {
  final bool standalone;

  const SearchScreen({super.key, this.standalone = false});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    final search = context.read<SearchProvider>();
    if (search.suggestions.isEmpty) {
      search.loadSuggestions();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<SearchProvider>();
    final player = context.read<PlayerProvider>();
    final showResults = search.query.trim().isNotEmpty;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Text('Cari',
                    style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800)),
                const Spacer(),
                if (widget.standalone)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, widget.standalone ? 0 : 4, 16, 4),
            child: TextField(
              controller: _controller,
              autofocus: widget.standalone,
              onChanged: search.onQueryChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: search.searchNow,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Apa yang mau kamu dengar?',
                hintStyle: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.5)),
                prefixIcon: const Icon(Icons.search, size: 22),
                suffixIcon: search.query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () {
                          _controller.clear();
                          search.clear();
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF232323),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildBody(search, player, showResults)),
        ],
      ),
    );
  }

  Widget _buildBody(
      SearchProvider search, PlayerProvider player, bool showResults) {
    if (showResults) {
      if (search.searching) {
        return const Center(child: CircularProgressIndicator());
      }
      if (search.results.isEmpty) {
        return const Center(child: Text('Tidak ada hasil.'));
      }
      return ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 16),
        itemCount: search.results.length,
        itemBuilder: (context, index) =>
            SongTile(song: search.results[index]),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Text('Jelajahi semua',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.55,
            children: [
              for (final s in search.suggestions)
                _CategoryCard(
                  query: s,
                  onTap: () {
                    _controller.text = s;
                    search.searchNow(s);
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String query;
  final VoidCallback onTap;

  const _CategoryCard({required this.query, required this.onTap});

  static const _colors = [
    [Color(0xFFE5A93C), Color(0xFF6B4D12)],
    [Color(0xFF8D67E5), Color(0xFF3B2897)],
    [Color(0xFFE91429), Color(0xFF79101A)],
    [Color(0xFF1182CE), Color(0xFF0B4E77)],
    [Color(0xFF06C1AC), Color(0xFF047062)],
    [Color(0xFFD93F63), Color(0xFF7C1F36)],
    [Color(0xFFF59B23), Color(0xFF8A5716)],
    [Color(0xFF2D46B9), Color(0xFF1A2A70)],
  ];

  @override
  Widget build(BuildContext context) {
    final index =
        query.hashCode.abs() % _colors.length;
    final colors = _colors[index];
    return Material(
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                query,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ),
    );
  }
}