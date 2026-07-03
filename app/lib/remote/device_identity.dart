import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// A stable per-install device id plus a human-friendly name for the picker.
class DeviceIdentity {
  final String id;
  final String name;
  DeviceIdentity(this.id, this.name);

  static const _storage = FlutterSecureStorage();

  static Future<DeviceIdentity> load() async {
    // Secure storage can fail (e.g. missing macOS keychain entitlement).
    // Never let that crash startup — fall back to a fresh per-launch id.
    String? id;
    try {
      id = await _storage.read(key: 'deviceId');
    } catch (_) {
      id = null;
    }
    if (id == null) {
      // Random-ish stable id from current microseconds + platform.
      id = '${defaultTargetPlatform.name}-'
          '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
      try {
        await _storage.write(key: 'deviceId', value: id);
      } catch (_) {
        /* non-persistent this session */
      }
    }
    return DeviceIdentity(id, _defaultName());
  }

  static String _defaultName() {
    if (kIsWeb) return 'Web browser';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android device';
      case TargetPlatform.iOS:
        return 'iPhone / iPad';
      case TargetPlatform.macOS:
        return 'Mac';
      default:
        return 'Device';
    }
  }
}
