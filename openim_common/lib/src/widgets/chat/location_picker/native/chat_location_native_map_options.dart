import 'package:flutter/widgets.dart';
import 'dart:typed_data';
import 'package:latlong2/latlong.dart';
import '../data/chat_location_place.dart';

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
    this.onSearchReady,
    this.readOnly = false,
    this.onSnapshot,
  });

  final LatLng? selected;
  final bool dark, active;
  final bool readOnly;
  final ValueChanged<Uint8List>? onSnapshot;
  final int centerRequest;
  final ValueChanged<LatLng> onSelected;
  final VoidCallback onReady;
  final ValueChanged<ChatLocationMapFailure> onError;
  final ValueChanged<ChatLocationPlaceSearch>? onSearchReady;
}

typedef ChatLocationMapBuilder = Widget Function(
    BuildContext context, ChatLocationNativeMapOptions options);
