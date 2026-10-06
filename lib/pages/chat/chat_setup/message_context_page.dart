import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../../../core/controller/im_controller.dart';

class MessageContextPage extends StatefulWidget {
  const MessageContextPage(
      {super.key,
      required this.conversationID,
      required this.target,
      this.date});
  final String conversationID;
  final Message target;
  final DateTime? date;
  @override
  State<MessageContextPage> createState() => _MessageContextPageState();
}

class _MessageContextPageState extends State<MessageContextPage> {
  final messages = <Message>[];
  final removed = <String>{};
  bool failedReverse = false;
  final subscriptions = <StreamSubscription>[];
  final targetKey = GlobalKey();
  bool busy = false, failed = false, older = true, newer = true;
  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<IMController>()) {
      final im = Get.find<IMController>();
      void remove(String? id) {
        if (id == null) return;
        removed.add(id);
        if (mounted)
          setState(() => messages.removeWhere((m) => m.clientMsgID == id));
      }

      subscriptions
          .add(im.revokedMessages.listen((e) => remove(e.clientMsgID)));
      subscriptions
          .add(im.deletedMessages.listen((e) => remove(e.clientMsgID)));
    }
    load(initial: true);
  }

  Future<void> load({bool initial = false, bool reverse = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      failed = false;
    });
    try {
      final manager = OpenIM.iMManager.messageManager;
      if (initial) {
        final found = await manager.findMessageList(searchParams: [
          SearchParams(
              conversationID: widget.conversationID,
              clientMsgIDList: [widget.target.clientMsgID!])
        ]);
        if (!mounted) return;
        messages.addAll((found.findResultItems ?? found.searchResultItems)
                ?.expand((e) => e.messageList ?? <Message>[]) ??
            <Message>[]);
        messages.removeWhere((m) => removed.contains(m.clientMsgID));
        if (messages.isEmpty) {
          older = false;
          newer = false;
          return;
        }
      }
      if (messages.isEmpty) return;
      final page = reverse
          ? await manager.getAdvancedHistoryMessageListReverse(
              conversationID: widget.conversationID,
              startMsg: messages.last,
              count: 20)
          : await manager.getAdvancedHistoryMessageList(
              conversationID: widget.conversationID,
              startMsg: messages.first,
              count: 20);
      if (!mounted) return;
      final byID = {for (final m in messages) m.clientMsgID: m};
      for (final m in page.messageList ?? <Message>[]) {
        if (!removed.contains(m.clientMsgID)) byID[m.clientMsgID] = m;
      }
      messages
        ..clear()
        ..addAll(byID.values);
      messages.sort((a, b) => (a.sendTime ?? 0).compareTo(b.sendTime ?? 0));
      if (reverse) {
        newer = page.isEnd != true;
      } else {
        older = page.isEnd != true;
      }
      if (initial)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final targetContext = targetKey.currentContext;
          if (targetContext != null)
            Scrollable.ensureVisible(targetContext, alignment: 0.5);
        });
    } catch (_) {
      if (mounted) {
        failed = true;
        failedReverse = reverse;
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    for (final s in subscriptions) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: GlassAppBar(
          title: Text(widget.date == null
              ? 'sdkSearchContext'.tr
              : MaterialLocalizations.of(context)
                  .formatFullDate(widget.date!))),
      body: Column(children: [
        if (busy) const LinearProgressIndicator(),
        if (failed)
          TextButton(
              onPressed: busy
                  ? null
                  : () =>
                      load(initial: messages.isEmpty, reverse: failedReverse),
              child: Text('chatSearchRetry'.tr)),
        Expanded(
            child: SingleChildScrollView(
                child: Column(children: [
          if (older)
            TextButton(
                onPressed: busy ? null : () => load(),
                child: Text('sdkSearchOlder'.tr)),
          if (!busy && messages.isEmpty) Text('chatSearchEmpty'.tr),
          for (final message in messages)
            Container(
                key: message.clientMsgID == widget.target.clientMsgID
                    ? targetKey
                    : ValueKey(message.clientMsgID),
                child: ChatItemView(
                  message: message,
                  highlightColor:
                      message.clientMsgID == widget.target.clientMsgID
                          ? Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: .10)
                          : null,
                  onTapUserProfile: (_) {},
                  customTypeBuilder: (_, m) {
                    final data = IMUtils.parseCustomMessage(m);
                    return data?['viewType'] == CustomMessageType.call
                        ? CustomTypeInfo(ChatCallItemView(
                            type: data['type'], content: data['content']))
                        : null;
                  },
                  onClickItemView: () {
                    if (message.isPictureType || message.isVideoType)
                      IMUtils.previewMediaFile(
                          context: context, message: message);
                  },
                  mediaItemBuilder: (_, m) => m.isVideoType
                      ? IconButton(
                          icon: const Icon(Icons.play_circle_outline),
                          onPressed: () => IMUtils.previewMediaFile(
                              context: context, message: m))
                      : null,
                )),
          if (newer && messages.isNotEmpty)
            TextButton(
                onPressed: busy ? null : () => load(reverse: true),
                child: Text('sdkSearchNewer'.tr)),
        ]))),
      ]));
}
