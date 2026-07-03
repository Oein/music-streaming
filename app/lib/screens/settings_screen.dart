import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../cache/audio_cache_service.dart';
import '../settings/settings_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Playback'),
          ListTile(
            title: const Text('Preload upcoming tracks'),
            subtitle: Text(
                'Buffer ${s.preloadCount} track(s) ahead for gapless playback'),
          ),
          Slider(
            value: s.preloadCount.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            label: '${s.preloadCount}',
            onChanged: (v) => s.update(preloadCount: v.round()),
          ),
          ListTile(
            title: const Text('Max buffer / cache'),
            subtitle: Text('${s.maxCacheMB} MB'),
          ),
          Slider(
            value: s.maxCacheMB.toDouble(),
            min: 64,
            max: 4096,
            divisions: 63,
            label: '${s.maxCacheMB} MB',
            onChanged: (v) => s.update(maxCacheMB: (v / 64).round() * 64),
          ),
          SwitchListTile(
            title: const Text('Show loading indicator'),
            subtitle: const Text('Display a spinner while buffering'),
            value: s.showLoadingIndicator,
            onChanged: (v) => s.update(showLoadingIndicator: v),
          ),
          const Divider(),
          const _SectionHeader('Library'),
          SwitchListTile(
            title: const Text('Album list view'),
            subtitle: const Text('Show albums as a list instead of a grid'),
            value: s.albumListView,
            onChanged: (v) => s.update(albumListView: v),
          ),
          ListTile(
            title: const Text('Album sort'),
            subtitle: Text({
                  'name': 'Name',
                  'artist': 'Artist',
                  'year': 'Year',
                  'added': 'Recently added',
                }[s.albumSort] ??
                s.albumSort),
            trailing: const Icon(Icons.arrow_drop_down),
            onTap: () async {
              final val = await showDialog<String>(
                context: context,
                builder: (ctx) => SimpleDialog(
                  title: const Text('Sort albums by'),
                  children: [
                    for (final e in [
                      ('name', 'Name'),
                      ('artist', 'Artist'),
                      ('year', 'Year'),
                      ('added', 'Recently added')
                    ])
                      SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, e.$1),
                        child: Text(e.$2),
                      ),
                  ],
                ),
              );
              if (val != null) s.update(albumSort: val);
            },
          ),
          const Divider(),
          const _SectionHeader('Cache'),
          Builder(builder: (context) {
            final cache = context.watch<AudioCacheService>();
            return Column(children: [
              ListTile(
                title: const Text('Audio cache'),
                subtitle: Text(
                    '${cache.cacheSizeMB.toStringAsFixed(1)} MB used of ${s.maxCacheMB} MB'),
              ),
              Slider(
                value: s.maxCacheMB.toDouble(),
                min: 64,
                max: 4096,
                divisions: 63,
                label: '${s.maxCacheMB} MB',
                onChanged: (v) => s.update(maxCacheMB: (v / 64).round() * 64),
              ),
              ListTile(
                title: const Text('Clear cache'),
                subtitle: const Text('Remove all cached and downloaded audio'),
                trailing: const Icon(Icons.delete_outline),
                onTap: () async {
                  await cache.clearCache();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Cache cleared')));
                  }
                },
              ),
            ]);
          }),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Changing preload or cache settings restarts the current playback.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title,
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold)),
      );
}
