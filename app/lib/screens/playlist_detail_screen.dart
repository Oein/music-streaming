import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../models/models.dart';
import '../player/player_service.dart';
import '../widgets/mini_player.dart';
import 'track_actions.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;
  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  List<Track> _tracks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final tracks = await api.playlistTracks(widget.playlist.id);
    setState(() {
      _tracks = tracks;
      _loading = false;
    });
    // (B) Warm the transcode cache for this playlist so playback is instant.
    api.prewarm(tracks.map((t) => t.id).toList());
  }

  Future<void> _persistOrder() async {
    await context
        .read<ApiClient>()
        .reorderPlaylist(widget.playlist.id, _tracks.map((t) => t.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlist.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            onPressed: _tracks.isEmpty
                ? null
                : () => context.read<PlayerService>().playQueue(_tracks),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await context
                  .read<ApiClient>()
                  .deletePlaylist(widget.playlist.id);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      bottomNavigationBar: const MiniPlayer(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ReorderableListView.builder(
              itemCount: _tracks.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final t = _tracks.removeAt(oldIndex);
                  _tracks.insert(newIndex, t);
                });
                _persistOrder();
              },
              itemBuilder: (context, i) {
                final t = _tracks[i];
                return GestureDetector(
                  key: ValueKey(t.id),
                  behavior: HitTestBehavior.opaque,
                  onSecondaryTapDown: (d) =>
                      showTrackContextMenu(context, t, d.globalPosition),
                  child: ListTile(
                    leading: const Icon(Icons.drag_handle),
                    title: Text(t.title),
                    subtitle: Text(t.artist ?? ''),
                    onTap: () => context
                        .read<PlayerService>()
                        .playQueue(_tracks, startIndex: i),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () {
                        setState(() => _tracks.removeAt(i));
                        _persistOrder();
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
