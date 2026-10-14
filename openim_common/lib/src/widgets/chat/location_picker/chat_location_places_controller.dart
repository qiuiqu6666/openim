import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'data/chat_location_place.dart';

/// Debounces typing/panning and rejects replies from an old query or route.
class ChatLocationPlacesController extends ChangeNotifier {
  ChatLocationPlaceSearch? search;
  List<ChatLocationPlace> places = const [];
  bool loading = false, failed = false;
  String query = '';
  LatLng? center;
  Timer? _timer;
  int _revision = 0;
  bool _disposed = false, _active = true;

  void update({String? text, LatLng? point}) {
    if (_disposed) return;
    query = text ?? query;
    center = point ?? center;
    _schedule();
  }

  void setActive(bool active) {
    if (_disposed || _active == active) return;
    _active = active;
    _revision++;
    _timer?.cancel();
    loading = false;
    if (active) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final revision = ++_revision;
    places = const [];
    failed = false;
    loading = _active &&
        search != null &&
        (center != null || query.trim().isNotEmpty);
    notifyListeners();
    if (!loading) return;
    _timer = Timer(const Duration(milliseconds: 350), () async {
      try {
        final result = await search!(query.trim(), center);
        if (_disposed || revision != _revision || !_active) return;
        places = result;
      } catch (_) {
        if (_disposed || revision != _revision || !_active) return;
        failed = true;
      }
      if (_disposed || revision != _revision || !_active) return;
      loading = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _timer?.cancel();
    super.dispose();
  }
}
