import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// Custom audio_service handler that mirrors a just_audio [AudioPlayer] to the
/// OS media session and notification. Unlike just_audio_background it exposes a
/// customisable control set — here we add a "favorite" (like) button.
///
/// PlayerService owns the [AudioPlayer]; it calls [attach] whenever the player
/// is (re)built. Favorite state is fed in via [setFavorite]; taps on the
/// notification's like button are surfaced through [onToggleFavorite].
class MusicAudioHandler extends BaseAudioHandler with SeekHandler {
  AudioPlayer? _player;
  final List<StreamSubscription> _subs = [];
  bool _isFavorite = false;

  /// When true, the media session mirrors a REMOTE device (this device is a
  /// controller). Local player events are suppressed and transport commands are
  /// routed through the on* callbacks below.
  bool _remoteMode = false;

  /// Invoked when the user taps the like button in the notification / media
  /// session. Set by the app wiring; toggles the current track's favorite.
  Future<void> Function()? onToggleFavorite;

  /// Transport commands to forward to the remote device while in remote mode.
  Future<void> Function()? onRemotePlay;
  Future<void> Function()? onRemotePause;
  Future<void> Function()? onRemoteNext;
  Future<void> Function()? onRemotePrevious;
  Future<void> Function(Duration position)? onRemoteSeek;

  /// Attach (or re-attach after a player rebuild) to a just_audio player.
  void attach(AudioPlayer player) {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _player = player;

    _subs.add(player.playbackEventStream.listen((_) => _broadcastState()));
    _subs.add(player.playingStream.listen((_) => _broadcastState()));

    // Push the current track's metadata (from the AudioSource tag) to the OS.
    // Merge in the player's known duration so the notification seek bar has a
    // range even if the tag didn't carry one.
    _subs.add(player.sequenceStateStream.listen((seqState) {
      if (_remoteMode) return;
      final src = seqState?.currentSource;
      final tag = src?.tag;
      if (tag is MediaItem) {
        final dur = player.duration;
        mediaItem.add(dur != null && tag.duration == null
            ? tag.copyWith(duration: dur)
            : tag);
      }
    }));

    // Once the real duration is decoded, update the current item so the OS
    // media control shows an accurate, seekable progress bar.
    _subs.add(player.durationStream.listen((dur) {
      if (_remoteMode || dur == null) return;
      final current = mediaItem.value;
      if (current != null && current.duration != dur) {
        mediaItem.add(current.copyWith(duration: dur));
      }
    }));

    _broadcastState();
  }

  /// Update the like state shown on the notification button.
  void setFavorite(bool value) {
    if (_isFavorite == value) return;
    _isFavorite = value;
    _broadcastState();
  }

  AudioProcessingState _mapState(ProcessingState? s) {
    switch (s) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
      case null:
        return AudioProcessingState.idle;
    }
  }

  /// Enter remote mode: stop mirroring the local player and hold the session
  /// so [publishRemote] fully drives what the OS shows.
  void enterRemoteMode() => _remoteMode = true;

  /// Leave remote mode and resume mirroring the local player.
  void exitRemoteMode() {
    _remoteMode = false;
    _broadcastState();
  }

  /// Publish the REMOTE device's current track + playback to the OS media
  /// session so it appears in the notification / lock screen on this device.
  void publishRemote({
    required MediaItem? item,
    required bool playing,
    required Duration position,
    Duration? duration,
  }) {
    if (item != null) mediaItem.add(item);
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        _favoriteControl,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.ready,
      playing: playing,
      updatePosition: position,
      bufferedPosition: duration ?? position,
      speed: 1.0,
      queueIndex: null,
    ));
  }

  MediaControl get _favoriteControl => MediaControl.custom(
        androidIcon: _isFavorite
            ? 'drawable/ic_favorite'
            : 'drawable/ic_favorite_border',
        label: 'Favorite',
        name: 'favorite',
      );

  void _broadcastState() {
    // In remote mode publishRemote() owns the session; ignore local events.
    if (_remoteMode) return;
    final player = _player;
    if (player == null) return;
    final playing = player.playing;

    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        _favoriteControl,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      // Show prev / play-pause / next in the compact (collapsed) notification.
      androidCompactActionIndices: const [0, 1, 2],
      processingState: _mapState(player.processingState),
      playing: playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: player.currentIndex,
    ));
  }

  // ---- Media session commands (from notification, headset, etc.) ----

  @override
  Future<void> play() => _remoteMode
      ? (onRemotePlay?.call() ?? Future.value())
      : (_player?.play() ?? Future.value());

  @override
  Future<void> pause() => _remoteMode
      ? (onRemotePause?.call() ?? Future.value())
      : (_player?.pause() ?? Future.value());

  @override
  Future<void> stop() async {
    if (_remoteMode) {
      await onRemotePause?.call();
      return;
    }
    await _player?.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _remoteMode
      ? (onRemoteSeek?.call(position) ?? Future.value())
      : (_player?.seek(position) ?? Future.value());

  @override
  Future<void> skipToNext() => _remoteMode
      ? (onRemoteNext?.call() ?? Future.value())
      : (_player?.seekToNext() ?? Future.value());

  @override
  Future<void> skipToPrevious() => _remoteMode
      ? (onRemotePrevious?.call() ?? Future.value())
      : (_player?.seekToPrevious() ?? Future.value());

  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    if (name == 'favorite') {
      await onToggleFavorite?.call();
    }
    return super.customAction(name, extras);
  }

  void detach() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _player = null;
  }
}
