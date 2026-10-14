import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../res/app_tokens.dart';
import '../../liquid_glass_surface.dart';
import '../location_picker/native/chat_location_native_map.dart';
import '../location_picker/native/chat_location_native_map_options.dart';
import 'chat_location_message_data.dart';
import 'chat_location_message_tokens.dart';

/// Views the shared point; never requests the recipient's GPS or changes the pin.
class ChatLocationDetailPage extends StatefulWidget {
  const ChatLocationDetailPage(
      {super.key, required this.data, this.mapBuilder});
  final ChatLocationMessageData data;
  final ChatLocationMapBuilder? mapBuilder;
  @override
  State<ChatLocationDetailPage> createState() => _ChatLocationDetailPageState();
}

class _ChatLocationDetailPageState extends State<ChatLocationDetailPage>
    with WidgetsBindingObserver {
  bool _foreground = true, _ready = false;
  int _center = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = AppTokens.surface(dark: dark);
    final point = widget.data.point;
    final active = _foreground &&
        (ModalRoute.isCurrentOf(context) ?? true) &&
        TickerMode.valuesOf(context).enabled;
    final options = ChatLocationNativeMapOptions(
        selected: point,
        dark: dark,
        active: active,
        centerRequest: _center,
        readOnly: true,
        onSelected: (_) {},
        onReady: () {
          if (mounted) setState(() => _ready = true);
        },
        onError: (_) {
          if (mounted) setState(() => _ready = false);
        });
    return Scaffold(
        key: const ValueKey('chat-location-detail'),
        backgroundColor: surface,
        appBar: GlassAppBar(
            opaque: true,
            backgroundColor: surface,
            toolbarHeight: 56,
            foregroundColor: AppTokens.textPrimary(dark: dark),
            centerTitle: true,
            leading: IconButton(
                key: const ValueKey('chat-location-detail-back'),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_ios_new)),
            title: Text('location'.tr)),
        body: point == null
            ? Center(child: Text('sdkInvalidLocation'.tr))
            : Column(children: [
                Expanded(
                    child: Stack(fit: StackFit.expand, children: [
                  widget.mapBuilder?.call(context, options) ??
                      ChatLocationNativeMap(options: options),
                  if (_ready)
                    Positioned(
                        right: AppTokens.s5,
                        bottom: AppTokens.s5,
                        child: Material(
                            color: surface,
                            borderRadius: BorderRadius.circular(AppTokens.rSm),
                            child: IconButton(
                                key: const ValueKey(
                                    'chat-location-detail-recenter'),
                                tooltip: widget.data.name.isEmpty
                                    ? 'location'.tr
                                    : widget.data.name,
                                onPressed: active
                                    ? () => setState(() => _center++)
                                    : null,
                                icon: const Icon(Icons.center_focus_strong,
                                    color: ChatLocationMessageTokens.accent)))),
                ])),
                SafeArea(
                    top: false,
                    child: Padding(
                        padding: const EdgeInsets.all(AppTokens.s5),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                  widget.data.name.isEmpty
                                      ? 'location'.tr
                                      : widget.data.name,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: AppTokens.textPrimary(dark: dark),
                                      fontSize:
                                          ChatLocationMessageTokens.titleSize,
                                      fontWeight: FontWeight.w600)),
                              if (widget.data.address.isNotEmpty) ...[
                                const SizedBox(height: AppTokens.s3),
                                Text(widget.data.address,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color:
                                            AppTokens.textSecondary(dark: dark),
                                        fontSize: ChatLocationMessageTokens
                                            .detailSize)),
                              ],
                            ]))),
              ]));
  }
}
