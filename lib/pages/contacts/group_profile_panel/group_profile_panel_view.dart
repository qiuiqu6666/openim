import '../../group_features/identity/group_name_label.dart';
import '../../channels/models/channel_kind.dart';
import '../../channels/presentation/channel_ui.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'group_profile_panel_logic.dart';

class GroupProfilePanelPage extends StatelessWidget {
  final GroupProfilePanelLogic logic;

  GroupProfilePanelPage({super.key, GroupProfilePanelLogic? logic})
      : logic = logic ?? Get.find<GroupProfilePanelLogic>();

  static Color get _muted => Styles.c_8E9AB0;
  static Color get _card => Styles.c_F4F5F7;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Styles.c_FFFFFF,
        appBar: GlassAppBar(
          backgroundColor: Styles.c_FFFFFF,
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Get.back(),
            icon: Icon(Icons.arrow_back_ios_new,
                color: Styles.c_0089FF, size: 22),
          ),
        ),
        body: Obx(() {
          final group = logic.groupInfo.value;
          final channel = isChannelEx(group.ex);
          return SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 36, 16, 24),
                    children: [
                      Center(
                        child: AvatarView(
                          width: 90,
                          height: 90,
                          url: group.faceURL,
                          text: group.groupName,
                          isGroup: true,
                          isCircle: true,
                          enabledPreview: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      GroupNameLabel(
                        name: group.groupName ?? '',
                        ex: group.ex,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                          color: Styles.c_0C1C33,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        channel ? 'channelSubscriberCountLabel'.trArgs(['${group.memberCount ?? logic.members.length}']) : '共${group.memberCount ?? logic.members.length}人',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: _muted),
                      ),
                      const SizedBox(height: 32),
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(channel ? channelText(context, '频道ID', 'Channel ID') : '群UID',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text(
                                    group.groupID,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        TextStyle(fontSize: 15, color: _muted),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: StrRes.copySuccessfully,
                              onPressed: () =>
                                  IMUtils.copy(text: group.groupID),
                              icon: Icon(Icons.copy_outlined, color: _muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(channel ? channelText(context, '频道公告', 'Channel announcement') : 'groupAnnouncement'.tr,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          group.notification?.isNotEmpty == true
                              ? group.notification!
                              : channel ? channelText(context, '暂无频道公告', 'No channel announcement') : 'groupNoAnnouncement'.tr,
                          style: TextStyle(fontSize: 15, color: _muted),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Button(
                    text: logic.isJoined.value
                        ? (channel ? channelText(context, '进入频道', 'Enter channel') : StrRes.enterGroup)
                        : (channel ? channelText(context, '订阅频道', 'Subscribe to channel') : StrRes.applyJoin),
                    onTap: logic.enterGroup,
                  ),
                ),
              ],
            ),
          );
        }),
      );
}
