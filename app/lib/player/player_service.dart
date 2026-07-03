import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../api/api_client.dart';
import '../cache/audio_cache_service.dart';
import '../models/models.dart';
import '../remote/remote_service.dart';
import '../settings/settings_service.dart';
import 'audio_handler.dart';

// Playback facade for the UI. When the remote target is THIS device it drives
// the local just_audio player. When the target is another device it forwards
// commands over the hub and reflects that device's reported state.
class PlayerService extends ChangeNotifier {
  final ApiClient api;
  final RemoteService remote;
  final SettingsService settings;
  final AudioCacheService cache;
  final MusicAudioHandler? audioHandler;
  late AudioPlayer _player;
  final List<StreamSubscription> _subs = [];
  List<Track> _queue = [];
  ConcatenatingAudioSource? _source;
  late Stream<Duration> _positionStream;
  Duration _position = Duration.zero;
  Track? _lastTrack;
  // Tracks the local→remote transition so we pause local playback exactly once
  // when control moves to another device.
  bool _wasRemote = false;

  PlayerService(this.api, this.remote, this.settings, this.cache,
      {this.audioHandler}) {
    _player = _buildPlayer();
    _player.setVolume(settings.volume);
    _positionStream = _player.positionStream.asBroadcastStream();
    audioHandler?.attach(_player);
    _wire();
    // Execute commands sent to us by a controller device.
    remote.onCommand = _applyRemoteCommand;
    _wasRemote = remote.isRemote;
    remote.addListener(_onRemoteChanged);
    // Route this device's OS media-session transport controls to the remote
    // target while remoting (so the notification/lock screen drives it).
    audioHandler?.onRemotePlay = () async => remote.sendCommand('play');
    audioHandler?.onRemotePause = () async => remote.sendCommand('pause');
    audioHandler?.onRemoteNext = () async => remote.sendCommand('next');
    audioHandler?.onRemotePrevious = () async => remote.sendCommand('previous');
    audioHandler?.onRemoteSeek = (pos) async =>
        remote.sendCommand('seek', {'position': pos.inMilliseconds});
    // Stop playback when the user logs out.
    api.addListener(_onAuthChanged);
    // Rebuild the player when buffer/cache settings change.
    settings.onPlaybackConfigChanged(_reconfigure);
  }

  // Build an AudioPlayer whose buffering is sized from user settings:
  // preloadCount scales how far ahead to buffer, maxCacheMB caps memory use.
  AudioPlayer _buildPlayer() {
    final ahead = Duration(seconds: 30 * settings.preloadCount.clamp(1, 10));
    return AudioPlayer(
      audioLoadConfiguration: AudioLoadConfiguration(
        darwinLoadControl: DarwinLoadControl(
          preferredForwardBufferDuration: ahead,
        ),
        androidLoadControl: AndroidLoadControl(
          maxBufferDuration: ahead * 2,
          targetBufferBytes: settings.maxCacheMB.clamp(16, 4096) * 1024 * 1024,
        ),
      ),
    );
  }

  void _wire() {
    _subs.add(_player.currentIndexStream.listen((idx) {
      if (idx != null && idx >= 0 && idx < _queue.length) {
        cache.recordPlay(_queue[idx].id);
        // (B) Warm the server transcode cache for the next couple of tracks so
        // they start instantly when the current one ends.
        final upcoming = _queue.skip(idx + 1).take(2).map((t) => t.id).toList();
        if (upcoming.isNotEmpty) api.prewarm(upcoming);
      }
      _broadcast();
      notifyListeners();
    }));
    _subs.add(_player.playerStateStream.listen((_) {
      _broadcast();
      notifyListeners();
    }));
    _subs.add(_player.positionStream.listen((p) {
      _position = p;
      _broadcast();
      notifyListeners();
    }));
    _subs.add(_player.durationStream.listen((_) => notifyListeners()));
    // Volume changes (incl. those driven by a remote controller) update the UI
    // and are reported to any controller device.
    _subs.add(_player.volumeStream.listen((_) {
      _broadcast();
      notifyListeners();
    }));
  }

