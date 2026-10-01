import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'group_profile_panel_logic.dart';

class GroupProfilePanelPage extends StatelessWidget {
  final logic = Get.find<GroupProfilePanelLogic>();

  GroupProfilePanelPage({super.key});

  static const _muted = Color(0xFF8993A7);
  static const _card = Color(0xFFF7F8FA);

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: GlassAppBar(
          backgroundColor: Colors.white,
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Get.back(),
            icon: Icon(Icons.arrow_back_ios_new,
                color: Styles.c_0089FF, size: 22),
          ),
        ),
        body: Obx(() {
          final group = logic.groupInfo.value;
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
                      Text(
                        group.groupName ?? '',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF11151D),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '共${group.memberCount ?? logic.members.length}人',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, color: _muted),
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
                                  const Text('群UID',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text(
                                    group.groupID,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 15, color: _muted),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: StrRes.copySuccessfully,
                              onPressed: () =>
                                  IMUtils.copy(text: group.groupID),
                              icon: const Icon(Icons.copy_outlined,
                                  color: _muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text('groupAnnouncement'.tr,
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
                              : 'groupNoAnnouncement'.tr,
                          style: const TextStyle(fontSize: 15, color: _muted),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Button(
                    text: logic.isJoined.value
                        ? StrRes.enterGroup
                        : StrRes.applyJoin,
                    onTap: logic.enterGroup,
                  ),
                ),
              ],
            ),
          );
        }),
      );
}
