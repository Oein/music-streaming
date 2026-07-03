import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../settings/settings_service.dart';
import 'albums_screen.dart';
import 'tracks_screen.dart';
import 'playlists_screen.dart';
import 'queue_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import '../remote/device_picker.dart';
import '../remote/remote_service.dart';
import '../widgets/mini_player.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _tabs = [AlbumsScreen(), TracksScreen(), PlaylistsScreen()];
  static const _destinations = [
    (Icons.album, 'Albums'),
    (Icons.library_music, 'Songs'),
    (Icons.queue_music, 'Playlists'),
  ];

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 720;

    final settings = context.watch<SettingsService>();
    final actions = [
      IconButton(
        icon: const Icon(Icons.search),
        tooltip: 'Search',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SearchScreen()),
        ),
      ),
      if (_index == 0) ...[
        PopupMenuButton<String>(
          icon: const Icon(Icons.sort),
          tooltip: 'Sort albums',
          onSelected: (v) => settings.update(albumSort: v),
          itemBuilder: (_) => [
            for (final e in [
              ('name', 'Name'),
              ('artist', 'Artist'),
              ('year', 'Year'),
              ('added', 'Recently added')
            ])
              PopupMenuItem(
                value: e.$1,
                child: Row(children: [
                  if (settings.albumSort == e.$1)
                    const Icon(Icons.check, size: 18)
                  else
                    const SizedBox(width: 18),
                  const SizedBox(width: 8),
                  Text(e.$2),
                ]),
              ),
          ],
        ),
        IconButton(
          icon:
              Icon(settings.albumListView ? Icons.grid_view : Icons.view_list),
          tooltip: 'Toggle album layout',
          onPressed: () =>
              settings.update(albumListView: !settings.albumListView),
        ),
      ],
      IconButton(
        icon: const Icon(Icons.playlist_play),
        tooltip: 'Play queue',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const QueueScreen()),
        ),
      ),
      Builder(builder: (context) {
        final remote = context.watch<RemoteService>();
        return IconButton(
          icon: Icon(
              remote.isRemote ? Icons.speaker_group : Icons.devices_outlined),
          tooltip: 'Devices',
          onPressed: () => showDevicePicker(context),
        );
      }),
      PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'settings') {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()));
          } else if (v == 'logout') {
            context.read<ApiClient>().logout();
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'settings', child: Text('Settings')),
          PopupMenuItem(value: 'logout', child: Text('Logout')),
        ],
      ),
    ];

    final content = _tabs[_index];

    // Wide layout: side navigation rail. Narrow: bottom navigation bar.
    if (isWide) {
      return Scaffold(
        appBar: AppBar(title: const Text('Music'), actions: actions),
        body: Row(
          children: [
            SafeArea(
              top: false,
              right: false,
              child: NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final d in _destinations)
                    NavigationRailDestination(
                      icon: Icon(d.$1),
                      label: Text(d.$2),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: content),
          ],
        ),
        // MiniPlayer as bottomNavigationBar so Scaffold reserves space; it
        // pads the bottom system inset itself (bottomSafe defaults to true).
        bottomNavigationBar: const MiniPlayer(),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Music'), actions: actions),
      body: content,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(bottomSafe: false),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              for (final d in _destinations)
                NavigationDestination(icon: Icon(d.$1), label: d.$2),
            ],
          ),
        ],
      ),
    );
  }
}
