import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/media_localization.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import '../../chat/group_setup/group_setup_logic.dart';
import 'group_personalization_editor.dart';
import 'group_personalization.dart';
import '../data/group_name_cache.dart';

class GroupPersonalizationPage extends StatefulWidget {
  const GroupPersonalizationPage({super.key, required this.logic});
  final GroupSetupLogic logic;
  @override
  State<GroupPersonalizationPage> createState() =>
      _GroupPersonalizationPageState();
}

class _GroupPersonalizationPageState extends State<GroupPersonalizationPage> {
  late final GroupSetupPermissionContext permission;
  late GroupPersonalization appearance;
  bool busy = false;
  String? error;
  bool get current =>
      mounted &&
      widget.logic.isPermissionContextCurrent(permission) &&
      widget.logic.isOwnerOrAdmin;

  @override
  void initState() {
    super.initState();
    permission = widget.logic.capturePermissionContext();
    appearance = GroupPersonalization.fromEx(widget.logic.groupInfo.value.ex);
  }

  Future<void> pickIcon() async {
    if (!current || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final assets = await AssetPicker.pickAssets(context,
          pickerConfig: AssetPickerConfig(
              textDelegate: AppMediaCopy.assets,
              maxAssets: 1,
              requestType: RequestType.image));
      if (!current || assets == null || assets.isEmpty) return;
      final file = await assets.first.file;
      if (!current || file == null) return;
      final result = await IMViews.uCropPic(file.path);
      if (!current) return;
      final url = result['url'];
      if (url is String && Uri.tryParse(url)?.scheme == 'https') {
        setState(() => appearance = GroupPersonalization(
            color: appearance.color,
            iconUrl: url,
            iconPosition: appearance.iconPosition));
      }
    } catch (_) {
      if (mounted) setState(() => error = '图标上传失败，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (!current || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final manager = OpenIM.iMManager.groupManager;
      final members = await manager.getGroupMembersInfo(
          groupID: permission.groupID, userIDList: [OpenIM.iMManager.userID]);
      if (!current) return;
      if (members.isEmpty ||
          (members.first.roleLevel != GroupRoleLevel.owner &&
              members.first.roleLevel != GroupRoleLevel.admin)) {
        throw StateError('只有群主和管理员可以设置群个性化');
      }
      final groups =
          await manager.getGroupsInfo(groupIDList: [permission.groupID]);
      if (!current) return;
      final latest = groups.firstWhere((g) => g.groupID == permission.groupID);
      final ex = appearance.mergeInto(latest.ex);
      await manager
          .setGroupInfo(GroupInfo(groupID: permission.groupID, ex: ex));
      if (!current) return;
      await GroupNameCache(permission.sdkAccount)
          .writeAppearance(permission.groupID, ex);
      if (!current) return;
      latest.ex = ex;
      widget.logic.applyGroupInfo(latest);
      widget.logic.imLogic.groupInfoUpdatedSubject.add(latest);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => error = '保存失败，请确认管理权限后重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => GroupPersonalizationEditor(
        name: widget.logic.groupInfo.value.groupName ?? '',
        avatarUrl: widget.logic.groupInfo.value.faceURL,
        appearance: appearance,
        busy: busy,
        error: error,
        onChanged: (value) => setState(() => appearance = value),
        onUpload: pickIcon,
        onSave: save,
      );
}
