import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_launcher/map_launcher.dart';
import '../../../res/app_tokens.dart';
import '../../navigation_glass_controller.dart';
import '../location_picker/chat_location_picker_labels.dart';
import '../location_picker/data/chat_location_source.dart';
import '../location_picker/native/chat_location_native_map.dart';
import '../location_picker/native/chat_location_native_map_options.dart';
import 'chat_location_message_data.dart';
import 'detail/chat_location_detail_actions.dart';
import 'detail/chat_location_maps_sheet.dart';
import 'detail/chat_location_address_source.dart';
import 'weather/chat_location_weather_chip.dart';
import 'detail/chat_location_detail_chrome.dart';
import 'detail/chat_location_detail_labels.dart';
import 'detail/chat_location_detail_tokens.dart';

/// Each visit locates the viewer once without changing the shared point.
class ChatLocationDetailPage extends StatefulWidget {
  const ChatLocationDetailPage(
      {super.key,
      required this.data,
      this.mapBuilder,
      this.actions = const ChatLocationDetailActions(),
      this.addressSource = const ChatLocationAddressSource(),
      this.locationSource = const GeolocatorChatLocationSource()});
  final ChatLocationMessageData data;
  final ChatLocationMapBuilder? mapBuilder;
  final ChatLocationDetailActions actions;
  final ChatLocationAddressSource addressSource;
  final ChatLocationSource locationSource;
  @override
  State<ChatLocationDetailPage> createState() => _ChatLocationDetailPageState();
}

