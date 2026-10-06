import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

/// The SDK owns deletion. This widget only masks expired content and displays
/// the read deadline; it never changes the server's retention policy.
class ChatExpiringContent extends StatefulWidget {
  const ChatExpiringContent(
      {super.key, required this.message, required this.child, this.builder});
  final Message message;
  final Widget child;

  /// Allows bounded media cells to place the notice inside their own surface.
  /// Expired content is replaced before calling the builder, never mounted.
  final Widget Function(BuildContext context, Widget content, String? notice)?
      builder;
  static DateTime? deadline(Message message) => message.burnDeadline;
  @override
  State<ChatExpiringContent> createState() => _ChatExpiringContentState();
}

class _ChatExpiringContentState extends State<ChatExpiringContent> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant ChatExpiringContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  void _schedule() {
    timer?.cancel();
    final end = ChatExpiringContent.deadline(widget.message);
    if (end != null && end.isAfter(DateTime.now())) {
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        if (!end.isAfter(DateTime.now())) timer?.cancel();
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final end = ChatExpiringContent.deadline(widget.message);
    final seconds = end == null
        ? null
        : (end.difference(DateTime.now()).inMilliseconds / 1000).ceil();
    if (seconds != null && seconds <= 0) {
      final expired = Text('sdkExpired'.tr, style: Styles.ts_8E9AB0_13sp);
      return widget.builder?.call(context, expired, null) ?? expired;
    }
    final notice =
        '${'sdkBurnCountdown'.tr}${seconds == null ? '' : ' · $seconds ${'sdkSeconds'.tr}'}';
    if (widget.builder != null) {
      return widget.builder!(context, widget.child, notice);
    }
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.child,
          Text(notice, style: Styles.ts_8E9AB0_12sp),
        ]);
  }
}
