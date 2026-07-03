// Browser MediaSession bridge. On web this wires the OS/browser media controls
// (notification, lock screen, media keys, Bluetooth buttons) to the player; on
// every other platform these are no-ops (audio_service handles native).
export 'media_session_stub.dart'
    if (dart.library.js_interop) 'media_session_web.dart';
