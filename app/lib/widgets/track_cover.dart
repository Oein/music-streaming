import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';

// Small square album-cover thumbnail for a track, with a music-note fallback.
class TrackCover extends StatelessWidget {
  final int? coverArtId;
  final double size;
  const TrackCover({super.key, required this.coverArtId, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: size,
        height: size,
        child: coverArtId != null
            ? CachedNetworkImage(
                imageUrl: api.coverUrl(coverArtId, size: 128),
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const _Fallback(),
                placeholder: (_, __) => const _Fallback(),
              )
            : const _Fallback(),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback();
  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white10,
        child: const Icon(Icons.music_note, size: 22),
      );
}
