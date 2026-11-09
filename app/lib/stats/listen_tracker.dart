import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

// Measures how long each track actually plays on THIS device and reports it
// to the server as listen events (see server/src/routes/stats.ts).
//
// - Time is measured from the player's position: only small forward steps
//   while playing count, so seeking, buffering stalls and pauses never add
//   listening time.
// - One event = one continuous listen of one track. Changing track, or
//   restarting the same track from the top (repeat-one, "previous"), starts a
//   new event.
// - Events live in a local outbox (SharedPreferences) until the server has
//   them, so offline listening is uploaded later. The open event is uploaded
//   as it grows (same clientId), so a crash loses at most one flush interval.
class ListenTracker {
  final ApiClient api;
  final String Function() deviceName;

  static const _prefsKey = 'listen_outbox_v1';
  static const _flushEvery = Duration(minutes: 1);
  // A single position step larger than this is a seek, not playback.
  static const _maxStep = Duration(seconds: 3);
  static const _minSeconds = 2.0;

  final Map<String, Map<String, dynamic>> _outbox = {};
  _Listen? _cur;
  Duration? _lastPos;
  bool _flushing = false;
  bool _loaded = false;
  Timer? _timer;
  final _rand = Random();

  ListenTracker(this.api, {required this.deviceName}) {
    _load();
    _timer = Timer.periodic(_flushEvery, (_) => flush());
    api.addListener(_onAuthChanged);
  }

  void dispose() {
    _timer?.cancel();
    api.removeListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    if (!api.isLoggedIn) {
      // Listens belong to the account that made them: drop the open one, keep
      // finished ones queued for when the same server is used again.
      _cur = null;
      _lastPos = null;
    } else {
      flush();
    }
  }

  /// The track now loaded in the player (null when nothing is).
  void onTrack(int? trackId) {
    if (_cur?.trackId == trackId) return;
    _close();
    _lastPos = null;
    if (trackId != null) _cur = _Listen(_newId(), trackId, DateTime.now());
  }

  /// Every position update from the player.
  void onPosition(Duration pos, {required bool playing}) {
    final cur = _cur;
    final last = _lastPos;
    _lastPos = pos;
    if (cur == null || last == null) return;
    // Jumped back to the start after real listening: a new listen of the
    // same track (repeat-one, or restarting it).
    if (pos < const Duration(seconds: 2) &&
        last > const Duration(seconds: 10) &&
        cur.seconds >= _minSeconds) {
      final id = cur.trackId;
      _close();
      _cur = _Listen(_newId(), id, DateTime.now());
      return;
    }
    if (!playing) return;
    final step = pos - last;
    if (step > Duration.zero && step <= _maxStep) {
      cur.seconds += step.inMilliseconds / 1000.0;
      // Checkpoint into the outbox every ~15s of listening.
      if (cur.seconds - cur.savedSeconds >= 15) _stage(cur);
    }
  }

  /// Ends the open listen (e.g. playback stopped or the queue was replaced).
  void endCurrent() {
    _close();
    _lastPos = null;
  }

  void _close() {
    final cur = _cur;
    _cur = null;
    if (cur == null) return;
    if (cur.seconds >= _minSeconds) {
      _stage(cur);
      flush();
    }
  }

  void _stage(_Listen l) {
    l.savedSeconds = l.seconds;
    _outbox[l.clientId] = {
      'clientId': l.clientId,
      'trackId': l.trackId,
      'day': _day(l.startedAt),
      'startedAt': l.startedAt.toUtc().toIso8601String(),
      'seconds': double.parse(l.seconds.toStringAsFixed(1)),
      'device': deviceName(),
    };
    _save();
  }

  /// Uploads everything in the outbox. Safe to call any time.
  Future<void> flush() async {
    if (_flushing || !api.isLoggedIn) return;
    if (!_loaded) await _load();
    // Include the open listen so long tracks show up before they finish.
    final cur = _cur;
    if (cur != null &&
        cur.seconds >= _minSeconds &&
        cur.seconds > cur.savedSeconds) {
      _stage(cur);
    }
    if (_outbox.isEmpty) return;
    _flushing = true;
    try {
      final batch = Map.of(_outbox);
      await api.postListens(batch.values.toList());
      // Drop what was sent, unless it grew meanwhile or is still open.
      batch.forEach((id, sent) {
        final now = _outbox[id];
        if (now != null &&
            now['seconds'] == sent['seconds'] &&
            id != _cur?.clientId) {
          _outbox.remove(id);
        }
      });
      await _save();
    } catch (e) {
      debugPrint('listen upload failed (will retry): $e');
    } finally {
      _flushing = false;
    }
  }

  Future<void> _load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        for (final e in (jsonDecode(raw) as List).cast<Map>()) {
          final m = e.cast<String, dynamic>();
          _outbox.putIfAbsent(m['clientId'] as String, () => m);
        }
      }
    } catch (e) {
      debugPrint('listen outbox load failed: $e');
    }
    _loaded = true;
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_outbox.values.toList()));
    } catch (_) {}
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${_rand.nextInt(1 << 32).toRadixString(36)}';

  static String _day(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)}';
  }
}

class _Listen {
  final String clientId;
  final int trackId;
  final DateTime startedAt;
  double seconds = 0;
  double savedSeconds = 0;
  _Listen(this.clientId, this.trackId, this.startedAt);
}
