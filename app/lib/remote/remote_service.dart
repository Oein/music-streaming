import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../api/api_client.dart';

class RemoteDevice {
  final String id;
  final String name;
  final Map<String, dynamic>? state;
  RemoteDevice(this.id, this.name, this.state);
}

// Handles the WebSocket connection to the server hub. Two roles at once:
//  1. Playback device — receives commands and drives the local player.
//  2. Controller — sends commands to another device and shows its state.
//
// PlayerService attaches callbacks so incoming commands drive local playback,
// and calls [sendCommand]/[broadcastState] when this device is being remoted.
class RemoteService extends ChangeNotifier {
  final ApiClient api;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  String deviceId = '';
  String deviceName = 'Device';

  List<RemoteDevice> devices = [];
  // Which device playback is targeted at. Defaults to this device (local).
  String _activeDeviceId = '';

  // Command handler installed by PlayerService (executes on THIS device).
  void Function(String command, Map<String, dynamic>? payload)? onCommand;
  // Latest playback state reported by the active REMOTE device.
  Map<String, dynamic>? remoteState;

  RemoteService(this.api) {
    // Drop the hub connection when the user logs out.
    api.addListener(() {
      if (!api.isLoggedIn) {
        _sub?.cancel();
        _channel?.sink.close();
        _channel = null;
        deviceId = '';
        devices = [];
        remoteState = null;
        notifyListeners();
      }
    });
  }

  bool get isRemote =>
      _activeDeviceId.isNotEmpty && _activeDeviceId != deviceId;
  String get activeDeviceId =>
      _activeDeviceId.isEmpty ? deviceId : _activeDeviceId;

  String get activeDeviceName {
    if (!isRemote) return 'This device';
    final d = devices.where((d) => d.id == _activeDeviceId);
    return d.isEmpty ? 'Remote device' : d.first.name;
  }

  Future<void> connect(String deviceId, String deviceName) async {
    this.deviceId = deviceId;
    this.deviceName = deviceName;
    _activeDeviceId = deviceId;

    final base = api.baseUrl!.replaceFirst(RegExp(r'^http'), 'ws');
    final uri = Uri.parse('$base/ws?token=${api.token}');
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;
    _sub = channel.stream.listen(_onMessage, onDone: _reconnectLater);

    _send({'type': 'hello', 'deviceId': deviceId, 'deviceName': deviceName});
  }

  void _onMessage(dynamic raw) {
    final msg = jsonDecode(raw as String) as Map<String, dynamic>;
    switch (msg['type']) {
      case 'devices':
        devices = (msg['devices'] as List)
            .map((d) => RemoteDevice(d['id'] as String, d['name'] as String,
                (d['state'] as Map?)?.cast<String, dynamic>()))
            .toList();
        notifyListeners();
        break;
      case 'command':
        // Someone is controlling THIS device.
        onCommand?.call(msg['command'] as String,
            (msg['payload'] as Map?)?.cast<String, dynamic>());
        break;
      case 'state':
        // A device reported its state; keep it if it's our active target.
        // MERGE (not replace) so lightweight frequent updates (position, etc.)
        // don't erase the occasionally-sent full queue.
        if (msg['from'] == _activeDeviceId) {
          final incoming = (msg['state'] as Map).cast<String, dynamic>();
          remoteState = {...?remoteState, ...incoming};
          notifyListeners();
        }
        break;
    }
  }

  void setActiveDevice(String id) {
    _activeDeviceId = id;
    remoteState = null;
    // Seed remoteState from the last-known device state if available.
    final d = devices.where((d) => d.id == id);
    if (d.isNotEmpty) remoteState = d.first.state;
    notifyListeners();
  }

  // Controller → target device.
  void sendCommand(String command, [Map<String, dynamic>? payload]) {
    _send({
      'type': 'command',
      'target': _activeDeviceId,
      'command': command,
      'payload': payload,
    });
  }

  // Device → hub: report local playback state so controllers can display it.
  void broadcastState(Map<String, dynamic> state) {
    _send({'type': 'state', 'state': state});
  }

  void _send(Map<String, dynamic> msg) {
    _channel?.sink.add(jsonEncode(msg));
  }

  void _reconnectLater() {
    _sub?.cancel();
    _channel = null;
    Future.delayed(const Duration(seconds: 3), () {
      if (api.isLoggedIn && deviceId.isNotEmpty) {
        connect(deviceId, deviceName);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}
