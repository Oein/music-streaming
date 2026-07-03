import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../api/api_client.dart';
import '../settings/settings_service.dart';

class AudioCacheService extends ChangeNotifier {
  final ApiClient api;
  final SettingsService settings;
  late Directory _cacheDir;
  bool _ready = false;

  // trackId → play count (persisted in _metaFile)
  final Map<int, int> _playCounts = {};
  // trackId → file size in bytes
  final Map<int, int> _fileSizes = {};
  // trackId → last access timestamp (ms)
  final Map<int, int> _lastAccess = {};
  // tracks explicitly downloaded for offline (never auto-evicted)
  final Set<int> _offline = {};

  AudioCacheService(this.api, this.settings);

  bool get ready => _ready;
  bool isOffline(int trackId) => _offline.contains(trackId);
  bool isCached(int trackId) => _fileSizes.containsKey(trackId);
  int getPlayCount(int trackId) => _playCounts[trackId] ?? 0;

  int get cacheSizeBytes => _fileSizes.values.fold(0, (a, b) => a + b);
  double get cacheSizeMB => cacheSizeBytes / (1024 * 1024);

  File _fileFor(int trackId) => File('${_cacheDir.path}/$trackId.audio');
  File get _metaFile => File('${_cacheDir.path}/_meta.json');

  Future<void> init() async {
    if (kIsWeb) {
      _ready = true;
      return;
    }
    try {
      final appDir = await getApplicationSupportDirectory();
      _cacheDir = Directory('${appDir.path}/audio_cache');
      if (!_cacheDir.existsSync()) _cacheDir.createSync(recursive: true);
      await _loadMeta();
    } catch (_) {}
    _ready = true;
    notifyListeners();
  }

  Future<void> _loadMeta() async {
    try {
      if (_metaFile.existsSync()) {
        final j =
            jsonDecode(await _metaFile.readAsString()) as Map<String, dynamic>;
        final counts = j['playCounts'] as Map<String, dynamic>? ?? {};
        final access = j['lastAccess'] as Map<String, dynamic>? ?? {};
        final offline = j['offline'] as List? ?? [];
        for (final e in counts.entries) {
          _playCounts[int.parse(e.key)] = e.value as int;
        }
        for (final e in access.entries) {
          _lastAccess[int.parse(e.key)] = e.value as int;
        }
        for (final id in offline) {
          _offline.add(id as int);
        }
      }
    } catch (_) {}
    // Rebuild file sizes from disk
    _fileSizes.clear();
    if (_cacheDir.existsSync()) {
      for (final f in _cacheDir.listSync()) {
        if (f is File && f.path.endsWith('.audio')) {
          final name = f.uri.pathSegments.last.replaceAll('.audio', '');
          final id = int.tryParse(name);
          if (id != null) _fileSizes[id] = f.lengthSync();
        }
      }
    }
  }

  Future<void> _saveMeta() async {
    try {
      await _metaFile.writeAsString(jsonEncode({
        'playCounts': _playCounts.map((k, v) => MapEntry(k.toString(), v)),
        'lastAccess': _lastAccess.map((k, v) => MapEntry(k.toString(), v)),
        'offline': _offline.toList(),
      }));
    } catch (_) {}
  }

  void recordPlay(int trackId) {
    _playCounts[trackId] = (_playCounts[trackId] ?? 0) + 1;
    _lastAccess[trackId] = DateTime.now().millisecondsSinceEpoch;
    _saveMeta();
  }

  /// Returns a local file URI if cached, otherwise downloads and caches.
  Future<Uri> getOrFetch(int trackId) async {
    if (kIsWeb || !_ready) return api.streamUri(trackId);

    final file = _fileFor(trackId);
    if (file.existsSync()) {
      _lastAccess[trackId] = DateTime.now().millisecondsSinceEpoch;
      return file.uri;
    }

    // Download
    try {
      final uri = api.streamUri(trackId);
      final request = await HttpClient().getUrl(uri);
      final response = await request.close();
      final bytes = await consolidateHttpClientResponseBytes(response);
      await file.writeAsBytes(bytes);
      _fileSizes[trackId] = bytes.length;
      _lastAccess[trackId] = DateTime.now().millisecondsSinceEpoch;
      await _saveMeta();
      notifyListeners();
      await _evictIfNeeded();
      return file.uri;
    } catch (_) {
      return api.streamUri(trackId);
    }
  }

  /// Explicitly download a track for offline use.
  Future<void> downloadOffline(int trackId) async {
    if (kIsWeb || !_ready) return;
    _offline.add(trackId);
    await getOrFetch(trackId);
    await _saveMeta();
    notifyListeners();
  }

  /// Remove offline flag (track may still be in cache but can be evicted).
  Future<void> removeOffline(int trackId) async {
    _offline.remove(trackId);
    await _saveMeta();
    notifyListeners();
  }

  Future<void> _evictIfNeeded() async {
    final maxBytes = settings.maxCacheMB * 1024 * 1024;
    if (cacheSizeBytes <= maxBytes) return;

    // Build eviction candidates: cached but NOT offline
    final candidates =
        _fileSizes.keys.where((id) => !_offline.contains(id)).toList();

    // Sort by score: lower play count + older access → evict first
    candidates.sort((a, b) {
      final scoreA =
          (_playCounts[a] ?? 0) * 1000 + (_lastAccess[a] ?? 0) ~/ 1000000;
      final scoreB =
          (_playCounts[b] ?? 0) * 1000 + (_lastAccess[b] ?? 0) ~/ 1000000;
      return scoreA.compareTo(scoreB);
    });

    for (final id in candidates) {
      if (cacheSizeBytes <= maxBytes) break;
      final file = _fileFor(id);
      if (file.existsSync()) {
        await file.delete();
        _fileSizes.remove(id);
      }
    }
    notifyListeners();
  }

  Future<void> clearCache() async {
    if (kIsWeb || !_ready) return;
    for (final id in _fileSizes.keys.toList()) {
      final file = _fileFor(id);
      if (file.existsSync()) await file.delete();
    }
    _fileSizes.clear();
    _offline.clear();
    _playCounts.clear();
    _lastAccess.clear();
    await _saveMeta();
    notifyListeners();
  }
}
