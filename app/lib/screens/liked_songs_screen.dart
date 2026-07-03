import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../favorites/favorites_service.dart';
import '../models/models.dart';
import '../player/player_service.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_tile.dart';
import '../widgets/track_cover.dart';

class LikedSongsScreen extends StatefulWidget {
  const LikedSongsScreen({super.key});

  @override
  State<LikedSongsScreen> createState() => _LikedSongsScreenState();
}

class _LikedSongsScreenState extends State<LikedSongsScreen> {
  late Future<List<Track>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<ApiClient>().favoriteTracks();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<FavoritesService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Liked Songs')),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<Track>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final tracks = snap.data ?? [];
                if (tracks.isEmpty) {
                  return const Center(child: Text('No liked songs yet.'));
                }
                return ListView.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, i) => TrackTile(
                    track: tracks[i],
                    leading: TrackCover(coverArtId: tracks[i].coverArtId),
                    onTap: () => context
                        .read<PlayerService>()
                        .playQueue(tracks, startIndex: i),
                  ),
                );
              },
            ),
          ),
          const MiniPlayer(),
        ],
      ),
    );
  }
}
