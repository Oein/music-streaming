import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../models/models.dart';
import '../player/player_service.dart';
import '../widgets/track_tile.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_cover.dart';
import 'album_detail_screen.dart';

// Global search over albums and songs.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  String _query = '';
  List<Album> _albums = [];
  List<Track> _tracks = [];
  bool _loading = false;

  Future<void> _run(String q) async {
    setState(() {
      _query = q;
      _loading = q.trim().isNotEmpty;
    });
    if (q.trim().isEmpty) {
      setState(() {
        _albums = [];
        _tracks = [];
      });
      return;
    }
    final api = context.read<ApiClient>();
    final lower = q.toLowerCase();
    final results = await Future.wait([
      api.albums(),
      api.searchTracks(q),
    ]);
    if (!mounted || q != _query) return;
    setState(() {
      _albums = (results[0] as List<Album>)
          .where((a) =>
              a.name.toLowerCase().contains(lower) ||
              (a.albumArtist ?? '').toLowerCase().contains(lower))
          .toList();
      _tracks = results[1] as List<Track>;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search albums & songs',
            border: InputBorder.none,
          ),
          onChanged: _run,
        ),
        actions: [
          if (_ctrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _ctrl.clear();
                _run('');
              },
            ),
        ],
      ),
      body: Column(children: [
        Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: [
                      if (_albums.isNotEmpty) ...[
                        _sectionHeader('Albums', _albums.length, () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => _AllAlbumsScreen(
                                    query: _query, albums: _albums)),
                          );
                        }),
                        for (final a in _albums.take(_previewCount))
                          albumTile(context, a),
                      ],
                      if (_tracks.isNotEmpty) ...[
                        _sectionHeader('Songs', _tracks.length, () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => _AllTracksScreen(
                                    query: _query, tracks: _tracks)),
                          );
                        }),
                        for (var i = 0;
                            i < _tracks.length && i < _previewCount;
                            i++)
                          TrackTile(
                            track: _tracks[i],
                            leading:
                                TrackCover(coverArtId: _tracks[i].coverArtId),
                            onTap: () => context
                                .read<PlayerService>()
                                .playQueue(_tracks, startIndex: i),
                          ),
                      ],
                      if (_query.trim().isNotEmpty &&
                          _albums.isEmpty &&
                          _tracks.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('No results.')),
                        ),
                    ],
                  )),
        const MiniPlayer(),
      ]),
    );
  }

  // Section header with a "See more" action when there are more than the
  // preview count of results.
  Widget _sectionHeader(String title, int total, VoidCallback onSeeMore) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$title ($total)',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          if (total > _previewCount)
            TextButton(onPressed: onSeeMore, child: const Text('See more')),
        ],
      ),
    );
  }
}

const _previewCount = 5;

// Shared album tile used by search and the "see all albums" screen.
Widget albumTile(BuildContext context, Album a) {
  final api = context.read<ApiClient>();
  return ListTile(
    leading: ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 44,
        height: 44,
        child: a.coverArtId != null
            ? CachedNetworkImage(
                imageUrl: api.coverUrl(a.coverArtId, size: 128),
                fit: BoxFit.cover)
            : Container(color: Colors.white10, child: const Icon(Icons.album)),
      ),
    ),
    title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle:
        Text(a.albumArtist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: a)),
    ),
  );
}

// Full list of matching albums.
class _AllAlbumsScreen extends StatelessWidget {
  final String query;
  final List<Album> albums;
  const _AllAlbumsScreen({required this.query, required this.albums});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Albums · "$query"')),
      body: ListView.builder(
        itemCount: albums.length,
        itemBuilder: (context, i) => albumTile(context, albums[i]),
      ),
    );
  }
}

// Full list of matching songs.
class _AllTracksScreen extends StatelessWidget {
  final String query;
  final List<Track> tracks;
  const _AllTracksScreen({required this.query, required this.tracks});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Songs · "$query"')),
      body: ListView.builder(
        itemCount: tracks.length,
        itemBuilder: (context, i) => TrackTile(
          track: tracks[i],
          leading: TrackCover(coverArtId: tracks[i].coverArtId),
          onTap: () =>
              context.read<PlayerService>().playQueue(tracks, startIndex: i),
        ),
      ),
    );
  }
}
