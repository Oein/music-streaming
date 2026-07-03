import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../models/models.dart';
import '../player/player_service.dart';
import '../widgets/track_tile.dart';
import '../widgets/mini_player.dart';

class AlbumDetailScreen extends StatefulWidget {
  final Album album;
  const AlbumDetailScreen({super.key, required this.album});

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  late Future<List<Track>> _future;

  @override
  void initState() {
    super.initState();
    final api = context.read<ApiClient>();
    _future = api.albumTracks(widget.album.id);
    // (B) Warm the transcode cache for this album so playback starts instantly.
    _future.then((tracks) => api.prewarm(tracks.map((t) => t.id).toList()));
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return Scaffold(
      appBar: AppBar(title: Text(widget.album.name)),
      bottomNavigationBar: const MiniPlayer(),
      body: FutureBuilder<List<Track>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final tracks = snap.data ?? [];
          return ListView.builder(
            itemCount: tracks.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 96,
                          height: 96,
                          child: widget.album.coverArtId != null
                              ? CachedNetworkImage(
                                  imageUrl: api.coverUrl(
                                      widget.album.coverArtId,
                                      size: 256),
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  color: Colors.white10,
                                  child: const Icon(Icons.album, size: 40)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.album.name,
                                style: Theme.of(context).textTheme.titleLarge),
                            Text(widget.album.albumArtist ?? ''),
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed: () => context
                                  .read<PlayerService>()
                                  .playQueue(tracks, startIndex: 0),
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Play'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }
              final t = tracks[i - 1];
              return TrackTile(
                track: t,
                leading: SizedBox(
                    width: 24, child: Center(child: Text('${t.trackNo ?? i}'))),
                onTap: () => context
                    .read<PlayerService>()
                    .playQueue(tracks, startIndex: i - 1),
              );
            },
          );
        },
      ),
    );
  }
}