  // Recreate the player with new load settings (stops current playback).
  Future<void> _reconfigure() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _player.dispose();
    _queue = [];
    _source = null;
    _player = _buildPlayer();
    _player.setVolume(settings.volume);
    _positionStream = _player.positionStream.asBroadcastStream();
    audioHandler?.attach(_player);
    _wire();
    notifyListeners();
  }

  // True while the player is loading/buffering (local playback only).
  bool get isBuffering =>
      !_remote &&
      (_player.processingState == ProcessingState.loading ||
          _player.processingState == ProcessingState.buffering);

  // When the active target flips from this device to a remote one, pause local
  // playback so it doesn't keep playing here in the background.
  void _onRemoteChanged() {
    final nowRemote = remote.isRemote;
    if (nowRemote && !_wasRemote) {
      audioHandler?.enterRemoteMode();
      if (_player.playing) _player.pause();
    } else if (!nowRemote && _wasRemote) {
      audioHandler?.exitRemoteMode();
    }
    _wasRemote = nowRemote;
    // Keep this device's media session in sync with the remote target so the
    // remote track shows in the notification / lock screen here.
    if (nowRemote) _pushRemoteToSession();
    notifyListeners();
  }

  // Mirror the active remote device's track + playback onto the OS media
  // session of this (controller) device.
  void _pushRemoteToSession() {
    final h = audioHandler;
    if (h == null) return;
    final t = currentTrack;
    final dur = duration ?? Duration.zero;
    final item = t == null
        ? null
        : MediaItem(
            id: t.id.toString(),
            title: t.title,
            artist: t.artist ?? 'Unknown',
            duration: dur > Duration.zero ? dur : null,
            artUri: t.coverArtId != null
                ? Uri.parse(api.coverUrl(t.coverArtId, size: 256))
                : null,
          );
    h.publishRemote(
      item: item,
      playing: isPlaying,
      position: position,
      duration: dur,
    );
  }

  void _onAuthChanged() {
    if (!api.isLoggedIn) {
      _player.stop();
      _queue = [];
      _source = null;
      notifyListeners();
    }
  }

  AudioPlayer get player => _player;
  // Position reflects the active target: the remote device's reported position
  // when remoting, otherwise the local player. (The bare _position field is only
  // updated by the local player, so remote controllers must not read it.)
  Duration get position {
    if (_remote) {
      return Duration(
          milliseconds: (remote.remoteState?['position'] as int?) ?? 0);
    }
    return _position;
  }

  List<Track> get queue => _queue;
  int? get currentIndex => _remote ? null : _player.currentIndex;
  Stream<int?> get currentIndexStream => _player.currentIndexStream;

  bool get _remote => remote.isRemote;

  // ---- State getters (switch between local and remote source of truth) ----

  Track? get currentTrack {
    if (_remote) {
      final s = remote.remoteState;
      if (s == null || s['trackId'] == null) return null;
      return Track(
        id: s['trackId'] as int,
        title: (s['title'] as String?) ?? '',
        artist: s['artist'] as String?,
        format: (s['format'] as String?) ?? '',
        coverArtId: s['coverArtId'] as int?,
      );
    }
    final idx = _player.currentIndex;
    if (idx == null || idx < 0 || idx >= _queue.length) return _lastTrack;
    _lastTrack = _queue[idx];
    return _lastTrack;
  }

  bool get isPlaying => _remote
      ? (remote.remoteState?['playing'] as bool? ?? false)
      : _player.playing;

  // Total duration. Transcoded streams (e.g. FLAC→AAC) carry no duration, so
  // fall back to the track's known duration from the server metadata.
  Duration? get _trackDuration {
    final t = currentTrack;
    if (t?.duration != null && t!.duration! > 0) {
      return Duration(milliseconds: (t.duration! * 1000).round());
    }
    return null;
  }

  Duration? get duration {
    if (_remote) {
      final ms = (remote.remoteState?['duration'] as int?) ?? 0;
      return ms > 0 ? Duration(milliseconds: ms) : _trackDuration;
    }
    final d = _player.duration;
    return (d != null && d.inMilliseconds > 0) ? d : _trackDuration;
  }

  Stream<Duration> get positionStream => _remote
      ? Stream<Duration>.periodic(
          const Duration(milliseconds: 500),
          (_) => Duration(
              milliseconds: (remote.remoteState?['position'] as int?) ?? 0))
      : _positionStream;

  // Emits whenever the track duration becomes known/changes. For remote
  // targets it ticks from the last reported state.
  Stream<Duration?> get durationStream => _remote
      ? Stream<Duration?>.periodic(
          const Duration(milliseconds: 500), (_) => duration)
      : _player.durationStream
          .map((d) => (d != null && d.inMilliseconds > 0) ? d : _trackDuration);

  // Buffered position for the progress bar's secondary track (local only).
  Duration get bufferedPosition =>
      _remote ? Duration.zero : _player.bufferedPosition;

  LoopMode get loopMode => _player.loopMode;

  // App-internal playback volume (0.0–1.0), NOT the OS/system volume. Reflects
  // the active target: the remote device's volume when remoting, else local.
  double get volume {
    if (_remote) {
      final v = remote.remoteState?['volume'];
      return v is num ? v.toDouble().clamp(0.0, 1.0) : 1.0;
    }
    return _player.volume.clamp(0.0, 1.0);
  }

  // Set the app-internal volume on the active target. Pass persist:false while
  // dragging a slider and persist:true once (e.g. on drag end) to avoid a
  // storage write per frame. Ignored for persistence when remoting.
  Future<void> setVolume(double v, {bool persist = false}) async {
    final vol = v.clamp(0.0, 1.0);
    if (_remote) return remote.sendCommand('volume', {'value': vol});
    await _player.setVolume(vol);
    if (persist) await settings.update(volume: vol);
  }

  // ---- Commands (forward to remote device when targeting one) ----

  Future<void> playQueue(List<Track> tracks, {int startIndex = 0}) async {
    if (_remote) {
      remote.sendCommand('playQueue', {
        'tracks': tracks.map(_trackJson).toList(),
        'startIndex': startIndex,
      });
      return;
    }
    await _localPlayQueue(tracks, startIndex: startIndex);
  }

  Future<void> togglePlay() async {
    if (_remote) return remote.sendCommand(isPlaying ? 'pause' : 'play');
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> next() async {
    if (_remote) return remote.sendCommand('next');
    await _player.seekToNext();
  }

  Future<void> previous() async {
    if (_remote) return remote.sendCommand('previous');
    await _player.seekToPrevious();
  }

  Future<void> seek(Duration pos) async {
    if (_remote)
      return remote.sendCommand('seek', {'position': pos.inMilliseconds});
    await _player.seek(pos);
  }

  Future<void> shuffleQueue() async {
    if (_remote) return remote.sendCommand('shuffle');
    final idx = _player.currentIndex ?? 0;
    if (idx + 1 >= _queue.length) return;
    final upcoming = _queue.sublist(idx + 1)..shuffle();
    _queue = [_queue[idx], ...upcoming];
    final sources = await Future.wait(_queue.map(_cachedSourceFor));
    _source = ConcatenatingAudioSource(children: sources);
    await _player.setAudioSource(_source!, initialIndex: 0);
    await _player.play();
    notifyListeners();
  }

  // Jump to a specific queue index.
  Future<void> jumpTo(int index) async {
    if (_remote) return remote.sendCommand('jump', {'index': index});
    await _player.seek(Duration.zero, index: index);
  }

  // Append a track to the end of the queue.
  Future<void> addToQueue(Track t) async {
    if (_remote) return remote.sendCommand('enqueue', {'track': _trackJson(t)});
    _queue.add(t);
    final src = await _cachedSourceFor(t);
    await _source?.add(src);
    notifyListeners();
  }

  // Insert a track to play right after the current one.
  Future<void> playNext(Track t) async {
    if (_remote)
      return remote.sendCommand('playNext', {'track': _trackJson(t)});
    final at = (_player.currentIndex ?? -1) + 1;
    _queue.insert(at, t);
    final src = await _cachedSourceFor(t);
    await _source?.insert(at, src);
    notifyListeners();
  }

  // Remove a track from the queue by index.
  Future<void> removeFromQueue(int index) async {
    if (_remote) return remote.sendCommand('dequeue', {'index': index});
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    await _source?.removeAt(index);
    notifyListeners();
  }

  Future<void> reorderQueue(int from, int to) async {
    if (from < 0 || from >= _queue.length || to < 0 || to >= _queue.length)
      return;
    final track = _queue.removeAt(from);
    _queue.insert(to, track);
    await _source?.removeAt(from);
    final src = await _cachedSourceFor(track);
    await _source?.insert(to, src);
    notifyListeners();
  }

  Future<void> cycleLoop() async {
    if (_remote) return remote.sendCommand('loop');
    const modes = [LoopMode.off, LoopMode.all, LoopMode.one];
    final idx = modes.indexOf(_player.loopMode);
    await _player.setLoopMode(modes[(idx + 1) % modes.length]);
    notifyListeners();
  }

  // ---- Remote command execution (someone controls THIS device) ----

  Future<void> _applyRemoteCommand(
      String command, Map<String, dynamic>? payload) async {
    switch (command) {
      case 'playQueue':
        final tracks = (payload!['tracks'] as List)
            .map((t) => Track.fromJson((t as Map).cast<String, dynamic>()))
            .toList();
        await _localPlayQueue(tracks,
            startIndex: (payload['startIndex'] as int?) ?? 0);
        break;
      case 'play':
        await _player.play();
        break;
      case 'pause':
        await _player.pause();
        break;
      case 'next':
        await _player.seekToNext();
        break;
      case 'previous':
        await _player.seekToPrevious();
        break;
      case 'seek':
        await _player.seek(Duration(milliseconds: payload!['position'] as int));
        break;
      case 'jump':
        await _player.seek(Duration.zero, index: payload!['index'] as int);
        break;
      case 'enqueue':
        await addToQueue(
            Track.fromJson((payload!['track'] as Map).cast<String, dynamic>()));
        break;
      case 'playNext':
        await playNext(
            Track.fromJson((payload!['track'] as Map).cast<String, dynamic>()));
        break;
      case 'dequeue':
        await removeFromQueue(payload!['index'] as int);
        break;
      case 'shuffle':
        await shuffleQueue();
        break;
      case 'loop':
        await cycleLoop();
        break;
      case 'volume':
        // volumeStream (wired in _wire) broadcasts the new level back to the
        // controller, so no explicit re-broadcast is needed here.
        await _player.setVolume((payload!['value'] as num).toDouble());
        break;
    }
  }

  Future<void> _localPlayQueue(List<Track> tracks, {int startIndex = 0}) async {
    final effective =
        startIndex > 0 ? tracks.sublist(startIndex) : List.of(tracks);
    _queue = effective;
    final sources = await Future.wait(effective.map(_cachedSourceFor));
    _source = ConcatenatingAudioSource(children: sources);
    await _player.setAudioSource(_source!);
    await _player.play();
    notifyListeners();
  }

  AudioSource _sourceFor(Track t, {Uri? cachedUri}) {
    return AudioSource.uri(
      cachedUri ?? api.streamUri(t.id),
      tag: MediaItem(
        id: t.id.toString(),
        title: t.title,
        artist: t.artist ?? 'Unknown',
        artUri: t.coverArtId != null
            ? Uri.parse(api.coverUrl(t.coverArtId, size: 256))
            : null,
      ),
    );
  }

  Future<AudioSource> _cachedSourceFor(Track t) async {
    if (cache.ready && cache.isCached(t.id)) {
      final uri = await cache.getOrFetch(t.id);
      return _sourceFor(t, cachedUri: uri);
    }
    return _sourceFor(t);
  }

  Map<String, dynamic> _trackJson(Track t) => {
        'id': t.id,
        'title': t.title,
        'artist': t.artist,
        'albumId': t.albumId,
        'trackNo': t.trackNo,
        'duration': t.duration,
        'format': t.format,
        'coverArtId': t.coverArtId,
      };

  // Report local playback so controllers can display it. Only meaningful when
  // this device is actually playing locally (not mirroring a remote target).
  void _broadcast() {
    if (_remote) return;
    final t = currentTrack;
    remote.broadcastState({
      'trackId': t?.id,
      'title': t?.title,
      'artist': t?.artist,
      'format': t?.format,
      'coverArtId': t?.coverArtId,
      'playing': _player.playing,
      'position': _position.inMilliseconds,
      'duration': _player.duration?.inMilliseconds ?? 0,
      'volume': _player.volume,
    });
  }

  @override
  void dispose() {
    remote.removeListener(_onRemoteChanged);
    api.removeListener(_onAuthChanged);
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}
