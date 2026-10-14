import 'dart:async';
import '../location_message/chat_location_message_data.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'chat_location_places_controller.dart';
import 'data/chat_location_place.dart';
import 'native/chat_location_amap_consent.dart';
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
  const ChatLocationPicker(
      {super.key, this.locationSource, this.mapBuilder, this.placeSearch});
  final ChatLocationSource? locationSource;
  final ChatLocationPlaceSearch? placeSearch;
  final ChatLocationMapBuilder? mapBuilder;

  @override
  State<ChatLocationPicker> createState() => _ChatLocationPickerState();
}

class _ChatLocationPickerState extends State<ChatLocationPicker>
    with WidgetsBindingObserver {
  final _description = TextEditingController();
  late final ChatLocationPickerController _controller;
  final _places = ChatLocationPlacesController();
  ChatLocationPlace? _selectedPlace;
  LatLng? _lastPoint;
  int _manualRevision = 0;
  bool _isCurrent = false;
  bool _mapReady = false, _autoTried = false;
  bool _visible = true, _foreground = true, _sending = false;
  int? _settingsSelection;
  bool _settingsResumePending = false;
  ChatLocationMapFailure? _mapFailure;

  bool get _active => mounted && _visible && _foreground && !_sending;

  @override
  void initState() {
    super.initState();
    _controller = ChatLocationPickerController(source: widget.locationSource);
    _controller.addListener(_changed);
    _places.search = widget.placeSearch;
    _places.addListener(_placesChanged);
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
    if (state == AppLifecycleState.resumed && _settingsSelection != null) {
      _settingsResumePending = true;
    }
    _syncActivity();
    if (mounted) setState(() {});
  }

  void _syncActivity() {
    _controller.setActive(_active);
    _places.setActive(_active);
    if (!_active || !_mapReady || _mapFailure != null) return;
    if (_autoTried && !_settingsResumePending) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_active ||
          !_mapReady ||
          _mapFailure != null ||
          _controller.locating) {
        return;
      }
      if (!_autoTried) {
        // Entering the location picker is the user's request to use location.
        // The source prompts only when permission has not already been granted.
        _autoTried = true;
        unawaited(_controller.locate());
      } else if (_settingsResumePending) {
        final selection = _settingsSelection;
        _settingsSelection = null;
        _settingsResumePending = false;
        if (selection != _controller.selectionRevision) return;
        // Service-disabled reads stop before checking permission. Continue
        // that permission flow after settings; other returns stay silent.
        unawaited(_controller.locate(
            requestPermission:
                _controller.failure == ChatLocationFailure.disabled));
      }
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

  void _placesChanged() {
    if (mounted) setState(() {});
  }

  void _changed() {
    if (!mounted) return;
    final point = _controller.selected;
    if (point != _lastPoint) {
      _lastPoint = point;
      _selectedPlace = null;
      _isCurrent = _controller.selectionRevision == _manualRevision;
      _places.update(point: point);
    }
    _manualRevision = _controller.selectionRevision;
    setState(() {});
    _syncActivity();
  }

  void _select(LatLng point) {
    if (!_active) return;
    FocusScope.of(context).unfocus();
    _controller.select(point);
  }

  void _selectPlace(ChatLocationPlace place) {
    if (!_active) return;
    FocusScope.of(context).unfocus();
    _controller.selectPlace(place.point);
    setState(() {
      _selectedPlace = place;
      _isCurrent = false;
    });
  }

  Future<void> _locate() async {
    if (!_active || !_mapReady || _mapFailure != null) return;
    FocusScope.of(context).unfocus();
    await _controller.locate();
  }

  Future<void> _openSettings() async {
    if (!_active || _settingsSelection != null) return;
    _settingsSelection = _controller.selectionRevision;
    final labels = ChatLocationPickerLabels.of(context);
    try {
      final opened = _controller.failure == ChatLocationFailure.disabled
          ? await Geolocator.openLocationSettings()
          : await Geolocator.openAppSettings();
      if (opened) return;
    } catch (_) {}
    _settingsSelection = null;
    _settingsResumePending = false;
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
    _places.setActive(false);
    Navigator.of(context).pop((
      latitude: point.latitude,
      longitude: point.longitude,
      description: ChatLocationMessageData.describe(
          _description.text.isNotEmpty
              ? _description.text
              : (_selectedPlace?.name ?? ''),
          _selectedPlace?.address)
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_changed);
    _controller.dispose();
    _description.dispose();
    _places.removeListener(_placesChanged);
    _places.dispose();
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
            toolbarHeight: ChatLocationPickerTokens.toolbarHeight,
            backgroundColor: surface,
            foregroundColor: AppTokens.textPrimary(dark: dark),
            centerTitle: true,
            leadingWidth: ChatLocationPickerTokens.navActionWidth,
            leading: TextButton(
                key: const ValueKey('chat-location-back'),
                style: TextButton.styleFrom(
                    foregroundColor: AppTokens.textPrimary(dark: dark)),
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(labels.cancel)),
            actions: [
              Padding(
                  padding: const EdgeInsets.only(right: AppTokens.s4),
                  child: FilledButton(
                      key: const ValueKey('chat-location-send'),
                      onPressed: _active &&
                              _mapReady &&
                              _mapFailure == null &&
                              _controller.selected != null
                          ? _send
                          : null,
                      style: FilledButton.styleFrom(
                          backgroundColor: ChatLocationPickerTokens.accent,
                          foregroundColor: AppTokens.onAccent,
                          disabledBackgroundColor: AppTokens.border(dark: dark),
                          disabledForegroundColor:
                              AppTokens.textSecondary(dark: dark),
                          minimumSize: const Size(
                              ChatLocationPickerTokens.actionWidth,
                              ChatLocationPickerTokens.actionHeight),
                          tapTargetSize: MaterialTapTargetSize.padded,
                          visualDensity: VisualDensity.standard,
                          textStyle: const TextStyle(
                              fontSize: ChatLocationPickerTokens.bodySize,
                              fontWeight: FontWeight.w500),
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppTokens.s5),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTokens.rSm))),
                      child: Text(labels.send))),
            ],
            title: Text(labels.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: ChatLocationPickerTokens.titleSize,
                    fontWeight: FontWeight.w600))),
        body: _consentBody(LayoutBuilder(builder: (context, constraints) {
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
              onSearchReady: (search) {
                _places.search = search;
                _places.update(point: _controller.selected);
              },
              onError: (failure) {
                if (mounted) setState(() => _mapFailure = failure);
              });
          final map = ChatLocationMapOverlay(
              map: widget.mapBuilder?.call(context, options) ??
                  ChatLocationNativeMap(
                      options: options, requireConsent: false),
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
              places: _places,
              selectedPlace: _selectedPlace,
              isCurrent: _isCurrent,
              onPlace: _selectPlace);
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
            SizedBox(
                height: constraints.maxHeight *
                    (MediaQuery.textScalerOf(context).scale(1) > 1.3
                        ? ChatLocationPickerTokens.accessiblePanelHeightFraction
                        : ChatLocationPickerTokens.panelHeightFraction),
                child: panel),
          ]);
        })));
  }

  Widget _consentBody(Widget child) {
    if (widget.mapBuilder == null &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      return ChatLocationAmapConsent(child: child);
    }
    return child;
  }
}
