import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'group_manage_logic.dart';

class GroupManagePage extends StatelessWidget {
  final GroupManageLogic logic;
  GroupManagePage({super.key, GroupManageLogic? logic})
      : logic = logic ?? Get.find<GroupManageLogic>();
  static const _radius = BorderRadius.all(Radius.circular(12));

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Styles.c_F8F9FA,
        appBar: AppBar(
            centerTitle: true,
            backgroundColor: Styles.c_F8F9FA,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(CupertinoIcons.back,
                    color: Styles.c_0089FF, size: 24)),
            title: Text(StrRes.groupManage,
                style: Styles.ts_0C1C33_17sp_semibold)),
        body: SafeArea(
            top: false,
            child: Obx(() {
              final owner = logic.groupSetupLogic.isOwner;
              final busy = logic.busy.value;
              final info = logic.groupInfo.value;
              final rule = info.needVerification ?? 0;
              return Column(children: [
                SizedBox(
                    height: 2,
                    child: busy
                        ? LinearProgressIndicator(color: Styles.c_0089FF)
                        : null),
                Expanded(
                    child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                        children: [
                      _section([
                        if (owner)
                          _toggle('sdkMuteAll'.tr,
                              value: info.status == 3,
                              onChanged: busy
                                  ? null
                                  : (v) => logic.saveRules(muted: v)),
                        _row('sdkAdminList'.tr, onTap: logic.admins),
                        _row('sdkMutedList'.tr, onTap: logic.mutedMembers),
                        if (owner)
                          _row('sdkJoinRule'.tr,
                              subtitle: 'sdkJoinRule${rule.clamp(0, 2)}'.tr,
                              onTap: busy
                                  ? null
                                  : () => _selectJoinRule(context, rule)),
                      ]),
                      const SizedBox(height: 16),
                      _section([
                        if (!logic.friendProtection.ready.value)
                          _row('群成员隐私保护',
                              subtitle: logic.friendProtection.failed.value
                                  ? '读取失败，点击重试'
                                  : '正在读取',
                              onTap: logic.friendProtection.busy.value
                                  ? null
                                  : logic.friendProtection.refresh),
                        if (logic.friendProtection.ready.value)
                          _toggle('群成员隐私保护',
                              value: logic.friendProtection.protect.value,
                              onChanged: logic.friendProtection.busy.value ||
                                      !logic.friendProtection.canManage.value
                                  ? null
                                  : logic.friendProtection.setProtected),
                        if (owner)
                          _toggle('允许查看群成员资料',
                              value: info.lookMemberInfo != 1,
                              onChanged: busy
                                  ? null
                                  : (v) => logic.saveRules(look: v ? 0 : 1)),
                      ]),
                      if (owner) ...[
                        const SizedBox(height: 16),
                        _section([
                          _row(StrRes.transferGroupOwnerRight,
                              onTap:
                                  busy ? null : logic.transferGroupOwnerRight)
                        ]),
                      ],
                    ])),
              ]);
            })),
      );

  Widget _section(List<Widget> rows) => Material(
      color: Styles.c_FFFFFF,
      borderRadius: _radius,
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            Divider(
                height: 1,
                thickness: .5,
                indent: 16,
                endIndent: 16,
                color: Styles.c_E8EAEF),
          rows[i],
        ],
      ]));

  Widget _row(String title,
          {String? subtitle, VoidCallback? onTap, Widget? trailing}) =>
      InkWell(
          onTap: onTap,
          child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 58),
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(title,
                              style: TextStyle(
                                  fontSize: 16, color: Styles.c_0C1C33)),
                          if (subtitle != null) ...[
                            const SizedBox(height: 6),
                            Text(subtitle,
                                style: TextStyle(
                                    fontSize: 13,
                                    height: 1.4,
                                    color: Styles.c_8E9AB0)),
                          ],
                        ])),
                    const SizedBox(width: 12),
                    trailing ??
                        Icon(CupertinoIcons.chevron_right,
                            size: 18, color: Styles.c_8E9AB0),
                  ]))));
  Widget _toggle(String title,
          {required bool value, required ValueChanged<bool>? onChanged}) =>
      _row(title,
          trailing: CupertinoSwitch(
              value: value,
              activeTrackColor: Styles.c_0089FF,
              onChanged: onChanged));

  Future<void> _selectJoinRule(BuildContext context, int current) async {
    final draft = current.clamp(0, 2);
    final accent = Styles.c_0089FF;
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Styles.c_FFFFFF,
      showDragHandle: false,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                margin: const EdgeInsets.only(top: 14, bottom: 20),
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                    color: Styles.c_8E9AB0.withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(3))),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 24),
              child: Text('sdkJoinRule'.tr,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Styles.c_0C1C33)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0)
                    Divider(height: 1, thickness: .5, color: Styles.c_E8EAEF),
                  Semantics(
                    selected: draft == i,
                    child: _row(
                      'sdkJoinRule$i'.tr,
                      subtitle: 'sdkJoinRuleDescription$i'.tr,
                      onTap: () => Navigator.of(sheetContext).pop(i),
                      trailing: Icon(
                          draft == i
                              ? CupertinoIcons.checkmark_circle_fill
                              : CupertinoIcons.circle,
                          size: 28,
                          color: draft == i ? accent : Styles.c_8E9AB0),
                    ),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            Divider(height: 1, thickness: .5, color: Styles.c_E8EAEF),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                  style: TextButton.styleFrom(
                      minimumSize: const Size(0, 64),
                      foregroundColor: Styles.c_0C1C33,
                      textStyle: const TextStyle(fontSize: 18)),
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text(StrRes.cancel)),
            ),
          ]),
        ),
      ),
    );
    if (selected != null && selected != current && !logic.isClosed) {
      await logic.saveRules(verification: selected);
    }
  }
}
