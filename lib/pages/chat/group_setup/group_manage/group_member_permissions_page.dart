import 'dart:async';
import '../../../../core/controller/im_controller.dart';
import 'package:flutter/cupertino.dart';
import '../group_member_order.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

enum MemberPermissionMode { admins, muted, addAdmin, addMuted }

class GroupMemberPermissionsPage extends StatefulWidget {
  const GroupMemberPermissionsPage(
      {super.key,
      required this.groupID,
      required this.owner,
      this.mode = MemberPermissionMode.admins});
  final MemberPermissionMode mode;
  final String groupID;
  final bool owner;
  @override
  State<GroupMemberPermissionsPage> createState() =>
      _GroupMemberPermissionsPageState();
}

class _GroupMemberPermissionsPageState
    extends State<GroupMemberPermissionsPage> {
  final members = <GroupMembersInfo>[];
  late MemberPermissionMode mode = widget.mode;
  bool get picking =>
      mode == MemberPermissionMode.addAdmin ||
      mode == MemberPermissionMode.addMuted;
  List<GroupMembersInfo> get displayedMembers => members.where((m) {
        final muted = (m.muteEndTime ?? 0) >
            DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (mode == MemberPermissionMode.admins)
          return m.roleLevel == GroupRoleLevel.admin;
        if (mode == MemberPermissionMode.muted) return muted;
        if (m.userID == OpenIM.iMManager.userID ||
            m.roleLevel == GroupRoleLevel.owner) return false;
        if (mode == MemberPermissionMode.addAdmin)
          return m.roleLevel == GroupRoleLevel.member;
        return !muted && (widget.owner || m.roleLevel == GroupRoleLevel.member);
      }).toList();

  Future<void> addMember() async {
    final result = await Navigator.of(context).push<GroupMembersInfo>(
        MaterialPageRoute(
            builder: (_) => GroupMemberPermissionsPage(
                groupID: widget.groupID,
                owner: widget.owner,
                mode: mode == MemberPermissionMode.admins
                    ? MemberPermissionMode.addAdmin
                    : MemberPermissionMode.addMuted)));
    if (mounted) {
      if (result != null) _latestMembers[result.userID!] = result;
      searchChanged(searchController.text);
      load();
    }
  }

  bool loading = false, more = true, failed = false;
  String? busy;
  final searchController = TextEditingController();
  Timer? _debounce;
  Timer? _muteExpiry;
  StreamSubscription<GroupMembersInfo>? _memberChanges;
  final _muteOverrides = <String, int>{};
  final _latestMembers = <String, GroupMembersInfo>{};

  void _scheduleExpiry() {
    _muteExpiry?.cancel();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final ends = members
        .map((m) => m.muteEndTime ?? 0)
        .where((end) => end > now)
        .toList()
      ..sort();
    if (ends.isNotEmpty) {
      _muteExpiry = Timer(Duration(seconds: ends.first - now), () {
        if (!mounted) return;
        setState(() {});
        _scheduleExpiry();
      });
    }
  }

  void _memberChanged(GroupMembersInfo member) {
    if (!mounted || member.groupID != widget.groupID || member.userID == null)
      return;
    _muteOverrides.remove(member.userID);
    _latestMembers[member.userID!] = member;
    final index = members.indexWhere((m) => m.userID == member.userID);
    if (index >= 0) {
      setState(() {
        members[index] = member;
        members.sort(compareGroupMembers);
      });
      _scheduleExpiry();
    }
  }

  String query = '';
  int _generation = 0, _offset = 0;

  void searchChanged(String text) {
    _debounce?.cancel();
    _generation++;
    setState(() {
      query = text.trim();
      members.clear();
      _offset = 0;
      more = true;
      failed = false;
      loading = false;
    });
    _debounce = Timer(const Duration(milliseconds: 300), load);
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    _muteExpiry?.cancel();
    _memberChanges?.cancel();
    searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<IMController>()) {
      _memberChanges = Get.find<IMController>()
          .memberInfoChangedSubject
          .listen(_memberChanged);
    }
    load();
  }

  Future<void> load() async {
    if (loading) return;
    _debounce?.cancel();
    final generation = _generation;
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final manager = OpenIM.iMManager.groupManager;
      final page = query.isEmpty
          ? await manager.getGroupMemberList(
              groupID: widget.groupID, offset: _offset, count: 100, filter: 0)
          : await manager.searchGroupMembers(
              groupID: widget.groupID,
              keywordList: [query],
              isSearchUserID: true,
              isSearchMemberNickname: true,
              offset: _offset,
              count: 100);
      if (!mounted || generation != _generation) return;
      setState(() {
        _offset += page.length;
        members.addAll(page.map((m) {
          final current = _latestMembers[m.userID] ?? m;
          if (_muteOverrides.containsKey(m.userID))
            current.muteEndTime = _muteOverrides[m.userID];
          return current;
        }));
        members.sort(compareGroupMembers);
        more = page.length == 100;
      });
      _scheduleExpiry();
    } catch (_) {
      if (mounted && generation == _generation) setState(() => failed = true);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => loading = false);
        // Muted members have no dedicated filter in this SDK. Scan subsequent
        // pages so matches beyond the first page are included.
        if (more && !failed) unawaited(load());
      }
    }
  }

  Future<void> change(GroupMembersInfo member, int action) async {
    if (busy != null) return;
    setState(() => busy = member.userID);
    try {
      if (action == -1) {
        if (!widget.owner) return;
        final role = member.roleLevel == GroupRoleLevel.admin
            ? GroupRoleLevel.member
            : GroupRoleLevel.admin;
        await OpenIM.iMManager.groupManager.setGroupMemberInfo(
            groupMembersInfo: SetGroupMemberInfo(
                groupID: widget.groupID,
                userID: member.userID!,
                roleLevel: role));
        final updated = GroupMembersInfo.fromJson(member.toJson())
          ..groupID = widget.groupID
          ..roleLevel = role;
        // Publish only after the server accepts the change. A local SDK read
        // immediately afterwards can still return the previous role.
        if (mounted) _memberChanged(updated);
        if (Get.isRegistered<IMController>()) {
          Get.find<IMController>().memberInfoChangedSubject.addSafely(updated);
        }
        if (picking && mounted) Navigator.of(context).pop(updated);
      } else {
        await OpenIM.iMManager.groupManager.changeGroupMemberMute(
            groupID: widget.groupID, userID: member.userID!, seconds: action);
        if (!mounted) return;
        // The SDK's immediate read may still contain the old local-cache value.
        final end = action == 0
            ? 0
            : DateTime.now().millisecondsSinceEpoch ~/ 1000 + action;
        _muteOverrides[member.userID!] = end;
        setState(() {
          for (final current
              in members.where((m) => m.userID == member.userID)) {
            current.muteEndTime = end;
          }
        });
        final updated = GroupMembersInfo.fromJson(member.toJson())
          ..groupID = widget.groupID
          ..muteEndTime = end;
        _latestMembers[member.userID!] = updated;
        if (Get.isRegistered<IMController>())
          Get.find<IMController>().memberInfoChangedSubject.addSafely(updated);
        _scheduleExpiry();
        if (picking && mounted) Navigator.of(context).pop(updated);
        return;
      }
    } catch (error) {
      IMViews.showToast(error.toString());
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  Widget _adminCards() {
    final mutedList = mode == MemberPermissionMode.muted;
    final owners = members.where((m) => m.roleLevel == GroupRoleLevel.owner);
    final admins = displayedMembers;
    Widget card(String label, List<Widget> children) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      decoration: BoxDecoration(
        color: Styles.c_FFFFFF,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.only(bottom: 10),
          child: Text(label, style: Styles.ts_8E9AB0_14sp)),
        ...children,
      ]),
    );
    Widget memberRow(GroupMembersInfo member, {bool removable = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          AvatarView(width: 44, height: 44, isCircle: true,
            url: member.faceURL, text: member.nickname),
          const SizedBox(width: 12),
          Expanded(child: Text(member.nickname ?? '', maxLines: 1,
            overflow: TextOverflow.ellipsis, style: Styles.ts_0C1C33_17sp)),
          if (removable && member.userID != OpenIM.iMManager.userID &&
              member.roleLevel != GroupRoleLevel.owner &&
              (widget.owner || (mutedList && member.roleLevel == GroupRoleLevel.member)))
            IconButton(
              tooltip: mutedList ? '解除禁言' : '移除管理员',
              onPressed: busy == null ? () => change(member, mutedList ? 0 : -1) : null,
              icon: Icon(Icons.remove_circle_outline, color: Styles.c_FF381F),
            ),
        ]),
      );
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      children: [
        if (loading || busy != null)
          LinearProgressIndicator(color: Styles.c_0089FF),
        if (!mutedList)
          card(StrRes.groupOwner, [for (final member in owners) memberRow(member)]),
        card('${mutedList ? '禁言成员' : '管理员'} (${admins.length})', [
          if (widget.owner || mutedList)
            InkWell(
              onTap: busy == null ? addMember : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(children: [
                  Icon(Icons.add_circle_outline, color: Styles.c_0089FF),
                  const SizedBox(width: 12),
                  Text(mutedList ? '添加禁言成员' : '添加管理员', style: Styles.ts_0089FF_17sp),
                ]),
              ),
            ),
          for (final member in admins) memberRow(member, removable: true),
        ]),
        if (failed)
          TextButton(onPressed: load, child: Text('chatSearchRetry'.tr)),
      ],
    );
  }

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
            icon: Icon(CupertinoIcons.back, color: Styles.c_0089FF, size: 24),
          ),
          title: Text(
              (mode == MemberPermissionMode.addAdmin
                      ? 'sdkMakeAdmin'
                      : mode == MemberPermissionMode.addMuted
                          ? 'sdkMute'
                          : mode == MemberPermissionMode.admins
                              ? '设置管理员'
                              : 'sdkMutedList')
                  .tr,
              style: Styles.ts_0C1C33_17sp_semibold),
        ),
        body: SafeArea(
            top: false,
            child: !picking ? _adminCards() : Column(children: [
              if (!picking &&
                  (widget.owner || mode == MemberPermissionMode.muted))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: busy == null ? addMember : null,
                      icon: const Icon(Icons.add, size: 20),
                      label: Text((mode == MemberPermissionMode.admins
                              ? 'sdkMakeAdmin'
                              : 'sdkMute')
                          .tr),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Styles.c_0089FF,
                        side: BorderSide(color: Styles.c_0089FF),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: SearchBox(
                  enabled: true,
                  controller: searchController,
                  hintText: 'groupMemberSearchHint'.tr,
                  onChanged: searchChanged,
                  onCleared: () => searchChanged(''),
                  onSubmitted: (value) {
                    searchChanged(value);
                    load();
                  },
                ),
              ),
              if (displayedMembers.isEmpty && !loading && !failed && !more)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.group_outlined,
                            size: 48, color: Styles.c_8E9AB0),
                        const SizedBox(height: 12),
                        Text('chatSearchEmpty'.tr,
                            style: Styles.ts_8E9AB0_14sp),
                      ],
                    ),
                  ),
                ),
              SizedBox(
                  height: 2,
                  child: loading || busy != null
                      ? LinearProgressIndicator(color: Styles.c_0089FF)
                      : null),
              if (displayedMembers.isNotEmpty || loading || failed || more)
                Expanded(
                    child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: displayedMembers.length + 1,
                        itemBuilder: (_, index) {
                          if (index == displayedMembers.length) {
                            return failed
                                ? TextButton(
                                    onPressed: loading ? null : load,
                                    child: Text('chatSearchRetry'.tr))
                                : loading || more
                                    ? Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Center(
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Styles.c_0089FF)),
                                      )
                                    : const SizedBox.shrink();
                          }
                          final member = displayedMembers[index];
                          final canEdit = member.userID !=
                                  OpenIM.iMManager.userID &&
                              member.roleLevel != GroupRoleLevel.owner &&
                              (widget.owner ||
                                  member.roleLevel == GroupRoleLevel.member);
                          final muted = (member.muteEndTime ?? 0) >
                              DateTime.now().millisecondsSinceEpoch ~/ 1000;
                          final name =
                              member.nickname?.trim().isNotEmpty == true
                                  ? member.nickname!.trim()
                                  : member.userID ?? '';
                          final role = member.roleLevel == GroupRoleLevel.owner
                              ? StrRes.groupOwner
                              : member.roleLevel == GroupRoleLevel.admin
                                  ? 'sdkAdmin'.tr
                                  : StrRes.groupMember;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: Styles.c_FFFFFF,
                              borderRadius: BorderRadius.circular(12),
                              clipBehavior: Clip.antiAlias,
                              child: Column(children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 14, 8, 14),
                                  child: Row(children: [
                                    AvatarView(
                                        width: 44,
                                        height: 44,
                                        isCircle: true,
                                        text: name,
                                        url: member.faceURL),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                                color: Styles.c_0C1C33)),
                                        const SizedBox(height: 6),
                                        Wrap(
                                            spacing: 8,
                                            runSpacing: 4,
                                            children: [
                                              Text(role,
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: member.roleLevel ==
                                                              GroupRoleLevel
                                                                  .member
                                                          ? Styles.c_8E9AB0
                                                          : Styles.c_0089FF)),
                                              if (muted)
                                                Text('sdkMuted'.tr,
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        color:
                                                            Styles.c_FF381F)),
                                            ]),
                                      ],
                                    )),
                                    if (canEdit)
                                      busy == member.userID
                                          ? Padding(
                                              padding: const EdgeInsets.all(14),
                                              child: SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color:
                                                              Styles.c_0089FF)))
                                          : PopupMenuButton<int>(
                                              tooltip:
                                                  'sdkMemberPermissions'.tr,
                                              icon: Icon(
                                                  CupertinoIcons.ellipsis,
                                                  color: Styles.c_8E9AB0,
                                                  size: 22),
                                              color: Styles.c_FFFFFF,
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          12)),
                                              enabled: busy == null,
                                              onSelected: (v) =>
                                                  change(member, v),
                                              itemBuilder: (_) => [
                                                    if (widget.owner &&
                                                        (mode ==
                                                                MemberPermissionMode
                                                                    .admins ||
                                                            mode ==
                                                                MemberPermissionMode
                                                                    .addAdmin))
                                                      PopupMenuItem(
                                                          value: -1,
                                                          child: Text(member
                                                                      .roleLevel ==
                                                                  GroupRoleLevel
                                                                      .admin
                                                              ? 'sdkRemoveAdmin'
                                                                  .tr
                                                              : 'sdkMakeAdmin'
                                                                  .tr)),
                                                    if (muted)
                                                      PopupMenuItem(
                                                          value: 0,
                                                          child: Text(
                                                              'sdkUnmute'.tr)),
                                                    if (mode ==
                                                        MemberPermissionMode
                                                            .addMuted)
                                                      for (final seconds in [
                                                        600,
                                                        3600,
                                                        86400
                                                      ])
                                                        PopupMenuItem(
                                                            value: seconds,
                                                            child: Text(
                                                                '${'sdkMute'.tr} ${seconds ~/ 60} ${'sdkMinutes'.tr}')),
                                                  ]),
                                  ]),
                                ),
                              ]),
                            ),
                          );
                        })),
            ])),
      );
}
