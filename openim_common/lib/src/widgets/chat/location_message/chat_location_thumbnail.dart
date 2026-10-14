import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../res/app_tokens.dart';
import '../location_picker/native/chat_location_amap_consent.dart';
import '../location_picker/native/chat_location_map_runtime.dart';
import '../location_picker/native/chat_location_native_map.dart';
import '../location_picker/native/chat_location_native_map_options.dart';
import 'chat_location_message_data.dart';
import 'chat_location_message_tokens.dart';

/// A short-lived native view produces a bounded in-memory snapshot cache.
/// No map SDK starts on Android until previously granted consent is confirmed.
class ChatLocationThumbnail extends StatefulWidget {
  const ChatLocationThumbnail({super.key, required this.data, this.mapBuilder});
  final ChatLocationMessageData data;
  final ChatLocationMapBuilder? mapBuilder;
  @override
  State<ChatLocationThumbnail> createState() => _ChatLocationThumbnailState();
}

class _ChatLocationThumbnailState extends State<ChatLocationThumbnail>
    with WidgetsBindingObserver {
  static final _cache = <String, Uint8List>{};
  bool _consent = false, _failed = false, _foreground = true;
  bool _nativeAvailable = true;
  Timer? _timeout;
  Uint8List? _image;
  String? _key;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _readConsent();
  }

  Future<void> _readConsent() async {
    var allowed = kIsWeb || defaultTargetPlatform != TargetPlatform.android;
    if (!allowed) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        allowed = prefs.getBool(ChatLocationAmapConsent.preferenceKey) == true;
      } catch (_) {
        allowed = false;
      }
    }
    final nativeAvailable =
        allowed ? await ChatLocationMapRuntime.nativeAvailable() : true;
    if (mounted) {
      setState(() {
        _consent = allowed;
        _nativeAvailable = nativeAvailable;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => _foreground = state == AppLifecycleState.resumed ||
          state == AppLifecycleState.inactive);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshKey();
  }

  @override
  void didUpdateWidget(covariant ChatLocationThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshKey();
  }

  void _refreshKey() {
    final point = widget.data.point;
    final next =
        '${point?.latitude},${point?.longitude}:${Theme.of(context).brightness}';
    if (_key == next) return;
    _key = next;
    _timeout?.cancel();
    _timeout = null;
    _failed = false;
    _image = _cache.remove(next);
    if (_image != null) _cache[next] = _image!;
  }

  @override
  void dispose() {
    _timeout?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final active = _foreground &&
        (ModalRoute.isCurrentOf(context) ?? true) &&
        TickerMode.valuesOf(context).enabled;
    if (!active) {
      _timeout?.cancel();
      _timeout = null;
    }
    Widget content;
    if (_consent && _image != null) {
      content = Image.memory(_image!, fit: BoxFit.cover, gaplessPlayback: true);
    } else if (_consent && !_failed && widget.data.point != null && active) {
      final key = _key;
      final mobile = _nativeAvailable &&
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS);
      if (mobile && widget.mapBuilder == null && _timeout == null) {
        _timeout = Timer(ChatLocationMessageTokens.snapshotTimeout, () {
          if (mounted && _key == key && _image == null) {
            setState(() => _failed = true);
          }
        });
      }
      final options = ChatLocationNativeMapOptions(
          selected: widget.data.point,
          dark: dark,
          active: active,
          readOnly: true,
          centerRequest: 0,
          onSelected: (_) {},
          onReady: () {},
          onError: (_) {
            if (mounted && _key == key) setState(() => _failed = true);
          },
          onSnapshot: mobile
              ? (bytes) {
                  if (!mounted || key != _key) return;
                  _timeout?.cancel();
                  _cache[key!] = bytes;
                  while (
                      _cache.length > ChatLocationMessageTokens.cacheEntries) {
                    _cache.remove(_cache.keys.first);
                  }
                  setState(() => _image = bytes);
                }
              : null);
      content = IgnorePointer(
          child: widget.mapBuilder?.call(context, options) ??
              ChatLocationNativeMap(
                  key: ValueKey(key), options: options, requireConsent: false));
    } else {
      content = ColoredBox(
          color: AppTokens.surfaceAlt(dark: dark),
          child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.location_on,
                color: ChatLocationMessageTokens.accent,
                size: ChatLocationMessageTokens.pinSize),
            const SizedBox(height: AppTokens.s3),
            Text('location'.tr,
                style: TextStyle(color: AppTokens.textSecondary(dark: dark))),
          ])));
    }
    return ExcludeSemantics(
        child: SizedBox(
            height: ChatLocationMessageTokens.previewHeight,
            width: double.infinity,
            child: ClipRect(child: content)));
  }
}
