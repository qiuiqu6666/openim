import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import '../../../../routes/app_navigator.dart';
import '../../../contacts/group_profile_panel/group_profile_panel_logic.dart';
import '../../../contacts/search/contact_search_source.dart';

class AnnouncementMentionLink {
  static bool _resolvingMention = false;

  static Future<void> open(BuildContext sheetContext, String mention,
      {bool dismissSheet = false}) async {
    if (_resolvingMention) return;
    _resolvingMention = true;
    final owner = (OpenIM.iMManager.userID, DataSp.chatToken);
    bool current() =>
        sheetContext.mounted &&
        owner == (OpenIM.iMManager.userID, DataSp.chatToken);
    try {
      final name = mention.substring(1);
      final account = normalizePublicAccountSearch(mention);
      final users = (await ContactSearchSource()
                  .users(account == null ? name : '@$account', 1) ??
              [])
          .where((user) =>
              user.userID?.isNotEmpty == true &&
              (user.userID == name ||
                  (account != null &&
                      normalizePublicAccountSearch(user.account ?? '') ==
                          account) ||
                  user.nickname == name))
          .toList();
      if (!sheetContext.mounted || !current()) return;
      final groups = <GroupInfo>[];
      try {
        groups.addAll((await OpenIM.iMManager.groupManager.getGroupsInfo(
          groupIDList: [name],
        ))
            .where((group) => group.groupID == name));
      } catch (_) {
        // A user mention need not be a valid group ID.
      }
      if (!sheetContext.mounted || !current()) return;
      final options = <({String label, VoidCallback open})>[
        for (final user in users)
          (
            label:
                '用户：${user.nickname ?? name}（${user.account ?? user.userID}）',
            open: () => AppNavigator.startUserProfilePane(
                userID: user.userID!,
                nickname: user.nickname,
                faceURL: user.faceURL)
          ),
        for (final group in groups)
          (
            label: '群聊：${group.groupName ?? name}',
            open: () => AppNavigator.startGroupProfilePanel(
                groupID: group.groupID, joinGroupMethod: JoinGroupMethod.search)
          ),
      ];
      if (options.isEmpty) {
        IMViews.showToast('未找到对应用户或群聊');
        return;
      }
      var index = 0;
      if (options.length > 1) {
        final selected = await showDialog<int>(
          context: sheetContext,
          builder: (context) => SimpleDialog(
            title: const Text('请选择要查看的资料'),
            children: [
              for (var i = 0; i < options.length; i++)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, i),
                  child: Text(options[i].label),
                ),
            ],
          ),
        );
        if (selected == null) return;
        index = selected;
      }
      if (!sheetContext.mounted || !current()) return;
      if (dismissSheet) Navigator.pop(sheetContext);
      options[index].open();
    } catch (error) {
      if (current()) IMViews.showToast('暂时无法打开资料，请稍后重试');
    } finally {
      _resolvingMention = false;
    }
  }
}
