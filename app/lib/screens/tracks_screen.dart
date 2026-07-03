import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../models/models.dart';
import '../player/player_service.dart';
import '../widgets/track_tile.dart';
import '../widgets/track_cover.dart';

// Flat "list view" of all songs with a search box.
class TracksScreen extends StatefulWidget {
  const TracksScreen({super.key});

  @override
  State<TracksScreen> createState() => _TracksScreenState();
}

class _TracksScreenState extends State<TracksScreen> {
  final _search = TextEditingController();
  late Future<List<Track>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<ApiClient>().searchTracks('');
  }

  void _runSearch(String q) {
    setState(() => _future = context.read<ApiClient>().searchTracks(q));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Search songs / artists',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _search.clear();
                        _runSearch('');
                      },
                    ),
            ),
            onChanged: (v) => _runSearch(v),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Track>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final tracks = snap.data ?? [];
              if (tracks.isEmpty) {
                return const Center(child: Text('No songs found.'));
              }
              return ListView.builder(
                itemCount: tracks.length,
                itemBuilder: (context, i) {
                  final t = tracks[i];
                  return TrackTile(
                    track: t,
                    leading: TrackCover(coverArtId: t.coverArtId),
                    onTap: () => context
                        .read<PlayerService>()
                        .playQueue(tracks, startIndex: i),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
