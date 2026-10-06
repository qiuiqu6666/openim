import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart' show AppTokens;

/// Public feedback only. A selection is returned before any permission read.
class SangongProfileLedgerUnavailable extends StatelessWidget {
  const SangongProfileLedgerUnavailable({
    super.key,
    required this.groups,
    required this.loading,
    this.error,
    this.selectedGroupID,
  });

  final List<GroupInfo> groups;
  final bool loading;
  final String? error, selectedGroupID;

  static const retry = SangongProfileLedgerChoice();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      key: const ValueKey('sangong-profile-ledger-unavailable'),
      color: AppTokens.surface(dark: dark),
      child: SafeArea(
        child: Column(children: [
          ListTile(
            title: const Text('游戏流水'),
            trailing: IconButton(
              tooltip: '关闭',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTokens.s5),
              child: Column(children: [
                Text(
                  error ??
                      (loading
                          ? '正在准备当前群的三公权限，请稍后重试'
                          : groups.length > 1 && selectedGroupID == null
                              ? '请选择游戏群以查看流水'
                              : '当前群尚未确认三公运营绑定，请重试'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTokens.textSecondary(dark: dark)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, retry),
                  child: const Text('重试'),
                ),
                if (groups.length > 1)
                  for (final group in groups)
                    ListTile(
                      title: Text(group.groupName?.isNotEmpty == true
                          ? group.groupName!
                          : group.groupID),
                      selected: group.groupID == selectedGroupID,
                      onTap: () => Navigator.pop(context,
                          SangongProfileLedgerChoice(groupID: group.groupID)),
                    ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// A null group ID asks the owning profile to refresh, after the sheet closes.
class SangongProfileLedgerChoice {
  const SangongProfileLedgerChoice({this.groupID});
  final String? groupID;
}
