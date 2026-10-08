import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../sangong_scope.dart';
import '../widgets/authorization/privilege_route_guard.dart';
import 'sangong_profile_admin_layout.dart';
import 'sangong_profile_admin_panel.dart';
import 'sangong_profile_entry_scope.dart';
export 'sangong_profile_admin_panel.dart' show SangongProfilePanel;

class SangongInlineProfilePanel extends StatelessWidget {
  const SangongInlineProfilePanel(
      {super.key, required this.userID, this.nickname = ''});
  final String userID;
  final String nickname;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= 900) return const SizedBox.shrink();
    final entry = SangongProfileEntryScope.maybeOf(context);
    if (entry != null) {
      return entry.userID == userID
          ? SangongProfileEntryCard(userID: userID, nickname: nickname)
          : const SizedBox.shrink();
    }
    final runtime =
        context.dependOnInheritedWidgetOfExactType<SangongScope>()?.notifier;
    if (runtime?.canManage != true ||
        userID == runtime?.featureContext.currentUserID) {
      return const SizedBox.shrink();
    }
    return _mobileCard(
        context, SangongProfilePanel(userID: userID, nickname: nickname));
  }
}

Widget _mobileCard(BuildContext context, Widget child) => Padding(
    key: const ValueKey('sangong-profile-services'),
    padding: const EdgeInsets.only(bottom: AppTokens.s4),
    child: child);

/// Public loading/empty/error states use the same three forms as 99chat.
/// Only the authorized child owns private reports and mutation controls.
class SangongProfileEntryCard extends StatefulWidget {
  const SangongProfileEntryCard(
      {super.key,
      required this.userID,
      this.nickname = '',
      this.embedded = false});
  final String userID;
  final String nickname;
  final bool embedded;
  @override
  State<SangongProfileEntryCard> createState() =>
      _SangongProfileEntryCardState();
}

class _SangongProfileEntryCardState extends State<SangongProfileEntryCard> {
  final _points = TextEditingController();
  final _banker = TextEditingController();
  final _joint = TextEditingController();

  @override
  void dispose() {
    _points.dispose();
    _banker.dispose();
    _joint.dispose();
    super.dispose();
  }

  Future<void> _chooseGroup(SangongProfileEntryScope entry) async {
    Widget choices(BuildContext context) => SafeArea(
        key: const ValueKey('sangong-profile-group-chooser'),
        child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final group in entry.groups)
            ListTile(
                title: Text(group.groupName?.isNotEmpty == true
                    ? group.groupName!
                    : group.groupID),
                selected: group.groupID == entry.selectedGroupID,
                onTap: () => Navigator.pop(context, group.groupID)),
        ])));
    final selectionContext = entry.selectionContext;
    final selected = await showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        builder: selectionContext == null
            ? choices
            : (_) => SangongPrivilegeRouteGuard(
                featureContext: selectionContext,
                refreshOnEntry: false,
                requireCapabilitiesCurrent: false,
                scopeChanges: entry.selectionChanges,
                builder: choices));
    if (!mounted || selected == null) return;
    // A stale chooser must not target a replaced account/group scope.
    final latest = SangongProfileEntryScope.maybeOf(context);
    if (latest == null ||
        latest.userID != widget.userID ||
        latest.loading ||
        !latest.groups.any((group) => group.groupID == selected)) {
      return;
    }
    latest.onSelectGroup(selected);
  }

  @override
  Widget build(BuildContext context) {
    final entry = SangongProfileEntryScope.maybeOf(context);
    if (entry == null || entry.userID != widget.userID) {
      return const SizedBox.shrink();
    }
    final runtime =
        context.dependOnInheritedWidgetOfExactType<SangongScope>()?.notifier;
    final ready =
        !entry.loading && entry.error == null && runtime?.canManage == true;
    final content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (entry.groups.length > 1)
            Align(
                alignment: Alignment.center,
                child: TextButton(
                    onPressed: entry.loading ? null : () => _chooseGroup(entry),
                    child: Text(
                        entry.selectedGroupID == null ? '选择游戏群' : '切换游戏群'))),
          if (ready)
            SangongProfilePanel(
                userID: widget.userID,
                nickname: widget.nickname,
                embedded: widget.embedded)
          else
            SangongProfileAdminLayout(
                pointsController: _points,
                bankerController: _banker,
                jointController: _joint,
                loading: entry.loading,
                disabled: true,
                embedded: widget.embedded,
                error: entry.error,
                onRetry: entry.loading ? null : entry.onRetry),
        ]);
    return widget.embedded ? content : _mobileCard(context, content);
  }
}