class _ChatLocationDetailPageState extends State<ChatLocationDetailPage>
    with WidgetsBindingObserver {
  bool _foreground = true,
      _ready = false,
      _busy = false,
      _locating = false,
      _satellite = false,
      _supportsSatellite = false;
  bool _addressRequested = false,
      _addressLoading = false,
      _addressFailed = false;
  ChatLocationAddress? _address;
  ChatLocationMessageData get _displayData => _address == null
      ? widget.data
      : ChatLocationMessageData(
          name: widget.data.name.isEmpty ||
                  const {'位置', '位置資訊', 'Location', 'location'}
                      .contains(widget.data.name)
              ? (_address!.name.isEmpty ? widget.data.name : _address!.name)
              : widget.data.name,
          address: _address!.address,
          point: widget.data.point);
  Future<void> _resolveAddress() async {
    final point = widget.data.point;
    if (point == null ||
        widget.data.address.trim().isNotEmpty ||
        _addressLoading) {
      return;
    }
    setState(() {
      _addressRequested = true;
      _addressLoading = true;
      _addressFailed = false;
    });
    try {
      final address = await widget.addressSource.resolve(
          point,
          (Localizations.maybeLocaleOf(context) ??
                  Get.locale ??
                  const Locale('zh', 'CN'))
              .toLanguageTag());
      if (!mounted) return;
      setState(() => _address = address);
    } catch (_) {
      if (mounted) setState(() => _addressFailed = true);
    } finally {
      if (mounted) setState(() => _addressLoading = false);
    }
  }

  bool _automaticLocationStarted = false;
  int _center = 0;
  LatLng? _camera, _user;
  final _shareKey = GlobalKey();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(NavigationGlassController.instance
        .initializeRenderer(preferLiquid: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => _foreground = state == AppLifecycleState.resumed ||
          state == AppLifecycleState.inactive);
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) _message(ChatLocationDetailLabels.of(context).failed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() => _run(() async {
        final box = _shareKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) return;
        await widget.actions
            .share(_displayData, box.localToGlobal(Offset.zero) & box.size);
      });
  Future<void> _directions() => _run(() async {
        List<AvailableMap> maps;
        try {
          maps = await widget.actions.installedMaps();
        } catch (_) {
          maps = [];
        }
        if (!mounted) return;
        final selection = await showModalBottomSheet<int>(
            context: context,
            useSafeArea: true,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => ChatLocationMapsSheet(maps: maps));
        if (!mounted || selection == null) return;
        await widget.actions
            .directions(_displayData, selection < 0 ? null : maps[selection]);
      });
  Future<void> _locate({bool automatic = false}) async {
    if (_locating) return;
    final initialCenter = _center;
    setState(() => _locating = true);
    try {
      final point = await widget.locationSource.locate(requestPermission: true);
      if (!mounted) return;
      if (point == null) {
        throw const ChatLocationException(ChatLocationFailure.unavailable);
      }
      setState(() {
        _user = point;
        if (!automatic || _center == initialCenter) {
          _camera = point;
          _center++;
        }
      });
    } catch (error) {
      if (!mounted) return;
      final labels = ChatLocationPickerLabels.of(context);
      final failure = error is ChatLocationException
          ? error.failure
          : ChatLocationFailure.unavailable;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ChatLocationDetailLabels.of(context).locationDenied),
          action: failure == ChatLocationFailure.deniedForever ||
                  failure == ChatLocationFailure.disabled
              ? SnackBarAction(
                  label: labels.settings,
                  onPressed: () async {
                    try {
                      if (failure == ChatLocationFailure.disabled) {
                        await Geolocator.openLocationSettings();
                      } else {
                        await Geolocator.openAppSettings();
                      }
                    } catch (_) {
                      if (mounted) {
                        _message(ChatLocationDetailLabels.of(context).failed);
                      }
                    }
                  })
              : null));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _layers() async {
    final labels = ChatLocationDetailLabels.of(context);
    final value = await showModalBottomSheet<bool>(
        context: context,
        useSafeArea: true,
        builder: (context) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  title: Text(labels.standard),
                  leading: const Icon(Icons.map_outlined),
                  trailing: !_satellite ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(context, false)),
              ListTile(
                  title: Text(labels.satellite),
                  leading: const Icon(Icons.satellite_alt),
                  trailing: _satellite ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(context, true)),
            ])));
    if (mounted && value != null) setState(() => _satellite = value);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final labels = ChatLocationDetailLabels.of(context);
    final picker = ChatLocationPickerLabels.of(context);
    final data = _displayData;
    final title = data.name.isEmpty ? 'location'.tr : data.name;
    final active = _foreground &&
        (ModalRoute.isCurrentOf(context) ?? true) &&
        TickerMode.valuesOf(context).enabled;
    return AnnotatedRegion<SystemUiOverlayStyle>(
        value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Scaffold(
            key: const ValueKey('chat-location-detail'),
            backgroundColor: AppTokens.surface(dark: dark),
            body: LayoutBuilder(builder: (context, constraints) {
              final safe = MediaQuery.paddingOf(context);
              final scale = MediaQuery.textScalerOf(context);
              final cardHeight = (AppTokens.s8 +
                      ChatLocationDetailTokens.buttonHeight +
                      AppTokens.s5 +
                      scale.scale(ChatLocationDetailTokens.titleSize) * 2.5 +
                      (data.address.isEmpty && !_addressRequested
                          ? 0
                          : scale.scale(ChatLocationDetailTokens.addressSize) *
                                  2.5 +
                              AppTokens.s2))
                  .clamp(0.0, constraints.maxHeight * .45);
              final bottom = cardHeight + safe.bottom + AppTokens.s7;
              final options = ChatLocationNativeMapOptions(
                  selected: widget.data.point,
                  dark: dark,
                  active: active,
                  centerRequest: _center,
                  readOnly: true,
                  detail: true,
                  satellite: _satellite,
                  cameraTarget: _camera,
                  userLocation: _user,
                  viewportInsets: EdgeInsets.only(
                      top: safe.top +
                          ChatLocationDetailTokens.controlSize +
                          AppTokens.s7,
                      bottom: bottom),
                  onCapabilities: (value) {
                    if (mounted && _supportsSatellite != value) {
                      setState(() => _supportsSatellite = value);
                    }
                  },
                  onSelected: (_) {},
                  onReady: () {
                    if (!mounted) return;
                    setState(() => _ready = true);
                    if (!_addressRequested) unawaited(_resolveAddress());
                    if (!_automaticLocationStarted &&
                        widget.data.point != null) {
                      _automaticLocationStarted = true;
                      unawaited(_locate(automatic: true));
                    }
                  },
                  onError: (_) {
                    if (mounted) setState(() => _ready = false);
                  });
              return Stack(fit: StackFit.expand, children: [
                if (widget.data.point != null)
                  Padding(
                      padding:
                          _ready ? EdgeInsets.zero : options.viewportInsets,
                      child: widget.mapBuilder?.call(context, options) ??
                          ChatLocationNativeMap(options: options))
                else
                  Center(child: Text('sdkInvalidLocation'.tr)),
                Positioned(
                    top: safe.top + AppTokens.s3,
                    left: AppTokens.s5,
                    right: AppTokens.s5,
                    child: Row(children: [
                      ChatLocationDetailControl(
                          key: const ValueKey('chat-location-detail-back'),
                          label: MaterialLocalizations.of(context)
                              .closeButtonTooltip,
                          icon: Icons.close,
                          onPressed: () => Navigator.of(context).maybePop()),
                      Expanded(
                          child: Center(
                              child: ChatLocationDetailSurface(
                                  child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: AppTokens.s5,
                                          vertical: AppTokens.s3),
                                      child: Text('location'.tr,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: ChatLocationDetailTokens
                                                  .titleSize,
                                              fontWeight: FontWeight.w600)))))),
                      ChatLocationDetailControl(
                          key: _shareKey,
                          label: labels.share,
                          icon: Icons.ios_share,
                          onPressed: widget.data.point != null && !_busy
                              ? _share
                              : null),
                    ])),
                if (_ready && widget.data.point != null)
                  Positioned(
                      top: safe.top +
                          ChatLocationDetailTokens.controlSize +
                          AppTokens.s7,
                      left: AppTokens.s5,
                      child: SizedBox(
                          width: constraints.maxWidth * .5,
                          child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: ChatLocationWeatherChip(
                                  point: widget.data.point!)))),
                if (widget.data.point != null)
                  Positioned(
                      bottom: safe.bottom,
                      left: AppTokens.s3,
                      right: AppTokens.s3,
                      child: Center(
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                  maxWidth:
                                      ChatLocationDetailTokens.maxCardWidth),
                              child: ConstrainedBox(
                                  constraints:
                                      BoxConstraints(maxHeight: cardHeight),
                                  child: SingleChildScrollView(
                                      child: ChatLocationDetailCard(
                                          data: data,
                                          addressStatus: _addressLoading
                                              ? labels.addressLoading
                                              : _addressFailed
                                                  ? labels.addressFailed
                                                  : null,
                                          onRetryAddress: _addressFailed
                                              ? _resolveAddress
                                              : null,
                                          title: title,
                                          onDirections:
                                              !_busy ? _directions : null)))))),
                if (_ready)
                  Positioned(
                      right: AppTokens.s5,
                      bottom: bottom + AppTokens.s3,
                      child: Flex(
                          direction: constraints.maxHeight < 500
                              ? Axis.horizontal
                              : Axis.vertical,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_supportsSatellite) ...[
                              ChatLocationDetailControl(
                                  label: labels.layers,
                                  icon: Icons.layers_outlined,
                                  onPressed: active ? _layers : null),
                              const SizedBox(
                                  width: AppTokens.s3, height: AppTokens.s3),
                            ],
                            ChatLocationDetailControl(
                                key: const ValueKey(
                                    'chat-location-detail-recenter'),
                                label: labels.recenter,
                                icon: Icons.location_on_outlined,
                                onPressed: active
                                    ? () => setState(() {
                                          _camera = null;
                                          _center++;
                                        })
                                    : null),
                            const SizedBox(
                                width: AppTokens.s3, height: AppTokens.s3),
                            ChatLocationDetailControl(
                                key: const ValueKey(
                                    'chat-location-detail-locate'),
                                label:
                                    _locating ? picker.locating : picker.locate,
                                icon: Icons.near_me_outlined,
                                busy: _locating,
                                onPressed:
                                    active && !_locating ? _locate : null),
                          ])),
              ]);
            })));
  }
}
