import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../res/app_tokens.dart';
import '../chat_location_picker_tokens.dart';
import 'chat_location_native_map_options.dart';

/// Preserve the existing web/desktop map without loading a mobile SDK.
class ChatLocationDesktopMap extends StatefulWidget {
  const ChatLocationDesktopMap({super.key, required this.options});
  final ChatLocationNativeMapOptions options;

  @override
  State<ChatLocationDesktopMap> createState() => _ChatLocationDesktopMapState();
}

class _ChatLocationDesktopMapState extends State<ChatLocationDesktopMap> {
  final _map = MapController();
  bool _ready = false;

  @override
  void didUpdateWidget(covariant ChatLocationDesktopMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ready &&
        widget.options.centerRequest != oldWidget.options.centerRequest &&
        widget.options.selected != null) {
      _map.move(
          widget.options.selected!, ChatLocationPickerTokens.selectedZoom);
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    return FlutterMap(
        mapController: _map,
        options: MapOptions(
            initialCenter: options.selected ?? const LatLng(0, 0),
            initialZoom: options.selected == null
                ? 2
                : ChatLocationPickerTokens.selectedZoom,
            onMapReady: () {
              _ready = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) widget.options.onReady();
              });
            },
            interactionOptions: InteractionOptions(
                flags: options.active
                    ? InteractiveFlag.all & ~InteractiveFlag.rotate
                    : InteractiveFlag.none),
            onTap: (_, point) {
              if (options.active) options.onSelected(point);
            },
            onPositionChanged: (camera, gesture) {
              if (gesture && options.active) options.onSelected(camera.center);
            }),
        children: [
          TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'io.openim.flutter.demo'),
          if (options.selected != null)
            MarkerLayer(markers: [
              Marker(
                  point: options.selected!,
                  width: ChatLocationPickerTokens.emptyIconSize,
                  height: ChatLocationPickerTokens.emptyIconSize,
                  alignment: Alignment.topCenter,
                  child: const Icon(Icons.location_on_rounded,
                      color: AppTokens.accent,
                      size: ChatLocationPickerTokens.emptyIconSize))
            ]),
          RichAttributionWidget(attributions: [
            TextSourceAttribution('OpenStreetMap contributors',
                onTap: () => unawaited(launchUrl(
                    Uri.parse('https://www.openstreetmap.org/copyright'),
                    mode: LaunchMode.externalApplication)))
          ]),
        ]);
  }
}
