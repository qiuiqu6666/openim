import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:openim_common/openim_common.dart';

class ChatDelayedStatusView extends StatefulWidget {
  const ChatDelayedStatusView({
    super.key,
    required this.isSending,
    this.delay = true,
    this.color,
  });
  final bool isSending;
  final bool delay;
  final Color? color;

  @override
  State<ChatDelayedStatusView> createState() => _ChatDelayedStatusViewState();
}

class _ChatDelayedStatusViewState extends State<ChatDelayedStatusView> {
  Timer? _timer;
  bool _visible = false;

  void _scheduleStatus() {
    _timer?.cancel();
    _visible = widget.isSending && !widget.delay;
    if (widget.isSending && widget.delay) {
      _timer = Timer(const Duration(seconds: 1), () {
        if (mounted && widget.isSending) setState(() => _visible = true);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _scheduleStatus();
  }

  @override
  void didUpdateWidget(covariant ChatDelayedStatusView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSending != widget.isSending ||
        oldWidget.delay != widget.delay) {
      _scheduleStatus();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Visibility(
        visible: widget.isSending && _visible,
        child: CupertinoActivityIndicator(
          color: widget.color ?? Styles.c_0089FF,
        ),
      );
}
