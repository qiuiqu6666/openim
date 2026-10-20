import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import '../../../res/app_tokens.dart';
import '../../../extension/message_manager.dart';
import '../location_picker/native/chat_location_native_map_options.dart';
import 'chat_location_detail_page.dart';
import 'chat_location_message_data.dart';
import 'chat_location_message_tokens.dart';
import 'chat_location_thumbnail.dart';

class ChatLocationMessageCard extends StatefulWidget {
  const ChatLocationMessageCard(
      {super.key,
      required this.message,
      this.time,
      this.status,
      this.mapBuilder});
  final Message message;
  final String? time;
  final Widget? status;
  final ChatLocationMapBuilder? mapBuilder;
  @override
  State<ChatLocationMessageCard> createState() =>
      _ChatLocationMessageCardState();
}

class _ChatLocationMessageCardState extends State<ChatLocationMessageCard> {
  bool _opening = false;
  int _revision = 0;
  Future<void> _open(ChatLocationMessageData data) async {
    if (_opening || data.point == null || widget.message.hasExpired) return;
    _opening = true;
    await Navigator.of(context).push(GetPageRoute<void>(
        customTransition: Get.customTransition,
        transitionDuration: Get.defaultTransitionDuration,
        popGesture: false,
        page: () =>
            ChatLocationDetailPage(data: data, mapBuilder: widget.mapBuilder)));
    if (mounted) {
      setState(() {
        _opening = false;
        _revision++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final point = widget.message.locationElem;
    final data = ChatLocationMessageData.parse(
        point?.description, point?.latitude, point?.longitude);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
        label: [data.name.isEmpty ? 'location'.tr : data.name, data.address]
            .where((text) => text.isNotEmpty)
            .join(', '),
        child: SizedBox(
            width: ChatLocationMessageTokens.width,
            child: Material(
                key: const ValueKey('chat-location-message-card'),
                color: AppTokens.surface(dark: dark),
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(ChatLocationMessageTokens.radius),
                    side: BorderSide(color: AppTokens.border(dark: dark))),
                child: InkWell(
                    onTap: data.point == null ? null : () => _open(data),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Stack(children: [
                            ChatLocationThumbnail(
                                key: ValueKey(
                                    '${widget.message.clientMsgID}:$_revision'),
                                data: data,
                                mapBuilder: widget.mapBuilder),
                            if (widget.time != null || widget.status != null)
                              Positioned(
                                  right: AppTokens.s3,
                                  bottom: AppTokens.s3,
                                  child: DecoratedBox(
                                      key: const ValueKey(
                                          'chat-location-time-watermark'),
                                      decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.45),
                                          borderRadius: BorderRadius.circular(
                                              AppTokens.rSm)),
                                      child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: AppTokens.s2,
                                              vertical: AppTokens.s2),
                                          child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (widget.time != null)
                                                  Text(widget.time!,
                                                      style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize:
                                                              ChatLocationMessageTokens
                                                                  .footerSize)),
                                                if (widget.status != null) ...[
                                                  if (widget.time != null)
                                                    const SizedBox(
                                                        width: AppTokens.s2),
                                                  IconTheme(
                                                      data: const IconThemeData(
                                                          color: Colors.white),
                                                      child: widget.status!),
                                                ],
                                              ])))),
                          ]),
                        ])))));
  }
}
