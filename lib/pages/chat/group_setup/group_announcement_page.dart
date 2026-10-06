import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'group_setup_logic.dart';
import '../group/announcements/group_announcement_error_message.dart';

class GroupAnnouncementPage extends StatefulWidget {
  const GroupAnnouncementPage({super.key, this.logic});
  final GroupSetupLogic? logic;

  @override
  State<GroupAnnouncementPage> createState() => _GroupAnnouncementPageState();
}

class _GroupAnnouncementPageState extends State<GroupAnnouncementPage> {
  late final logic = widget.logic ?? Get.find<GroupSetupLogic>();
  late final controller = TextEditingController(
    text: logic.groupInfo.value.notification ?? '',
  );
  bool saving = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> publish() async {
    if (saving || !logic.isOwnerOrAdmin) return;
    final text = controller.text.trim();
    if (text.characters.length > 600) return;
    final groupID = logic.groupInfo.value.groupID;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => saving = true);
    try {
      await OpenIM.iMManager.groupManager.setGroupInfo(GroupInfo(
        groupID: groupID,
        notification: text,
      ));
      if (!mounted || logic.groupInfo.value.groupID != groupID) return;
      logic.groupInfo.update((info) => info?.notification = text);
      IMViews.showToast(StrRes.setSuccessfully);
      Navigator.of(context).pop();
    } catch (error) {
      Logger.print('Publish group announcement failed: $error',
          isError: true, onlyConsole: true);
      if (mounted && logic.groupInfo.value.groupID == groupID) {
        IMViews.showToast(groupAnnouncementPublishErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Obx(() {
        final canEdit = logic.isOwnerOrAdmin;
        final theme = Theme.of(context);
        return PopScope(
          canPop: !saving,
          child: Scaffold(
            backgroundColor: Styles.c_FFFFFF,
            appBar: GlassAppBar(
              toolbarHeight: kToolbarHeight,
              title: Text('groupAnnouncement'.tr),
              centerTitle: true,
              backgroundColor: Styles.c_FFFFFF,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_ios_new, color: Styles.c_0089FF),
                onPressed: saving ? null : () => Navigator.of(context).pop(),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Divider(height: 1, color: Styles.c_E8EAEF),
              ),
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.sizeOf(context).width * 0.032,
                  vertical: 18,
                ),
                child: canEdit
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                              constraints: BoxConstraints(
                                minHeight:
                                    (MediaQuery.sizeOf(context).width * 0.36)
                                        .clamp(144.0, 240.0),
                              ),
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                              decoration: BoxDecoration(
                                color: Styles.c_F4F5F7,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: TextField(
                                controller: controller,
                                enabled: !saving,
                                onChanged: (_) => setState(() {}),
                                maxLength: 600,
                                keyboardType: TextInputType.multiline,
                                textAlignVertical: TextAlignVertical.top,
                                maxLines: null,
                                minLines: 5,
                                style: theme.textTheme.bodyLarge,
                                decoration: InputDecoration(
                                  hintText: '请输入群公告',
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  counterStyle:
                                      theme.textTheme.bodySmall?.copyWith(
                                    color: Styles.c_8E9AB0,
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              )),
                          const SizedBox(height: 22),
                          SizedBox(
                            height: 44,
                            child: FilledButton(
                              onPressed: saving ||
                                      controller.text.trim() ==
                                          (logic.groupInfo.value.notification ??
                                                  '')
                                              .trim() ||
                                      controller.text.characters.length > 600
                                  ? null
                                  : publish,
                              style: FilledButton.styleFrom(
                                backgroundColor: Styles.c_0089FF,
                                disabledBackgroundColor:
                                    Styles.c_0089FF.withValues(alpha: 0.45),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(saving ? '正在发布…' : '完成'),
                            ),
                          ),
                        ],
                      )
                    : SingleChildScrollView(
                        child: SelectableText(
                          logic.groupInfo.value.notification?.isNotEmpty == true
                              ? logic.groupInfo.value.notification!
                              : 'groupNoAnnouncement'.tr,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
              ),
            ),
          ),
        );
      });
}
