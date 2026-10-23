import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import '../../group_setup_logic.dart';
import 'group_history_policy.dart';
import 'package:openim/pages/mine/settings/widgets/settings_widgets.dart';

class GroupHistoryPage extends StatefulWidget {
  const GroupHistoryPage({super.key, required this.logic});
  final GroupSetupLogic logic;

  @override
  State<GroupHistoryPage> createState() => _GroupHistoryPageState();
}

class _GroupHistoryPageState extends State<GroupHistoryPage> {
  late final GroupSetupPermissionContext permission;
  late bool enabled = GroupHistoryPolicy.read(widget.logic.groupInfo.value.ex);
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    permission = widget.logic.capturePermissionContext();
  }

  bool get current =>
      mounted &&
      widget.logic.isPermissionContextCurrent(permission) &&
      widget.logic.isOwner;

  Future<void> save() async {
    if (busy) return;
    if (!current) {
      setState(() => error = '只有群主可以修改此设置');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final manager = OpenIM.iMManager.groupManager;
      final members = await manager.getGroupMembersInfo(
          groupID: permission.groupID, userIDList: [permission.sdkAccount]);
      if (!current) return;
      if (!members.any((m) =>
          m.userID == permission.sdkAccount &&
          m.roleLevel == GroupRoleLevel.owner)) {
        throw StateError('owner permission changed');
      }
      final groups =
          await manager.getGroupsInfo(groupIDList: [permission.groupID]);
      if (!current) return;
      final latest = groups.firstWhere((g) => g.groupID == permission.groupID);
      final ex = GroupHistoryPolicy.merge(latest.ex, enabled);
      await manager
          .setGroupInfo(GroupInfo(groupID: permission.groupID, ex: ex));
      if (!current) return;
      latest.ex = ex;
      widget.logic.applyGroupInfo(latest);
      widget.logic.imLogic.groupInfoUpdatedSubject.add(latest);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => error = '保存失败，请确认群主权限后重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: '新成员历史消息',
        children: [
          SettingsGroup(children: [
            for (final value in [true, false])
              Semantics(
                selected: enabled == value,
                inMutuallyExclusiveGroup: true,
                child: SettingsCell(
                  title: value ? '允许查看入群前消息' : '仅查看入群后消息',
                  showArrow: false,
                  showDivider: value,
                  enabled: !busy,
                  trailing: SizedBox.square(
                    dimension: AppTokens.s6,
                    child: enabled == value
                        ? const Icon(Icons.check_rounded,
                            color: AppTokens.accent, size: AppTokens.s6)
                        : null,
                  ),
                  onTap: busy ? null : () => setState(() => enabled = value),
                ),
              ),
          ]),
          const SettingsSectionText('仅影响保存后新加入的成员；已有成员的历史权限不变。'),
          if (error != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.s4),
                child: Text(error!,
                    style: TextStyle(
                        color: settingsDanger(settingsIsDark(context)))),
              ),
            ),
          SettingsPrimaryButton(text: '保存', loading: busy, onPressed: save),
        ],
      );
}
