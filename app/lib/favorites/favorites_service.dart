import 'package:flutter/foundation.dart';
import '../api/api_client.dart';

class FavoritesService extends ChangeNotifier {
  final ApiClient api;
  final Set<int> _ids = {};

  FavoritesService(this.api);

  bool isLiked(int trackId) => _ids.contains(trackId);

  Future<void> load() async {
    if (!api.isLoggedIn) return;
    try {
      final ids = await api.favoriteIds();
      _ids
        ..clear()
        ..addAll(ids);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggle(int trackId) async {
    if (_ids.contains(trackId)) {
      _ids.remove(trackId);
      notifyListeners();
      try {
        await api.removeFavorite(trackId);
      } catch (_) {
        _ids.add(trackId);
        notifyListeners();
      }
    } else {
      _ids.add(trackId);
      notifyListeners();
      try {
        await api.addFavorite(trackId);
      } catch (_) {
        _ids.remove(trackId);
        notifyListeners();
      }
    }
  }
}
