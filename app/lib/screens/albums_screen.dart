import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../models/models.dart';
import '../settings/settings_service.dart';
import 'album_detail_screen.dart';

class AlbumsScreen extends StatefulWidget {
  const AlbumsScreen({super.key});

  @override
  State<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends State<AlbumsScreen> {
  late Future<List<Album>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<ApiClient>().albums();
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    return FutureBuilder<List<Album>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final albums = snap.data ?? [];
        if (albums.isEmpty) {
          return const Center(child: Text('No albums. Scan a folder first.'));
        }
        final settings = context.watch<SettingsService>();
        final listView = settings.albumListView;
        _sortAlbums(albums, settings.albumSort);
        if (listView) {
          return ListView.builder(
            itemCount: albums.length,
            itemBuilder: (context, i) {
              final a = albums[i];
              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: a.coverArtId != null
                        ? CachedNetworkImage(
                            imageUrl: api.coverUrl(a.coverArtId, size: 128),
                            fit: BoxFit.cover)
                        : const _CoverFallback(),
                  ),
                ),
                title:
                    Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(a.albumArtist ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text('${a.trackCount}'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => AlbumDetailScreen(album: a)),
                ),
              );
            },
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            childAspectRatio: 0.78,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: albums.length,
          itemBuilder: (context, i) {
            final a = albums[i];
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AlbumDetailScreen(album: a)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: a.coverArtId != null
                              ? CachedNetworkImage(
                                  imageUrl:
                                      api.coverUrl(a.coverArtId, size: 400),
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) =>
                                      const _CoverFallback(),
                                )
                              : const _CoverFallback(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(a.albumArtist ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

void _sortAlbums(List<Album> albums, String sort) {
  switch (sort) {
    case 'artist':
      albums
          .sort((a, b) => (a.albumArtist ?? '').compareTo(b.albumArtist ?? ''));
      break;
    case 'year':
      albums.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
      break;
    case 'added':
      albums.sort((a, b) => b.id.compareTo(a.id));
      break;
    default:
      albums
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();
  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white10,
        child: const Icon(Icons.album, size: 48),
      );
}
