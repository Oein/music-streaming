import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../favorites/favorites_service.dart';
import '../player/player_service.dart';
import '../remote/remote_service.dart';
import '../settings/settings_service.dart';
import '../screens/now_playing_screen.dart';

class MiniPlayer extends StatelessWidget {
  // When true (default), the player reserves and pads the bottom system inset
  // (gesture bar / taskbar) so it — and the content above it — stays clear of
  // the system navigation area. Set false when another widget below it (e.g. a
  // NavigationBar) already handles that inset.
  final bool bottomSafe;
  const MiniPlayer({super.key, this.bottomSafe = true});

  @override
  Widget build(BuildContext context) {
    return _wrap(context, _buildInner(context));
  }

  Widget _wrap(BuildContext context, Widget inner) {
    if (!bottomSafe) return inner;
    return SafeArea(top: false, child: inner);
  }

  Widget _buildInner(BuildContext context) {
    final player = context.watch<PlayerService>();
    final remote = context.watch<RemoteService>();
    final track = player.currentTrack;

    if (track == null && !remote.isRemote) return const SizedBox.shrink();

    if (track == null && remote.isRemote) {
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            const Icon(Icons.speaker_group, size: 20),
            const SizedBox(width: 8),
            Text('Connected to ${remote.activeDeviceName}',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );
    }

    final api = context.read<ApiClient>();
    final showBuffer = context.watch<SettingsService>().showLoadingIndicator &&
        player.isBuffering;
    final pos = player.position;
    final dur = player.duration ?? Duration.zero;
    final progress = dur.inMilliseconds > 0
        ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NowPlayingScreen()),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: progress,
              minHeight: 2,
              backgroundColor: Colors.transparent,
              color: Theme.of(context).colorScheme.primary,
            ),
            if (remote.isRemote)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.speaker_group, size: 14),
                    const SizedBox(width: 4),
                    Text(remote.activeDeviceName ?? '',
                        style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Hero(
                    tag: 'now-playing-cover',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: track!.coverArtId != null
                            ? CachedNetworkImage(
                                imageUrl:
                                    api.coverUrl(track.coverArtId, size: 128),
                                fit: BoxFit.cover)
                            : Container(
                                color: Colors.white10,
                                child: const Icon(Icons.music_note)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      // Align children to the left so the title/artist are
                      // left-aligned (not centered) and vertically centered.
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      ),
                      child: Column(
                        key: ValueKey(track.id),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(track.title,
                              maxLines: 1,
                              textAlign: TextAlign.left,
                              overflow: TextOverflow.ellipsis),
                          Text(track.artist ?? '',
                              maxLines: 1,
                              textAlign: TextAlign.left,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                  Builder(builder: (context) {
                    final favs = context.watch<FavoritesService>();
                    final isLiked = favs.isLiked(track.id);
                    return IconButton(
                      icon: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        size: 20,
                        color: isLiked ? Colors.redAccent : null,
                      ),
                      onPressed: () => favs.toggle(track.id),
                    );
                  }),
                  showBuffer
                      ? const SizedBox(
                          width: 48,
                          height: 48,
                          child: Padding(
                            padding: EdgeInsets.all(14),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          icon: Icon(player.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow),
                          onPressed: player.togglePlay,
                        ),
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    onPressed: player.next,
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
