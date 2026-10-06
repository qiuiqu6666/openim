import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'data/chat_location_source.dart';

/// Keeps a user's map selection independent of delayed device-location reads.
class ChatLocationPickerController extends ChangeNotifier {
  ChatLocationPickerController({ChatLocationSource? source})
      : _source = source ?? const GeolocatorChatLocationSource();

  final ChatLocationSource _source;
  LatLng? _selected;
  ChatLocationFailure? _failure;
  bool _locating = false, _active = true, _disposed = false;
  int _selectionRevision = 0, _activation = 0, _locationRevision = 0;

  LatLng? get selected => _selected;
  bool get locating => _locating;
  ChatLocationFailure? get failure => _failure;

  /// Counts valid manual selections, including tapping the same point again.
  int get selectionRevision => _selectionRevision;

  /// Each accepted GPS fix is a recenter intent, including the same point.
  int get locationRevision => _locationRevision;
  bool get isActive => _active && !_disposed;

  /// Pauses acceptance of a pending result without starting another read.
  ///
  /// The flight keeps [locating] true until it finishes, so resuming never
  /// overlaps requests. The page chooses when to retry after becoming active.
  /// This changes only the read fence, not the visible selection or failure.
  void setActive(bool active) {
    if (_disposed || _active == active) return;
    _active = active;
    _activation++;
  }

  /// Accepts map coordinates while a device-location request is still running.
  /// Wrapped map longitudes are normalized to the SDK's valid coordinate range.
  void select(LatLng point) {
    if (_disposed || !_active) return;
    if (!_validLatitude(point.latitude) || !point.longitude.isFinite) {
      _failure = ChatLocationFailure.unavailable;
      notifyListeners();
      return;
    }
    final longitude = point.longitude >= -180 && point.longitude <= 180
        ? point.longitude
        : (point.longitude + 180) % 360 - 180;
    _selected = LatLng(point.latitude, longitude);
    _selectionRevision++;
    _failure = null;
    notifyListeners();
  }

  /// Automatic reads never ask for permission and fail without an error banner.
  Future<void> locate({bool requestPermission = true}) async {
    if (_disposed || !_active || _locating) return;
    final activation = _activation;
    final selection = _selectionRevision;
    _locating = true;
    if (requestPermission) _failure = null;
    notifyListeners();
    try {
      final point = await _source.locate(requestPermission: requestPermission);
      if (!_accepts(activation, selection)) return;
      if (point == null) {
        if (requestPermission) _failure = ChatLocationFailure.unavailable;
        return;
      }
      if (!_validLatitude(point.latitude) ||
          !point.longitude.isFinite ||
          point.longitude < -180 ||
          point.longitude > 180) {
        if (requestPermission) _failure = ChatLocationFailure.unavailable;
        return;
      }
      _selected = point;
      _locationRevision++;
      _failure = null;
    } on ChatLocationException catch (error) {
      if (requestPermission && _accepts(activation, selection)) {
        _failure = error.failure;
      }
    } catch (_) {
      if (requestPermission && _accepts(activation, selection)) {
        _failure = ChatLocationFailure.unavailable;
      }
    } finally {
      // Activity/selection changes reject only the result. They still release
      // the flight's busy state, including after returning from the background.
      if (!_disposed) {
        _locating = false;
        notifyListeners();
      }
    }
  }

  bool _accepts(int activation, int selection) =>
      !_disposed &&
      _active &&
      activation == _activation &&
      selection == _selectionRevision;

  static bool _validLatitude(double latitude) =>
      latitude.isFinite && latitude >= -90 && latitude <= 90;

  @override
  void dispose() {
    _disposed = true;
    _active = false;
    _activation++;
    super.dispose();
  }
}
