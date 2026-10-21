import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../presentation/channel_tokens.dart';

/// Channel subscribers control delivery notifications instead of composing.
/// The conversation service owns persistence and failure reporting.
class ChannelNotificationBar extends StatefulWidget {
  const ChannelNotificationBar({
    super.key,
    required this.conversation,
    required this.changes,
    required this.setMuted,
  });

  final ConversationInfo Function() conversation;
  final Stream<List<ConversationInfo>> changes;
  final Future<void> Function(ConversationInfo, bool) setMuted;

  @override
  State<ChannelNotificationBar> createState() => _ChannelNotificationBarState();
}

class _ChannelNotificationBarState extends State<ChannelNotificationBar> {
  StreamSubscription<List<ConversationInfo>>? _subscription;
  late ConversationInfo _info;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _info = widget.conversation();
    _subscription = widget.changes.listen((changes) {
      for (final info in changes) {
        if (info.conversationID == _info.conversationID && mounted) {
          setState(() => _info = info);
          break;
        }
      }
    });
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.setMuted(_info, _info.recvMsgOpt != 2);
    } catch (error) {
      if (mounted) IMViews.showErrorToast(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
                minHeight: ChannelTokens.notificationBarHeight),
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                key: const ValueKey('channel-notification-toggle'),
                onPressed: _busy ? null : _toggle,
                style: TextButton.styleFrom(
                  shape: const RoundedRectangleBorder(),
                  minimumSize:
                      const Size(0, ChannelTokens.notificationBarHeight),
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  textStyle:
                      const TextStyle(fontSize: AppTokens.secondaryFontSize),
                ),
                child: Text((_busy
                        ? 'channelNotificationUpdating'
                        : _info.recvMsgOpt == 2
                            ? 'channelNotificationMuted'
                            : 'channelNotificationReceiving')
                    .tr),
              ),
            ),
          ),
        ),
      );
}
