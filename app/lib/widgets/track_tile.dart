import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../cache/audio_cache_service.dart';
import '../models/models.dart';
import '../player/player_service.dart';
import '../screens/track_actions.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final Widget? leading;
  final Widget? trailing;
  final bool highlighted;
  final VoidCallback onTap;

  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.leading,
    this.trailing,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final isPlaying =
        context.watch<PlayerService>().currentTrack?.id == track.id;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (d) =>
          showTrackContextMenu(context, track, d.globalPosition),
      onLongPressStart: (d) =>
          showTrackContextMenu(context, track, d.globalPosition),
      child: Container(
        color: isPlaying && !highlighted
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
            : null,
        child: ListTile(
          selected: highlighted,
          leading: isPlaying && leading != null
              ? Icon(Icons.equalizer,
                  color: Theme.of(context).colorScheme.primary, size: 20)
              : leading,
          title: Row(
            children: [
              Expanded(
                child: Text(track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: isPlaying
                        ? TextStyle(
                            color: Theme.of(context).colorScheme.primary)
                        : null),
              ),
              if (context.watch<AudioCacheService>().isOffline(track.id))
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child:
                      Icon(Icons.download_done, size: 14, color: Colors.green),
                ),
            ],
          ),
          subtitle: track.artist != null
              ? Text(track.artist!,
                  maxLines: 1, overflow: TextOverflow.ellipsis)
              : null,
          trailing: trailing ??
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () => showTrackActions(context, track),
              ),
          onTap: onTap,
        ),
      ),
    );
  }
}
