import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim_common/openim_common.dart';
import 'package:sprintf/sprintf.dart';

import 'conversation_logic.dart';

class ConversationPage extends StatelessWidget {
  final logic = Get.find<ConversationLogic>();
  final im = Get.find<IMController>();

  ConversationPage({super.key});

  Future<void> _confirmDeleteConversation(
      BuildContext context, ConversationInfo info) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(StrRes.delete),
        content: Text('${StrRes.delete} "${logic.getShowName(info)}"?\n${StrRes.confirmClearChatHistory}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(StrRes.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(StrRes.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      logic.deleteConversation(info);
    }
  }

  Widget _swipeAction({
    required Color color,
    required IconData icon,
    required String label,
    required void Function(BuildContext) onPressed,
  }) =>
      CustomSlidableAction(
        onPressed: onPressed,
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Obx(() => Scaffold(
          backgroundColor: Styles.c_F8F9FA,
          appBar: TitleBar.conversation(
              statusStr: logic.imSdkStatus,
              isFailed: logic.isFailedSdkStatus,
              popCtrl: logic.popCtrl,
              onAddFriend: logic.addFriend,
              onAddGroup: logic.addGroup,
              onCreateGroup: logic.createGroup,
              left: Expanded(
                flex: 2,
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    AvatarView(
                      width: 42.w,
                      height: 42.h,
                      text: im.userInfo.value.nickname,
                      url: im.userInfo.value.faceURL,
                    ),
                    10.horizontalSpace,
                    if (null != im.userInfo.value.nickname)
                      Flexible(
                        child: im.userInfo.value.nickname!.toText
                          ..style = Styles.ts_0C1C33_17sp
                          ..maxLines = 1
                          ..overflow = TextOverflow.ellipsis,
                      ),
                    10.horizontalSpace,
                    if (null != logic.imSdkStatus && (!logic.reInstall || logic.isFailedSdkStatus))
                      Flexible(
                          child: SyncStatusView(
                        isFailed: logic.isFailedSdkStatus,
                        statusStr: logic.imSdkStatus!,
                      )),
                  ],
                ),
              )),
          body: Column(
            children: [
              Expanded(
                  child: ListView.builder(
                    itemBuilder: (_, index) => _buildItemView(
                      logic.list.elementAt(index),
                    ),
                    itemCount: logic.list.length,
                  
                ),
              ),
            ],
          ),
        ));
  }

  Widget _buildItemView(ConversationInfo info) => Slidable(
    key: ValueKey(info.conversationID),
    endActionPane: ActionPane(
      motion: const BehindMotion(),
      extentRatio: 0.5,
      openThreshold: 0.12,
      closeThreshold: 0.38,
      children: [
        _swipeAction(
          onPressed: (_) => logic.setNotDisturb(info, !logic.isNotDisturb(info)),
          color: const Color(0xFF8E9AB0),
          icon: logic.isNotDisturb(info) ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
          label: logic.isNotDisturb(info)
              ? StrRes.disableConversationMute
              : StrRes.enableConversationMute,
        ),
        _swipeAction(
          onPressed: (_) => logic.setPinned(info, info.isPinned != true),
          color: Styles.c_0089FF,
          icon: info.isPinned == true ? Icons.push_pin_outlined : Icons.push_pin,
          label: info.isPinned == true ? StrRes.cancelTop : StrRes.topChat,
        ),
        _swipeAction(
          onPressed: (context) => _confirmDeleteConversation(context, info),
          color: const Color(0xFFE45454),
          icon: Icons.delete_outline,
          label: StrRes.delete,
        ),
      ],
    ),
    child: Ink(
        child: InkWell(
          onTap: () => logic.toChat(conversationInfo: info),
          child: Stack(
            children: [
              Container(
                height: 68,
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        AvatarView(
                          width: 48.w,
                          height: 48.h,
                          text: logic.getShowName(info),
                          url: info.faceURL,
                          isGroup: logic.isGroupChat(info),
                          textStyle: Styles.ts_FFFFFF_14sp_medium,
                        ),
                      ],
                    ),
                    12.horizontalSpace,
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: 180.w),
                                child: logic.getShowName(info).toText
                                  ..style = Styles.ts_0C1C33_17sp
                                  ..maxLines = 1
                                  ..overflow = TextOverflow.ellipsis,
                              ),
                              if (info.isPinned == true) ...[
                                5.horizontalSpace,
                                Icon(Icons.push_pin, size: 15.w, color: Styles.c_8E9AB0),
                              ],
                              if (logic.isNotDisturb(info)) ...[
                                5.horizontalSpace,
                                Icon(Icons.notifications_off_outlined, size: 15.w, color: Styles.c_8E9AB0),
                              ],
                              const Spacer(),
                              logic.getTime(info).toText..style = Styles.ts_8E9AB0_12sp,
                            ],
                          ),
                          3.verticalSpace,
                          Row(
                            children: [
                              MatchTextView(
                                text: logic.getContent(info),
                                textStyle: Styles.ts_8E9AB0_14sp,
                                prefixSpan: TextSpan(
                                  text: '',
                                  children: [
                                    if (logic.getUnreadCount(info) > 0)
                                      TextSpan(
                                        text: '[${sprintf(StrRes.nPieces, [logic.getUnreadCount(info)])}] ',
                                        style: Styles.ts_8E9AB0_14sp,
                                      ),
                                    TextSpan(
                                      text: logic.getPrefixTag(info),
                                      style: Styles.ts_0089FF_14sp,
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const Spacer(),
                              UnreadCountView(count: logic.getUnreadCount(info)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
  );
}
