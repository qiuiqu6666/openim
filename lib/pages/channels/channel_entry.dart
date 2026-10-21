import 'package:flutter/material.dart';
import 'create/channel_create_flow.dart';
import 'create/channel_intro_page.dart';
import 'package:get/get.dart';
import '../conversation/conversation_logic.dart';
import 'data/channel_creation.dart';
import 'models/channel_preview.dart';
import 'presentation/channel_tokens.dart';
import 'channel_live_list_page.dart';

/// Directory entry opens the list; quick creation skips the list.
Future<void> openChannelPages(BuildContext context,
    {bool create = false}) async {
  if (!create) {
    await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute(builder: (_) => const ChannelLiveListPage()));
    return;
  }
  final proceed =
      await _showChannelSheet<bool>(context, const ChannelIntroPage());
  if (!context.mounted || proceed != true) return;
  final creation = ChannelCreation.sdk();
  final channel = await _showChannelSheet<ChannelPreview>(
      context, ChannelCreateFlow(onSubmit: creation.submit));
  if (channel == null) return;
  try {
    if (!context.mounted) return;
    final group = channel.createdGroup;
    if (group != null && creation.current()) {
      Get.find<ConversationLogic>().toChat(
          offUntilHome: false,
          groupID: group.groupID,
          nickname: group.groupName,
          faceURL: group.faceURL,
          sessionType: group.sessionType);
    }
  } finally {
    channel.dispose();
  }
}

Future<T?> _showChannelSheet<T>(BuildContext context, Widget page) =>
    showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      isDismissible: page is! ChannelCreateFlow,
      enableDrag: page is! ChannelCreateFlow,
      barrierColor: const Color(0x800A1526),
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(ChannelTokens.sheetRadius))),
      builder: (context) => SizedBox(
          height:
              MediaQuery.sizeOf(context).height * ChannelTokens.sheetFraction,
          child: page),
    );
