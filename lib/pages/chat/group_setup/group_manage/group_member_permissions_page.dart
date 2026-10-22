import '../../../channels/presentation/channel_labels.dart';
import 'package:openim_common/localization.dart';
import 'package:openim/routes/swipe_back/app_page_route.dart';
import 'dart:async';
import '../../../../core/controller/im_controller.dart';
import '../../../../core/im_callback.dart';
import '../../group/identity/group_member_identity_source.dart';
import 'package:flutter/cupertino.dart';
import '../group_member_order.dart';
import 'group_member_permission_session.dart';
import '../../group/permissions/group_mute.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

enum MemberPermissionMode { admins, muted, addAdmin, addMuted }

class GroupMemberPermissionsPage extends StatefulWidget {
  const GroupMemberPermissionsPage(
      {super.key,
      required this.groupID,
      required this.owner,
      this.isChannel = false,
      this.mode = MemberPermissionMode.admins});
  final MemberPermissionMode mode;
  final String groupID;
  final bool owner;
  final bool isChannel;
  @override
  State<GroupMemberPermissionsPage> createState() =>
      _GroupMemberPermissionsPageState();
}

class _GroupMemberPermissionsPageState extends State<GroupMemberPermissionsPage>
    with WidgetsBindingObserver {
  late final _permissions = GroupMemberPermissionSession(
      groupID: widget.groupID, owner: widget.owner);
  bool get _active => mounted && _permissions.active;
  bool get _owner => _permissions.owner;
  bool get _canManage => _permissions.canManage;
  final _subscriptions = <StreamSubscription>[];
  final _removed = <String>{};
  Future<void>? _permissionRefresh;
  final members = <GroupMembersInfo>[];
  late MemberPermissionMode mode = widget.mode;
  final _selected = <String, GroupMembersInfo>{};
  final _completed = <GroupMembersInfo>[];
  bool _batchSubmitting = false;
  bool get picking =>
      mode == MemberPermissionMode.addAdmin ||
      mode == MemberPermissionMode.addMuted;
  List<GroupMembersInfo> get displayedMembers => members.where((m) {
        final muted = m.roleLevel != GroupRoleLevel.owner &&
            GroupMute.active(m.muteEndTime,
                nowMilliseconds: DateTime.now().millisecondsSinceEpoch);
        if (mode == MemberPermissionMode.admins)
          return m.roleLevel == GroupRoleLevel.admin;
        if (mode == MemberPermissionMode.muted) return muted;
        if (m.userID == OpenIM.iMManager.userID ||
            m.roleLevel == GroupRoleLevel.owner) return false;
        if (mode == MemberPermissionMode.addAdmin)
          return m.roleLevel == GroupRoleLevel.member;
        return !muted && (_owner || m.roleLevel == GroupRoleLevel.member);
      }).toList();

  Future<void> addMember() async {
    if (!_active || !_canManage) return;
    final permissionRevision = _permissions.revision;
    final result = await Navigator.of(context).push<List<GroupMembersInfo>>(
        AppMaterialPageRoute(
            builder: (_) => GroupMemberPermissionsPage(
                groupID: widget.groupID,
                owner: _owner,
                isChannel: widget.isChannel,
                mode: mode == MemberPermissionMode.admins
                    ? MemberPermissionMode.addAdmin
                    : MemberPermissionMode.addMuted)));
    if (_active && _permissions.current(permissionRevision)) {
      for (final member in result ?? <GroupMembersInfo>[]) {
        _latestMembers[member.userID!] = member;
      }
      searchChanged(searchController.text);
      load();
    }
  }

  bool loading = false, more = true, failed = false;
  String? busy;
  final searchController = TextEditingController();
  Timer? _debounce;
  Timer? _muteExpiry;
  final _muteOverrides = <String, int>{};
  final _latestMembers = <String, GroupMembersInfo>{};
  final _memberRevisions = <String, int>{};

  void _scheduleExpiry() {
    _muteExpiry?.cancel();
    final now = DateTime.now().millisecondsSinceEpoch;
    final ends = members
        .where((m) => m.roleLevel != GroupRoleLevel.owner)
        .map((m) => GroupMute.milliseconds(m.muteEndTime))
        .where((end) => end > now)
        .toList()
      ..sort();
    if (ends.isNotEmpty) {
      _muteExpiry = Timer(Duration(milliseconds: ends.first - now), () {
        if (!mounted) return;
        setState(() {});
        _scheduleExpiry();
      });
    }
  }

  void _memberChanged(GroupMembersInfo member) {
    if (!_active ||
        member.groupID != widget.groupID ||
        member.userID == null ||
        _removed.contains(member.userID)) return;
    if (_permissions.update(member)) {
      setState(_selected.clear);
    }
    _muteOverrides.remove(member.userID);
    _memberRevisions.update(member.userID!, (value) => value + 1,
        ifAbsent: () => 1);
    _latestMembers[member.userID!] = member;
    final index = members.indexWhere((m) => m.userID == member.userID);
    if (index >= 0 || query.isEmpty) {
      setState(() {
        if (index >= 0) {
          members[index] = member;
        } else {
          members.add(member);
        }
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
      query = graphemeTrim(text);
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
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _debounce?.cancel();
    _muteExpiry?.cancel();
    _permissions.close();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Get.isRegistered<IMController>()) {
      final im = Get.find<IMController>();
      _subscriptions.addAll([
        im.imSdkStatusPublishSubject.listen((status) {
          if (status.status == IMSdkStatus.syncEnded) {
            unawaited(_refreshPermission());
          }
        }),
        im.memberInfoChangedSubject.listen(_memberChanged),
        im.memberDeletedSubject.listen((member) {
          if (!_active || member.groupID != widget.groupID) return;
          if (member.userID == _permissions.userID) {
            _leave();
            return;
          }
          setState(() {
            final id = member.userID;
            if (id != null) _removed.add(id);
            members.removeWhere((m) => m.userID == id);
            _selected.remove(id);
            _latestMembers.remove(id);
            _muteOverrides.remove(id);
          });
          _scheduleExpiry();
        }),
        im.memberAddedSubject.listen((member) {
          if (!_active || member.groupID != widget.groupID) return;
          _removed.remove(member.userID);
          _memberChanged(member);
        }),
        im.joinedGroupDeletedSubject.listen((group) {
          if (group.groupID == widget.groupID) _leave();
        }),
        im.groupInfoUpdatedSubject.listen((group) {
          if (_permissions.updateGroup(group) && mounted)
            setState(_selected.clear);
        }),
      ]);
    }
    load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshPermission());
  }

  Future<void> _refreshPermission() => _permissionRefresh ??=
      _readPermission().whenComplete(() => _permissionRefresh = null);

  Future<void> _readPermission() async {
    if (!_active) return;
    final revision = _permissions.revision;
    final source = GroupMemberIdentitySource();
    try {
      final joined = await source.containsMember(
          groupID: widget.groupID, userID: _permissions.userID);
      if (!_active || !_permissions.current(revision)) return;
      if (!joined) {
        _leave();
        return;
      }
      final rows = await source
          .members(groupID: widget.groupID, userIDList: [_permissions.userID]);
      if (!_active || !_permissions.current(revision)) return;
      for (final row in rows) {
        _memberChanged(row);
      }
    } catch (_) {
      // An unavailable authority cannot prove departure or grant a new role.
    }
  }

  void _leave() {
    if (!mounted) return;
    _permissions.leave();
    _generation++;
    _debounce?.cancel();
    _muteExpiry?.cancel();
    setState(() {
      members.clear();
      _selected.clear();
      _latestMembers.clear();
      _muteOverrides.clear();
      loading = false;
      more = false;
    });
  }

  Future<void> load() async {
    if (!_active || loading || !more) return;
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
      if (!_active || generation != _generation) return;
      setState(() {
        _offset += page.length;
        final known = members.map((m) => m.userID).toSet();
        members.addAll(page
            .where((m) => !_removed.contains(m.userID) && known.add(m.userID))
            .map((m) {
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

  Future<bool> change(GroupMembersInfo member, int action,
      {bool batch = false}) async {
    if (!_active ||
        !_canManage ||
        busy != null ||
        _removed.contains(member.userID) ||
        member.userID == _permissions.userID ||
        member.roleLevel == GroupRoleLevel.owner ||
        (action == -1
            ? !_owner
            : (!_owner && member.roleLevel != GroupRoleLevel.member)))
      return false;
    final permissionRevision = _permissions.revision;
    final memberRevision = _memberRevisions[member.userID];
    bool current() =>
        _active &&
        _permissions.current(permissionRevision) &&
        _memberRevisions[member.userID] == memberRevision &&
        !_removed.contains(member.userID);
    setState(() => busy = member.userID);
    try {
      if (action == -1) {
        if (!_owner) return false;
        final role = member.roleLevel == GroupRoleLevel.admin
            ? GroupRoleLevel.member
            : GroupRoleLevel.admin;
        await OpenIM.iMManager.groupManager.setGroupMemberInfo(
            groupMembersInfo: SetGroupMemberInfo(
                groupID: widget.groupID,
                userID: member.userID!,
                roleLevel: role));
        if (!current()) return false;
        final updated = GroupMembersInfo.fromJson(member.toJson())
          ..groupID = widget.groupID
          ..roleLevel = role;
        // Publish only after the server accepts the change. A local SDK read
        // immediately afterwards can still return the previous role.
        if (mounted) _memberChanged(updated);
        if (Get.isRegistered<IMController>()) {
          Get.find<IMController>().memberInfoChangedSubject.addSafely(updated);
        }
        if (batch) _completed.add(updated);
        if (picking && mounted && !batch) Navigator.of(context).pop([updated]);
      } else {
        await OpenIM.iMManager.groupManager.changeGroupMemberMute(
            groupID: widget.groupID, userID: member.userID!, seconds: action);
        if (!current()) return false;
        // The SDK's immediate read may still contain the old local-cache value.
        final end = GroupMute.afterSeconds(action,
            nowMilliseconds: DateTime.now().millisecondsSinceEpoch);
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
        if (picking && mounted) Navigator.of(context).pop([updated]);
      }
    } catch (error) {
      if (current()) IMViews.showErrorToast(error);
      return false;
    } finally {
      if (mounted) setState(() => busy = null);
    }
    return true;
  }

  Future<void> _submitAdmins() async {
    if (_batchSubmitting || !_owner || _selected.isEmpty) return;
    setState(() => _batchSubmitting = true);
    for (final member in _selected.values.toList()) {
      if (!_active || !_owner) break;
      final current = _latestMembers[member.userID] ?? member;
      if (current.roleLevel != GroupRoleLevel.member ||
          await change(current, -1, batch: true)) {
        if (mounted) setState(() => _selected.remove(member.userID));
      }
    }
    if (!mounted) return;
    setState(() => _batchSubmitting = false);
    if (_active && _owner && _selected.isEmpty)
      Navigator.of(context).pop(_completed);
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
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(label, style: Styles.ts_8E9AB0_14sp)),
            ...children,
          ]),
        );
    Widget memberRow(GroupMembersInfo member, {bool removable = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            AvatarView(
                width: 44,
                height: 44,
                isCircle: true,
                url: member.faceURL,
                text: member.nickname),
            const SizedBox(width: 12),
            Expanded(
                child: Text(member.nickname ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Styles.ts_0C1C33_17sp)),
            if (removable &&
                member.userID != OpenIM.iMManager.userID &&
                member.roleLevel != GroupRoleLevel.owner &&
                (_owner ||
                    (_canManage &&
                        mutedList &&
                        member.roleLevel == GroupRoleLevel.member)))
              IconButton(
                tooltip: mutedList ? '解除禁言' : AppCopy.text('移除管理员'),
                onPressed: busy == null
                    ? () => change(member, mutedList ? 0 : -1)
                    : null,
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
          card(channelLabel(StrRes.groupOwner, channel: widget.isChannel),
              [for (final member in owners) memberRow(member)]),
        card(
            '${mutedList ? AppCopy.text('禁言成员') : AppCopy.text('管理员')} (${admins.length})',
            [
              if (_owner || (mutedList && _canManage))
                InkWell(
                  onTap: busy == null ? addMember : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(children: [
                      Icon(Icons.add_circle_outline, color: Styles.c_0089FF),
                      const SizedBox(width: 12),
                      Text(
                          mutedList
                              ? AppCopy.text('添加禁言成员')
                              : AppCopy.text('添加管理员'),
                          style: Styles.ts_0089FF_17sp),
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
  Widget build(BuildContext context) => PopScope(
      canPop: !_batchSubmitting,
      child: Scaffold(
        backgroundColor: mode == MemberPermissionMode.addAdmin
            ? Styles.c_FFFFFF
            : Styles.c_F8F9FA,
        appBar: GlassAppBar(
          toolbarHeight: kToolbarHeight,
          centerTitle: true,
          backgroundColor: mode == MemberPermissionMode.addAdmin
              ? Styles.c_FFFFFF
              : Styles.c_F8F9FA,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: _batchSubmitting
                ? null
                : () => Navigator.of(context).pop(_completed),
            icon: Icon(CupertinoIcons.back, color: Styles.c_0089FF, size: 24),
          ),
          title: Text(
              (mode == MemberPermissionMode.addAdmin
                      ? 'sdkMakeAdmin'
                      : mode == MemberPermissionMode.addMuted
                          ? 'sdkMute'
                          : mode == MemberPermissionMode.admins
                              ? AppCopy.text('设置管理员')
                              : 'sdkMutedList')
                  .tr,
              style: Styles.ts_0C1C33_17sp_semibold),
          actions: [
            if (mode == MemberPermissionMode.addAdmin)
              TextButton(
                onPressed: _batchSubmitting || _selected.isEmpty || !_owner
                    ? null
                    : _submitAdmins,
                child: Text(_batchSubmitting
                    ? AppCopy.text('设置中…')
                    : AppCopy.format('确定（{#0}）', [_selected.length])),
              ),
          ],
        ),
        body: SafeArea(
            top: false,
            child: !picking
                ? _adminCards()
                : Column(children: [
                    if (!picking &&
                        (_owner || mode == MemberPermissionMode.muted))
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
                    if (displayedMembers.isEmpty &&
                        !loading &&
                        !failed &&
                        !more)
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
                    if (displayedMembers.isNotEmpty ||
                        loading ||
                        failed ||
                        more)
                      Expanded(
                          child: ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color:
                                                              Styles.c_0089FF)),
                                            )
                                          : const SizedBox.shrink();
                                }
                                final member = displayedMembers[index];
                                final canEdit = _canManage &&
                                    member.userID != OpenIM.iMManager.userID &&
                                    member.roleLevel != GroupRoleLevel.owner &&
                                    (_owner ||
                                        member.roleLevel ==
                                            GroupRoleLevel.member);
                                final muted =
                                    member.roleLevel != GroupRoleLevel.owner &&
                                        GroupMute.active(member.muteEndTime,
                                            nowMilliseconds: DateTime.now()
                                                .millisecondsSinceEpoch);
                                final name = graphemeTrim(member.nickname ?? '')
                                        .isNotEmpty
                                    ? graphemeTrim(member.nickname!)
                                    : member.userID ?? '';
                                final role = member.roleLevel ==
                                        GroupRoleLevel.owner
                                    ? channelLabel(StrRes.groupOwner,
                                        channel: widget.isChannel)
                                    : member.roleLevel == GroupRoleLevel.admin
                                        ? 'sdkAdmin'.tr
                                        : channelLabel(StrRes.groupMember,
                                            channel: widget.isChannel);
                                if (mode == MemberPermissionMode.addAdmin) {
                                  final selected =
                                      _selected.containsKey(member.userID);
                                  final enabled =
                                      !_batchSubmitting && _owner && canEdit;
                                  return Semantics(
                                    checked: selected,
                                    enabled: enabled,
                                    child: Material(
                                      color: Styles.c_FFFFFF,
                                      child: InkWell(
                                        key: ValueKey(
                                            'admin-picker-row-${member.userID}'),
                                        onTap: !enabled
                                            ? null
                                            : () => setState(() {
                                                  if (selected) {
                                                    _selected
                                                        .remove(member.userID);
                                                  } else {
                                                    _selected[member.userID!] =
                                                        member;
                                                  }
                                                }),
                                        child: Column(children: [
                                          Padding(
                                            padding: EdgeInsets.symmetric(
                                                vertical: AppTokens.s3),
                                            child: Row(children: [
                                              ChatRadio(
                                                  checked: selected,
                                                  enabled: enabled),
                                              SizedBox(width: AppTokens.s3),
                                              AvatarView(
                                                  width: 44,
                                                  height: 44,
                                                  isCircle: true,
                                                  text: name,
                                                  url: member.faceURL),
                                              SizedBox(width: AppTokens.s3),
                                              Expanded(
                                                  child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(name,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: Styles
                                                          .ts_0C1C33_17sp),
                                                  SizedBox(
                                                      height: AppTokens.s2),
                                                  Text(role,
                                                      style: Styles
                                                          .ts_8E9AB0_14sp),
                                                ],
                                              )),
                                            ]),
                                          ),
                                          if (index <
                                              displayedMembers.length - 1)
                                            Divider(
                                              height: 1,
                                              thickness: 0.5,
                                              indent:
                                                  20.w + 44 + AppTokens.s3 * 2,
                                              color: AppTokens.border(
                                                  dark: Theme.of(context)
                                                          .brightness ==
                                                      Brightness.dark),
                                            ),
                                        ]),
                                      ),
                                    ),
                                  );
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Material(
                                    color: Styles.c_FFFFFF,
                                    borderRadius: BorderRadius.circular(12),
                                    clipBehavior: Clip.antiAlias,
                                    child: Column(children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            16, 14, 8, 14),
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
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w500,
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
                                                                ? Styles
                                                                    .c_8E9AB0
                                                                : Styles
                                                                    .c_0089FF)),
                                                    if (muted)
                                                      Text('sdkMuted'.tr,
                                                          style: TextStyle(
                                                              fontSize: 12,
                                                              color: Styles
                                                                  .c_FF381F)),
                                                  ]),
                                            ],
                                          )),
                                          if (canEdit)
                                            busy == member.userID
                                                ? Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            14),
                                                    child: SizedBox(
                                                        width: 20,
                                                        height: 20,
                                                        child:
                                                            CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                                color: Styles
                                                                    .c_0089FF)))
                                                : PopupMenuButton<int>(
                                                    tooltip:
                                                        'sdkMemberPermissions'
                                                            .tr,
                                                    icon: Icon(
                                                        CupertinoIcons.ellipsis,
                                                        color: Styles.c_8E9AB0,
                                                        size: 22),
                                                    color: Styles.c_FFFFFF,
                                                    shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(12)),
                                                    enabled: busy == null,
                                                    onSelected: (v) =>
                                                        change(member, v),
                                                    itemBuilder: (_) => [
                                                          if (_owner &&
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
                                                                    'sdkUnmute'
                                                                        .tr)),
                                                          if (mode ==
                                                              MemberPermissionMode
                                                                  .addMuted)
                                                            for (final seconds
                                                                in [
                                                              600,
                                                              3600,
                                                              86400
                                                            ])
                                                              PopupMenuItem(
                                                                  value:
                                                                      seconds,
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
      ));
}
