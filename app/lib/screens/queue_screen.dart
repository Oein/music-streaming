import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../models/models.dart';
import '../player/player_service.dart';
import '../widgets/track_tile.dart';

class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  Widget _cover(ApiClient api, Track t) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 44,
        height: 44,
        child: t.coverArtId != null
            ? CachedNetworkImage(
                imageUrl: api.coverUrl(t.coverArtId, size: 128),
                fit: BoxFit.cover,
              )
            : Container(
                color: Colors.white10,
                child: const Icon(Icons.music_note, size: 20),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return Scaffold(
      appBar: AppBar(title: const Text('Play Queue')),
      body: Consumer<PlayerService>(
        builder: (context, player, _) {
          final queue = player.queue;
          final current = player.currentIndex ?? 0;
          if (queue.isEmpty) {
            return const Center(child: Text('Queue is empty.'));
          }
          final visible = queue.length - current;
          return ReorderableListView.builder(
            // Keep the last items clear of the system navigation bar / taskbar.
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 12),
            itemCount: visible,
            onReorder: (oldIndex, newIndex) {
              if (oldIndex == 0 || newIndex == 0) return;
              final from = current + oldIndex;
              final to =
                  current + (newIndex > oldIndex ? newIndex - 1 : newIndex);
              player.reorderQueue(from, to);
            },
            itemBuilder: (context, i) {
              final qi = current + i;
              final t = queue[qi];
              return Container(
                key: ValueKey('${t.id}-$qi'),
                decoration: qi == current
                    ? BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 3,
                          ),
                        ),
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.08),
                      )
                    : null,
                child: TrackTile(
                  track: t,
                  highlighted: qi == current,
                  leading: _cover(api, t),
                  trailing: qi == current
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => player.removeFromQueue(qi),
                        ),
                  onTap: () => player.jumpTo(qi),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
