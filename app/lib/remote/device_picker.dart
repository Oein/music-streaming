import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'remote_service.dart';

// Bottom sheet listing all online devices. Selecting one routes playback
// controls to that device; selecting "This device" plays locally.
Future<void> showDevicePicker(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    builder: (context) => Consumer<RemoteService>(
      builder: (context, remote, _) {
        final others =
            remote.devices.where((d) => d.id != remote.deviceId).toList();
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Play on', style: TextStyle(fontSize: 16)),
              ),
              ListTile(
                leading: const Icon(Icons.smartphone),
                title: const Text('This device'),
                trailing: !remote.isRemote ? const Icon(Icons.check) : null,
                onTap: () {
                  remote.setActiveDevice(remote.deviceId);
                  Navigator.pop(context);
                },
              ),
              if (others.isNotEmpty) const Divider(height: 1),
              for (final d in others)
                ListTile(
                  leading: const Icon(Icons.speaker_group),
                  title: Text(d.name),
                  subtitle: d.state?['title'] != null
                      ? Text('Playing: ${d.state!['title']}')
                      : null,
                  trailing: remote.activeDeviceId == d.id
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () {
                    remote.setActiveDevice(d.id);
                    Navigator.pop(context);
                  },
                ),
              if (others.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No other devices online.',
                      style: TextStyle(color: Colors.grey)),
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    ),
  );
}
