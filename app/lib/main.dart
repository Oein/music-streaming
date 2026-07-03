import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'api/api_client.dart';
import 'player/player_service.dart';
import 'player/audio_handler.dart';
import 'remote/remote_service.dart';
import 'remote/device_identity.dart';
import 'cache/audio_cache_service.dart';
import 'favorites/favorites_service.dart';
import 'settings/settings_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Custom audio_service handler drives the OS media session/notification and
  // exposes a like button. Mobile/desktop only; on web its init throws and
  // would blank the app, so guard the platforms.
  MusicAudioHandler? audioHandler;
  try {
    final supportsBackground = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    if (supportsBackground) {
      // Time-bound the init: on some Android builds the platform channel can
      // stall indefinitely, which would freeze the app on the launch splash.
      // If it doesn't complete quickly, continue without background audio.
      audioHandler = await AudioService.init(
        builder: () => MusicAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.musicplayer.channel.audio',
          androidNotificationChannelName: 'Music playback',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      ).timeout(const Duration(seconds: 8));
    }
  } catch (e) {
    debugPrint('AudioService init failed or timed out: $e');
  }

  final api = ApiClient();
  await api.loadSession();
  DeviceIdentity identity;
  try {
    identity = await DeviceIdentity.load();
  } catch (_) {
    identity = DeviceIdentity('unknown', 'Unknown');
  }
  final remote = RemoteService(api);
  final settings = SettingsService();
  await settings.load();
  final favorites = FavoritesService(api);
  final audioCache = AudioCacheService(api, settings);
  await audioCache.init();

  final player = PlayerService(api, remote, settings, audioCache,
      audioHandler: audioHandler);

  // Wire the notification's like button to favorites, and keep the button's
  // icon in sync with the current track's favorite state.
  if (audioHandler != null) {
    audioHandler.onToggleFavorite = () async {
      final t = player.currentTrack;
      if (t != null) await favorites.toggle(t.id);
    };
    void syncFavorite() {
      final t = player.currentTrack;
      audioHandler!.setFavorite(t != null && favorites.isLiked(t.id));
    }

    player.addListener(syncFavorite);
    favorites.addListener(syncFavorite);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: api),
        ChangeNotifierProvider.value(value: remote),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: favorites),
        ChangeNotifierProvider.value(value: audioCache),
        ChangeNotifierProvider.value(value: player),
      ],
      child: MusicApp(identity: identity),
    ),
  );
}

class MusicApp extends StatefulWidget {
  final DeviceIdentity identity;
  const MusicApp({super.key, required this.identity});

  @override
  State<MusicApp> createState() => _MusicAppState();
}

class _MusicAppState extends State<MusicApp> {
  bool _wasLoggedIn = false;

  @override
  void initState() {
    super.initState();
    // Android 13+ needs the POST_NOTIFICATIONS runtime permission for the media
    // playback notification/controls to be visible. Ask once after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        if (!await Permission.notification.isGranted) {
          await Permission.notification.request();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4F7CFF),
          brightness: Brightness.dark,
        ),
      ),
      home: Consumer<ApiClient>(
        builder: (context, api, _) {
          // Open the remote hub connection once logged in.
          if (api.isLoggedIn && !_wasLoggedIn) {
            _wasLoggedIn = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              context
                  .read<RemoteService>()
                  .connect(widget.identity.id, widget.identity.name);
              context.read<FavoritesService>().load();
            });
          }
          if (!api.isLoggedIn) _wasLoggedIn = false;
          final content =
              api.isLoggedIn ? const HomeScreen() : const LoginScreen();
          // Space toggles play/pause app-wide. Focused text fields / buttons
          // consume Space first, so this only fires when nothing else claims it.
          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.space): () {
                final player = context.read<PlayerService>();
                if (player.currentTrack != null) player.togglePlay();
              },
            },
            child: Focus(autofocus: true, child: content),
          );
        },
      ),
    );
  }
}
