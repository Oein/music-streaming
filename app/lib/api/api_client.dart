import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

// Formats each platform can decode natively. Sent to the server so it only
// transcodes what this client can't play. Anything not listed → server sends
// transcoded AAC.
Set<String> _clientCanPlay() {
  if (kIsWeb) {
    // Most browsers: mp3, wav, m4a/aac, ogg. FLAC support is spotty in Safari.
    return {'mp3', 'wav', 'm4a', 'ogg'};
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.macOS:
      return {'mp3', 'wav', 'm4a', 'flac'};
    case TargetPlatform.iOS:
      return {'mp3', 'wav', 'm4a', 'flac'};
    case TargetPlatform.android:
      // Android supports all of these via ExoPlayer.
      return {'mp3', 'wav', 'm4a', 'ogg', 'flac'};
    default:
      return {'mp3', 'wav', 'm4a'};
  }
}

class ApiClient extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  String? _baseUrl;
  String? _token;

  String? get baseUrl => _baseUrl;
  String? get token => _token;
  bool get isLoggedIn => _token != null && _baseUrl != null;

  Future<String?> _read(String key) async {
    try {
      final v = await _storage.read(key: key);
      if (v != null) return v;
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('auth_$key');
    } catch (_) {}
    return null;
  }

  Future<void> _write(String key, String? value) async {
    try {
      if (value == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove('auth_$key');
      } else {
        await prefs.setString('auth_$key', value);
      }
    } catch (_) {}
  }

  Future<void> loadSession() async {
    _baseUrl = await _read('baseUrl');
    _token = await _read('token');
    notifyListeners();
  }

  Future<void> login(String baseUrl, String username, String password) async {
    final normalized = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final res = await http.post(
      Uri.parse('$normalized/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (res.statusCode != 200) {
      throw Exception('Login failed (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    _baseUrl = normalized;
    _token = data['token'] as String;
    await _write('baseUrl', _baseUrl);
    await _write('token', _token);
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    await _write('token', null);
    notifyListeners();
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<dynamic> _get(String path) async {
    final res = await http.get(Uri.parse('$_baseUrl$path'), headers: _headers);
    if (res.statusCode == 401) {
      await logout();
      throw Exception('Session expired');
    }
    if (res.statusCode != 200)
      throw Exception('GET $path -> ${res.statusCode}');
    return jsonDecode(res.body);
  }

  Future<dynamic> _send(String method, String path, [Object? body]) async {
    final req = http.Request(method, Uri.parse('$_baseUrl$path'))
      ..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode >= 400)
      throw Exception('$method $path -> ${res.statusCode}');
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  // --- Library ---
  Future<List<Album>> albums() async => (await _get('/api/albums') as List)
      .map((e) => Album.fromJson(e))
      .toList();

  Future<List<Track>> albumTracks(int albumId) async {
    final data = await _get('/api/albums/$albumId') as Map<String, dynamic>;
    return (data['tracks'] as List).map((e) => Track.fromJson(e)).toList();
  }

  Future<List<Track>> searchTracks(String q) async =>
      (await _get('/api/tracks?q=${Uri.encodeQueryComponent(q)}') as List)
          .map((e) => Track.fromJson(e))
          .toList();

  // --- Playlists ---
  Future<List<Playlist>> playlists() async =>
      (await _get('/api/playlists') as List)
          .map((e) => Playlist.fromJson(e))
          .toList();

  Future<List<Track>> playlistTracks(int id) async {
    final data = await _get('/api/playlists/$id') as Map<String, dynamic>;
    return (data['tracks'] as List).map((e) => Track.fromJson(e)).toList();
  }

  Future<Playlist> createPlaylist(String name) async =>
      Playlist.fromJson(await _send('POST', '/api/playlists', {'name': name}));

  Future<void> deletePlaylist(int id) => _send('DELETE', '/api/playlists/$id');

  Future<void> addToPlaylist(int playlistId, int trackId) =>
      _send('POST', '/api/playlists/$playlistId/tracks', {'trackId': trackId});

  Future<void> reorderPlaylist(int playlistId, List<int> trackIds) =>
      _send('PUT', '/api/playlists/$playlistId/tracks', {'trackIds': trackIds});

  // --- Prewarm ---
  // Ask the server to transcode-and-cache these tracks ahead of playback so the
  // first play is instant. Fire-and-forget: failures are ignored (playback
  // still works via on-demand transcode).
  Future<void> prewarm(List<int> ids) async {
    if (ids.isEmpty || !isLoggedIn) return;
    try {
      await _send('POST', '/api/prewarm', {'ids': ids});
    } catch (_) {
      /* best-effort */
    }
  }

  // --- Favorites ---
  Future<List<int>> favoriteIds() async =>
      (await _get('/api/favorites/ids') as List).cast<int>();

  Future<List<Track>> favoriteTracks() async =>
      (await _get('/api/favorites') as List)
          .map((e) => Track.fromJson(e))
          .toList();

  Future<void> addFavorite(int trackId) =>
      _send('POST', '/api/favorites/$trackId');

  Future<void> removeFavorite(int trackId) =>
      _send('DELETE', '/api/favorites/$trackId');

  // --- Media URLs ---
  // Optional [size] requests a square WebP thumbnail (smaller transfer for
  // list/search views); omit for the full-resolution cover.
  String coverUrl(int? coverArtId, {int? size}) {
    if (coverArtId == null) return '';
    final sizeParam = size != null ? '&size=$size' : '';
    return '$_baseUrl/api/cover/$coverArtId?token=$_token$sizeParam';
  }

  // When true, advertise only already-lossy formats so the server transcodes
  // lossless sources (flac/wav/ogg) to AAC — a user setting to trade quality for
  // smaller, smoother, cached, seekable playback. Kept in sync by PlayerService.
  bool preferAac = false;

  // Stream URL includes token (query) so native players can authenticate,
  // and canPlay so the server knows whether to transcode.
  Uri streamUri(int trackId) {
    final formats = preferAac ? const {'mp3', 'm4a'} : _clientCanPlay();
    final canPlay = formats.join(',');
    return Uri.parse(
        '$_baseUrl/api/stream/$trackId?token=$_token&canPlay=$canPlay');
  }
}
