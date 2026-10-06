import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

enum ChatLocationMapFailure { unavailable, unsupported, keyMissing }

/// All coordinates crossing the native-map boundary use WGS84.
class ChatLocationNativeMapOptions {
  const ChatLocationNativeMapOptions({
    required this.selected,
    required this.dark,
    required this.active,
    required this.centerRequest,
    required this.onSelected,
    required this.onReady,
    required this.onError,
  });

  final LatLng? selected;
  final bool dark, active;
  final int centerRequest;
  final ValueChanged<LatLng> onSelected;
  final VoidCallback onReady;
  final ValueChanged<ChatLocationMapFailure> onError;
}

typedef ChatLocationMapBuilder = Widget Function(
    BuildContext context, ChatLocationNativeMapOptions options);
