import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../cache/audio_cache_service.dart';
import '../favorites/favorites_service.dart';
import '../models/models.dart';
import '../player/player_service.dart';

// A single track action shared by the mobile bottom sheet and the desktop
// right-click context menu.
class _Action {
  final IconData icon;
  final String label;
  final Future<void> Function(BuildContext) run;
  const _Action(this.icon, this.label, this.run);
}

List<_Action> _actionsFor(Track track,
        {bool liked = false, bool offline = false}) =>
    [
      _Action(
        liked ? Icons.favorite : Icons.favorite_border,
        liked ? 'Unlike' : 'Like',
        (c) async => c.read<FavoritesService>().toggle(track.id),
      ),
      _Action(Icons.play_arrow, 'Play now', (c) async {
        await c.read<PlayerService>().playQueue([track]);
      }),
      _Action(Icons.queue_play_next, 'Play next', (c) async {
        await c.read<PlayerService>().playNext(track);
      }),
      _Action(Icons.add_to_queue, 'Add to queue', (c) async {
        await c.read<PlayerService>().addToQueue(track);
      }),
      _Action(Icons.playlist_add, 'Add to playlist…', (c) async {
        await addToPlaylistFlow(c, track);
      }),
      _Action(
        offline ? Icons.download_done : Icons.download,
        offline ? 'Remove download' : 'Download offline',
        (c) async {
          final cache = c.read<AudioCacheService>();
          if (offline) {
            await cache.removeOffline(track.id);
          } else {
            await cache.downloadOffline(track.id);
          }
        },
      ),
    ];

// Mobile: bottom sheet with the actions.
Future<void> showTrackActions(BuildContext context, Track track) async {
  final liked = context.read<FavoritesService>().isLiked(track.id);
  final offline = context.read<AudioCacheService>().isOffline(track.id);
  final actions = _actionsFor(track, liked: liked, offline: offline);
  await showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
              title: Text(track.title), subtitle: Text(track.artist ?? '')),
          const Divider(height: 1),
          for (final a in actions)
            ListTile(
              leading: Icon(a.icon),
              title: Text(a.label),
              onTap: () async {
                Navigator.pop(ctx);
                await a.run(context);
              },
            ),
        ],
      ),
    ),
  );
}

// Desktop: popup menu at the pointer (right-click).
Future<void> showTrackContextMenu(
    BuildContext context, Track track, Offset globalPos) async {
  final liked = context.read<FavoritesService>().isLiked(track.id);
  final offline = context.read<AudioCacheService>().isOffline(track.id);
  final actions = _actionsFor(track, liked: liked, offline: offline);
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final selected = await showMenu<int>(
    context: context,
    position: RelativeRect.fromRect(
      globalPos & const Size(40, 40),
      Offset.zero & overlay.size,
    ),
    items: [
      for (var i = 0; i < actions.length; i++)
        PopupMenuItem(
          value: i,
          child: Row(children: [
            Icon(actions[i].icon, size: 18),
            const SizedBox(width: 10),
            Text(actions[i].label),
          ]),
        ),
    ],
  );
  if (selected != null && context.mounted) {
    await actions[selected].run(context);
  }
}

// Shared "add to playlist" picker (existing playlist or new one).
Future<void> addToPlaylistFlow(BuildContext context, Track track) async {
  final api = context.read<ApiClient>();
  final playlists = await api.playlists();
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('New playlist…'),
            onTap: () async {
              final name = await _promptName(ctx);
              if (name == null || name.isEmpty) return;
              final pl = await api.createPlaylist(name);
              await api.addToPlaylist(pl.id, track.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
          for (final pl in playlists)
            ListTile(
              leading: const Icon(Icons.queue_music),
              title: Text(pl.name),
              onTap: () async {
                await api.addToPlaylist(pl.id, track.id);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
        ],
      ),
    ),
  );
}

Future<String?> _promptName(BuildContext context) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Playlist name'),
      content: TextField(controller: ctrl, autofocus: true),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, ctrl.text.trim()),
          child: const Text('Create'),
        ),
      ],
    ),
  );
}
