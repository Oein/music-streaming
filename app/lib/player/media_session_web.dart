// Web implementation of the MediaSession bridge using the browser's
// navigator.mediaSession API (via dart:js_interop). Feature-detected and fully
// guarded so unsupported browsers just no-op.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('globalThis')
external JSObject get _global;

JSObject? get _ms {
  try {
    if (!_global.has('navigator')) return null;
    final nav = _global.getProperty<JSObject>('navigator'.toJS);
    if (!nav.has('mediaSession')) return null;
    return nav.getProperty<JSObject>('mediaSession'.toJS);
  } catch (_) {
    return null;
  }
}

void initMediaSession({
  required void Function() onPlay,
  required void Function() onPause,
  required void Function() onNext,
  required void Function() onPrevious,
  required void Function(Duration position) onSeek,
}) {
  final ms = _ms;
  if (ms == null) return;
  void set(String action, JSFunction handler) {
    try {
      ms.callMethod('setActionHandler'.toJS, action.toJS, handler);
    } catch (_) {
      /* action unsupported by this browser */
    }
  }

  set('play', ((JSObject _) => onPlay()).toJS);
  set('pause', ((JSObject _) => onPause()).toJS);
  set('previoustrack', ((JSObject _) => onPrevious()).toJS);
  set('nexttrack', ((JSObject _) => onNext()).toJS);
  set(
      'seekto',
      ((JSObject details) {
        try {
          final t = details.getProperty<JSNumber?>('seekTime'.toJS);
          if (t != null) {
            onSeek(Duration(milliseconds: (t.toDartDouble * 1000).round()));
          }
        } catch (_) {}
      }).toJS);
}

void setMediaMetadata({
  required String title,
  String? artist,
  String? album,
  String? artworkUrl,
}) {
  final ms = _ms;
  if (ms == null) return;
  try {
    final init = JSObject();
    init.setProperty('title'.toJS, title.toJS);
    if (artist != null) init.setProperty('artist'.toJS, artist.toJS);
    if (album != null) init.setProperty('album'.toJS, album.toJS);
    if (artworkUrl != null) {
      final img = JSObject();
      img.setProperty('src'.toJS, artworkUrl.toJS);
      img.setProperty('sizes'.toJS, '512x512'.toJS);
      img.setProperty('type'.toJS, 'image/jpeg'.toJS);
      init.setProperty('artwork'.toJS, <JSAny>[img].toJS);
    }
    final ctor = _global.getProperty<JSFunction>('MediaMetadata'.toJS);
    final meta = ctor.callAsConstructor<JSObject>(init);
    ms.setProperty('metadata'.toJS, meta);
  } catch (_) {}
}

void setMediaPlaybackState({required bool playing}) {
  final ms = _ms;
  if (ms == null) return;
  try {
    ms.setProperty('playbackState'.toJS, (playing ? 'playing' : 'paused').toJS);
  } catch (_) {}
}

void setMediaPositionState({
  Duration? duration,
  required Duration position,
  double speed = 1.0,
}) {
  final ms = _ms;
  if (ms == null) return;
  try {
    final durS = (duration?.inMilliseconds ?? 0) / 1000.0;
    if (durS <= 0) return; // setPositionState requires a positive duration
    var posS = position.inMilliseconds / 1000.0;
    if (posS < 0) posS = 0;
    if (posS > durS) posS = durS;
    final init = JSObject();
    init.setProperty('duration'.toJS, durS.toJS);
    init.setProperty('playbackRate'.toJS, (speed == 0 ? 1.0 : speed).toJS);
    init.setProperty('position'.toJS, posS.toJS);
    ms.callMethod('setPositionState'.toJS, init);
  } catch (_) {}
}
