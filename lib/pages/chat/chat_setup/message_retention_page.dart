import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

class MessageRetentionPage extends StatefulWidget {
  const MessageRetentionPage({super.key, required this.conversation});
  final ConversationInfo conversation;
  @override
  State<MessageRetentionPage> createState() => _MessageRetentionPageState();
}

class _MessageRetentionPageState extends State<MessageRetentionPage> {
  late ConversationInfo info = widget.conversation;
  bool busy = false;
  Future<void> save({int? burn, int? retain}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await OpenIM.iMManager.conversationManager.setConversation(
          info.conversationID,
          ConversationReq(
              isPrivateChat: burn == null ? null : burn > 0,
              burnDuration: burn == null || burn == 0 ? null : burn,
              isMsgDestruct: retain == null ? null : retain > 0,
              msgDestructTime: retain == null || retain == 0 ? null : retain));
      final updated = await OpenIM.iMManager.conversationManager
          .getMultipleConversation(conversationIDList: [info.conversationID]);
      if (mounted && updated.isNotEmpty) setState(() => info = updated.first);
    } catch (error) {
      if (mounted) IMViews.showToast(error.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget choices(String title, int current, Map<int, String> values,
          ValueChanged<int> onChanged) =>
      ListTile(
          title: Text(title),
          subtitle: DropdownButton<int>(
              isExpanded: true,
              value: current,
              items: {
                ...values,
                if (!values.containsKey(current))
                  current: '$current ${'sdkSeconds'.tr}'
              }
                  .entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: busy
                  ? null
                  : (v) {
                      if (v != null) onChanged(v);
                    }));
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: GlassAppBar(title: Text('sdkRetention'.tr)),
      body: ListView(children: [
        if (busy) const LinearProgressIndicator(),
        if (info.isSingleChat)
          choices(
              'sdkBurn'.tr,
              info.isPrivateChat == true ? (info.burnDuration ?? 30) : 0,
              {
                0: 'sdkOff'.tr,
                30: '30 ${'sdkSeconds'.tr}',
                60: '1 ${'sdkMinutes'.tr}',
                300: '5 ${'sdkMinutes'.tr}'
              },
              (v) => save(burn: v)),
        choices(
            'sdkAutoDelete'.tr,
            info.isMsgDestruct == true ? (info.msgDestructTime ?? 86400) : 0,
            {
              0: 'sdkOff'.tr,
              86400: '1 ${'sdkDays'.tr}',
              604800: '7 ${'sdkDays'.tr}',
              2592000: '30 ${'sdkDays'.tr}'
            },
            (v) => save(retain: v)),
        Padding(
            padding: const EdgeInsets.all(16),
            child: Text('sdkRetentionHint'.tr, style: Styles.ts_8E9AB0_14sp)),
      ]));
}
