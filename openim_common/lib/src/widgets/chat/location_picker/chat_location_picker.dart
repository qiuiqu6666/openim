import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../res/app_tokens.dart';
import '../../liquid_glass_surface.dart';
import 'chat_location_picker_controller.dart';
import 'chat_location_picker_labels.dart';
import 'chat_location_picker_tokens.dart';
import 'data/chat_location_source.dart';
import 'native/chat_location_native_map.dart';
import 'native/chat_location_native_map_options.dart';
import 'widgets/chat_location_map_overlay.dart';
import 'widgets/chat_location_selection_panel.dart';

/// Native map selection returns the existing SDK's WGS84 coordinate record.
class ChatLocationPicker extends StatefulWidget {
  const ChatLocationPicker({super.key, this.locationSource, this.mapBuilder});
  final ChatLocationSource? locationSource;
  final ChatLocationMapBuilder? mapBuilder;

  @override
  State<ChatLocationPicker> createState() => _ChatLocationPickerState();
}

class _ChatLocationPickerState extends State<ChatLocationPicker>
    with WidgetsBindingObserver {
  final _description = TextEditingController();
  late final ChatLocationPickerController _controller;
  bool _mapReady = false, _autoTried = false;
  bool _visible = true, _foreground = true, _sending = false;
  ChatLocationMapFailure? _mapFailure;

  bool get _active => mounted && _visible && _foreground && !_sending;

  @override
  void initState() {
    super.initState();
    _controller = ChatLocationPickerController(source: widget.locationSource);
    _controller.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle != AppLifecycleState.paused &&
        lifecycle != AppLifecycleState.hidden &&
        lifecycle != AppLifecycleState.detached;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = (ModalRoute.isCurrentOf(context) ?? true) &&
        TickerMode.valuesOf(context).enabled;
    _syncActivity();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A native permission prompt may be inactive without leaving the app.
    _foreground = state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.detached;
    _syncActivity();
    if (mounted) setState(() {});
  }

  void _syncActivity() {
    _controller.setActive(_active);
    if (!_active || !_mapReady || _autoTried) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_active || _autoTried) return;
      _autoTried = true;
      unawaited(_controller.locate(requestPermission: false));
    });
  }

  void _onReady() {
    if (!mounted) return;
    setState(() {
      _mapReady = true;
      _mapFailure = null;
    });
    _syncActivity();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
  }

  void _select(LatLng point) {
    if (!_active) return;
    FocusScope.of(context).unfocus();
    _controller.select(point);
  }

  Future<void> _locate() async {
    if (!_active || !_mapReady || _mapFailure != null) return;
    FocusScope.of(context).unfocus();
    await _controller.locate();
  }

  Future<void> _openSettings() async {
    if (!_active) return;
    final labels = ChatLocationPickerLabels.of(context);
    try {
      final opened = _controller.failure == ChatLocationFailure.disabled
          ? await Geolocator.openLocationSettings()
          : await Geolocator.openAppSettings();
      if (opened || !_active) return;
    } catch (_) {
      if (!_active) return;
    }
    if (mounted && _active) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(labels.failure(ChatLocationFailure.unavailable))));
    }
  }

  void _send() {
    final point = _controller.selected;
    if (!_active || _mapFailure != null || point == null) return;
    _sending = true;
    _controller.setActive(false);
    Navigator.of(context).pop((
      latitude: point.latitude,
      longitude: point.longitude,
      description: _description.text.trim()
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_changed);
    _controller.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final labels = ChatLocationPickerLabels.of(context);
    final surface = AppTokens.surface(dark: dark);
    return Scaffold(
        key: const ValueKey('chat-location-picker'),
        backgroundColor: surface,
        appBar: GlassAppBar(
            opaque: true,
            backgroundColor: surface,
            foregroundColor: AppTokens.textPrimary(dark: dark),
            centerTitle: true,
            leading: IconButton(
                key: const ValueKey('chat-location-back'),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                color: AppTokens.accent,
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => Navigator.of(context).maybePop()),
            title: Text(labels.title,
                style: const TextStyle(
                    fontSize: ChatLocationPickerTokens.titleSize,
                    fontWeight: FontWeight.w600))),
        body: LayoutBuilder(builder: (context, constraints) {
          final wide =
              constraints.maxWidth >= ChatLocationPickerTokens.wideBreakpoint &&
                  constraints.maxWidth > constraints.maxHeight;
          final options = ChatLocationNativeMapOptions(
              selected: _controller.selected,
              dark: dark,
              active: _active,
              centerRequest: _controller.locationRevision,
              onSelected: _select,
              onReady: _onReady,
              onError: (failure) {
                if (mounted) setState(() => _mapFailure = failure);
              });
          final map = ChatLocationMapOverlay(
              map: widget.mapBuilder?.call(context, options) ??
                  ChatLocationNativeMap(options: options),
              locating: _controller.locating,
              active: _active && _mapReady && _mapFailure == null,
              failure: _mapFailure,
              onLocate: _locate);
          final panel = ChatLocationSelectionPanel(
              description: _description,
              selected: _controller.selected,
              failure: _controller.failure,
              wide: wide,
              onRetry: !_active || _controller.locating ? null : _locate,
              onSettings: !_active ? null : _openSettings,
              onSend:
                  _active && _mapFailure == null && _controller.selected != null
                      ? _send
                      : null);
          if (wide) {
            return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: map),
                  SizedBox(
                      width: math.min(
                          ChatLocationPickerTokens.widePanelWidth,
                          constraints.maxWidth *
                              ChatLocationPickerTokens.widePanelFraction),
                      child: panel),
                ]);
          }
          return Column(children: [
            Expanded(child: map),
            ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight *
                        ChatLocationPickerTokens.panelHeightFraction),
                child: panel),
          ]);
        }));
  }
}
