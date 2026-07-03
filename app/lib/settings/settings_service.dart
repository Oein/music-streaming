import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// User-tunable playback/UI preferences, persisted locally.
class SettingsService extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _key = 'settings';

  // How many upcoming tracks to buffer ahead (maps to player buffer sizing).
  int preloadCount = 2;
  // Max media buffer/cache to use, in megabytes.
  int maxCacheMB = 512;
  // Whether to show a loading/buffering indicator during playback.
  bool showLoadingIndicator = true;
  // Album browsing layout: grid (false) or list (true).
  bool albumListView = false;
  // Album sort key: 'name' | 'artist' | 'year' | 'added'.
  String albumSort = 'name';
  // App-internal playback volume (0.0–1.0), NOT the OS/system volume.
  double volume = 1.0;
  // Force server-side AAC transcoding instead of native lossless playback.
  // Trades audio quality for smaller/smoother (cached, seekable) streams.
  bool forceAac = false;

  Future<void> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        preloadCount = (j['preloadCount'] as int?) ?? preloadCount;
        maxCacheMB = (j['maxCacheMB'] as int?) ?? maxCacheMB;
        showLoadingIndicator =
            (j['showLoadingIndicator'] as bool?) ?? showLoadingIndicator;
        albumListView = (j['albumListView'] as bool?) ?? albumListView;
        albumSort = (j['albumSort'] as String?) ?? albumSort;
        volume = (j['volume'] as num?)?.toDouble().clamp(0.0, 1.0) ?? volume;
        forceAac = (j['forceAac'] as bool?) ?? forceAac;
      }
    } catch (_) {
      /* keep defaults */
    }
  }

  Future<void> _save() async {
    try {
      await _storage.write(
        key: _key,
        value: jsonEncode({
          'preloadCount': preloadCount,
          'maxCacheMB': maxCacheMB,
          'showLoadingIndicator': showLoadingIndicator,
          'albumListView': albumListView,
          'albumSort': albumSort,
          'volume': volume,
          'forceAac': forceAac,
        }),
      );
    } catch (_) {
      /* non-persistent */
    }
  }

  // `playbackChanged` is true when a change affects the audio player's load
  // configuration (so the player must be reconfigured).
  Future<void> update({
    int? preloadCount,
    int? maxCacheMB,
    bool? showLoadingIndicator,
    bool? albumListView,
    String? albumSort,
    double? volume,
    bool? forceAac,
  }) async {
    var playbackChanged = false;
    var formatChanged = false;
    if (preloadCount != null && preloadCount != this.preloadCount) {
      this.preloadCount = preloadCount;
      playbackChanged = true;
    }
    if (maxCacheMB != null && maxCacheMB != this.maxCacheMB) {
      this.maxCacheMB = maxCacheMB;
      playbackChanged = true;
    }
    if (showLoadingIndicator != null) {
      this.showLoadingIndicator = showLoadingIndicator;
    }
    if (albumListView != null) this.albumListView = albumListView;
    if (albumSort != null) this.albumSort = albumSort;
    if (volume != null) this.volume = volume.clamp(0.0, 1.0);
    if (forceAac != null && forceAac != this.forceAac) {
      this.forceAac = forceAac;
      formatChanged = true;
    }
    await _save();
    notifyListeners();
    if (playbackChanged) _playbackConfigListeners.forEach((f) => f());
    if (formatChanged) _formatListeners.forEach((f) => f());
  }

  // PlayerService subscribes here to rebuild its player on load-config changes.
  final List<VoidCallback> _playbackConfigListeners = [];
  void onPlaybackConfigChanged(VoidCallback cb) =>
      _playbackConfigListeners.add(cb);

  // PlayerService subscribes here to reload the current track with the new
  // stream format (AAC vs native) when [forceAac] is toggled.
  final List<VoidCallback> _formatListeners = [];
  void onAudioFormatChanged(VoidCallback cb) => _formatListeners.add(cb);
}
