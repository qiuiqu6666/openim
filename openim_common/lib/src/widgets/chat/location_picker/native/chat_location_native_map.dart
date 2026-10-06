import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../../../../res/app_tokens.dart';
import '../chat_location_picker_labels.dart';
import '../chat_location_picker_tokens.dart';
import 'chat_location_amap_consent.dart';
import 'chat_location_desktop_map.dart';
import 'chat_location_native_map_options.dart';

/// Mobile map SDKs display/select points; GPS remains owned by the picker.
class ChatLocationNativeMap extends StatelessWidget {
  const ChatLocationNativeMap({super.key, required this.options});
  final ChatLocationNativeMapOptions options;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return ChatLocationDesktopMap(options: options);
    }
    final view = _NativeMapView(options: options);
    return defaultTargetPlatform == TargetPlatform.android
        ? ChatLocationAmapConsent(child: view)
        : view;
  }
}

class _NativeMapView extends StatefulWidget {
  const _NativeMapView({required this.options});
  final ChatLocationNativeMapOptions options;

  @override
  State<_NativeMapView> createState() => _NativeMapViewState();
}

class _NativeMapViewState extends State<_NativeMapView> {
  static const _viewType = 'openim/chat-location-map';
  MethodChannel? _channel;
  ChatLocationMapFailure? _failure;
  bool _ready = false;

  @override
  void didUpdateWidget(covariant _NativeMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final options = widget.options;
    if (options.dark != oldWidget.options.dark) {
      unawaited(_invoke('style', {'dark': options.dark}));
    }
    if (options.active != oldWidget.options.active) {
      unawaited(_invoke('setActive', {'active': options.active}));
    }
    // Only GPS/recenter requests move the map. Echoing a manual selection here
    // would interrupt the native map's pan/deceleration gesture.
    if (options.centerRequest != oldWidget.options.centerRequest) {
      unawaited(_move());
    }
  }

  Future<void> _created(int id) async {
    final channel = MethodChannel('$_viewType/$id');
    _channel = channel;
    channel.setMethodCallHandler(_event);
    await _invoke('style', {'dark': widget.options.dark});
    if (!mounted || _channel != channel) return;
    await _invoke('setActive', {'active': widget.options.active});
    if (!mounted || _channel != channel) return;
    try {
      final status = await channel.invokeMapMethod<String, dynamic>('status');
      if (!mounted || _channel != channel) return;
      if (status?['error'] != null) {
        _failed(status!['error']);
        return;
      }
      await _move();
      if (mounted && _channel == channel && _failure == null) _notifyReady();
    } catch (_) {
      if (mounted && _channel == channel) _failed('unavailable');
    }
  }

  Future<dynamic> _event(MethodCall call) async {
    if (!mounted) return null;
    switch (call.method) {
      case 'onReady':
        // The status handshake reports readiness even if a native callback
        // arrived before Flutter installed its handler.
        break;
      case 'onSelected':
        if (!widget.options.active || _failure != null) return null;
        final values = call.arguments;
        if (values is! Map) return null;
        final latitude = values['latitude'], longitude = values['longitude'];
        if (latitude is! num ||
            longitude is! num ||
            !latitude.isFinite ||
            !longitude.isFinite ||
            latitude < -90 ||
            latitude > 90 ||
            longitude < -180 ||
            longitude > 180) {
          return null;
        }
        widget.options
            .onSelected(LatLng(latitude.toDouble(), longitude.toDouble()));
        break;
      case 'onError':
        final values = call.arguments;
        _failed(values is Map ? values['code'] : 'unavailable');
        break;
    }
    return null;
  }

  void _notifyReady() {
    if (_ready || !mounted) return;
    _ready = true;
    widget.options.onReady();
  }

  Future<void> _invoke(String method, Map<String, dynamic> arguments) async {
    final channel = _channel;
    if (channel == null || _failure != null) return;
    try {
      await channel.invokeMethod<void>(method, arguments);
    } catch (_) {
      if (mounted && _channel == channel) _failed('unavailable');
    }
  }

  Future<void> _move() async {
    final selected = widget.options.selected;
    if (selected != null) {
      await _invoke('move', {
        'latitude': selected.latitude,
        'longitude': selected.longitude,
        'zoom': ChatLocationPickerTokens.selectedZoom
      });
    }
  }

  void _failed(Object? code) {
    if (!mounted || _failure != null) return;
    final failure = code == 'keyMissing'
        ? ChatLocationMapFailure.keyMissing
        : ChatLocationMapFailure.unavailable;
    setState(() => _failure = failure);
    widget.options.onError(failure);
  }

  @override
  void dispose() {
    final channel = _channel;
    _channel = null;
    channel?.setMethodCallHandler(null);
    if (channel != null) {
      unawaited(
          channel.invokeMethod<void>('dispose').catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failure != null) return const _UnavailableMap();
    final point = widget.options.selected;
    final params = <String, dynamic>{
      'dark': widget.options.dark,
      'privacyAgreed': defaultTargetPlatform == TargetPlatform.android,
      if (point != null) 'latitude': point.latitude,
      if (point != null) 'longitude': point.longitude
    };
    return defaultTargetPlatform == TargetPlatform.android
        ? AndroidView(
            viewType: _viewType,
            creationParams: params,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _created)
        : UiKitView(
            viewType: _viewType,
            creationParams: params,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _created);
  }
}

class _UnavailableMap extends StatelessWidget {
  const _UnavailableMap();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final labels = ChatLocationPickerLabels.of(context);
    return ColoredBox(
        color: AppTokens.background(dark: dark),
        child: Center(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppTokens.s7),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.map_outlined,
                      size: ChatLocationPickerTokens.emptyIconSize,
                      color: AppTokens.textSecondary(dark: dark)),
                  const SizedBox(height: AppTokens.s4),
                  Text(labels.mapUnavailable,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: ChatLocationPickerTokens.headingSize,
                          color: AppTokens.textPrimary(dark: dark))),
                  const SizedBox(height: AppTokens.s3),
                  Text(labels.mapUnavailableHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: ChatLocationPickerTokens.captionSize,
                          color: AppTokens.textSecondary(dark: dark))),
                ]))));
  }
}
