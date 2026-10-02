import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../routes/app_navigator.dart';
import 'common_groups_store.dart';

class CommonGroupsPage extends StatefulWidget {
  const CommonGroupsPage(
      {super.key, required this.peerUserID, this.store, this.onOpenGroup});
  final String peerUserID;
  final CommonGroupsStore? store;
  final Future<void> Function(GroupInfo)? onOpenGroup;

  @override
  State<CommonGroupsPage> createState() => _CommonGroupsPageState();
}

class _CommonGroupsPageState extends State<CommonGroupsPage> {
  // SDK GroupStatus.dismissed is 2; this SDK version does not export the enum.
  static const _dismissedGroupStatus = 2;
  late final CommonGroupsStore _store;
  final _scroll = ScrollController();
  bool _opening = false;
  bool _pullRefreshing = false;
  final _search = TextEditingController();
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? CommonGroupsStore(widget.peerUserID);
    _scroll.addListener(() {
      if (_scroll.position.pixels > 0 &&
          _scroll.position.extentAfter < AppTokens.s8 * 6 &&
          !_pullRefreshing &&
          !_store.failed) {
        _store.loadMore();
      }
    });
    _store.refresh();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    if (widget.store == null) _store.dispose();
    super.dispose();
  }

  Future<void> _refreshFromPull() async {
    setState(() => _pullRefreshing = true);
    try {
      await _store.refresh();
    } finally {
      if (mounted) setState(() => _pullRefreshing = false);
    }
  }

  Future<void> _open(GroupInfo group) async {
    if (_opening) return;
    setState(() => _opening = true);
    final owner = DataSp.userID;
    try {
      if (widget.onOpenGroup != null) {
        await widget.onOpenGroup!(group);
        return;
      }
      final id = group.groupID;
      final joined =
          await OpenIM.iMManager.groupManager.isJoinedGroup(groupID: id);
      final infos =
          await OpenIM.iMManager.groupManager.getGroupsInfo(groupIDList: [id]);
      if (!mounted || DataSp.userID != owner) return;
      final current = infos.where((info) => info.groupID == id).firstOrNull;
      if (!joined ||
          current == null ||
          current.status == _dismissedGroupStatus) {
        IMViews.showToast('profileCommonGroupsUnavailable'.tr);
        await _store.refresh();
        return;
      }
      final conversation = await OpenIM.iMManager.conversationManager
          .getOneConversation(sourceID: id, sessionType: current.sessionType);
      if (!mounted || DataSp.userID != owner) return;
      await AppNavigator.startChat(
          conversationInfo: conversation, offUntilHome: false);
      if (mounted && DataSp.userID == owner) await _store.refresh();
    } catch (_) {
      if (mounted && DataSp.userID == owner) {
        IMViews.showToast('profileCommonGroupsOpenFailed'.tr);
        await _store.refresh();
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Styles.c_F8F9FA,
        appBar: TitleBar.back(title: 'profileCommonGroups'.tr),
        body: SafeArea(
            top: false,
            child: Column(children: [
              Material(
                  color: Styles.c_FFFFFF,
                  child: SearchBox(
                    controller: _search,
                    enabled: true,
                    hintText: 'profileCommonGroupsSearch'.tr,
                    height: AppTokens.s7 + AppTokens.s6,
                    backgroundColor: Styles.c_F0F2F6,
                    textStyle: Styles.ts_0C1C33_14sp,
                    hintStyle: Styles.ts_8E9AB0_14sp,
                    margin: const EdgeInsets.symmetric(
                        horizontal: AppTokens.s5, vertical: AppTokens.s4),
                    onChanged: (value) =>
                        setState(() => _keyword = value.trim().toLowerCase()),
                    onCleared: () => setState(() => _keyword = ''),
                  )),
              Expanded(
                  child: AnimatedBuilder(
                animation: _store,
                builder: (context, _) {
                  final groups = _keyword.isEmpty
                      ? _store.items
                      : _store.items
                          .where((group) =>
                              (group.groupName ?? '')
                                  .toLowerCase()
                                  .contains(_keyword) ||
                              group.groupID.toLowerCase().contains(_keyword))
                          .toList();
                  return RefreshIndicator(
                    onRefresh: _refreshFromPull,
                    child: ListView.builder(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: groups.length + 1,
                      itemBuilder: (context, index) {
                        if (index == groups.length) {
                          return Column(children: [
                            if (_keyword.isNotEmpty &&
                                groups.isEmpty &&
                                !_store.busy &&
                                !_store.failed)
                              Padding(
                                  padding: const EdgeInsets.all(AppTokens.s5),
                                  child: Text('profileCommonGroupsNoMatch'.tr,
                                      style:
                                          TextStyle(color: Styles.c_8E9AB0))),
                            _footer(),
                          ]);
                        }
                        final group = groups[index];
                        return Material(
                          color: Styles.c_FFFFFF,
                          child: Column(children: [
                            ListTile(
                              minVerticalPadding: AppTokens.s3,
                              horizontalTitleGap: AppTokens.s5,
                              key: ValueKey(group.groupID),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: AppTokens.s5,
                                  vertical: AppTokens.s2),
                              leading: AvatarView(
                                  url: group.faceURL,
                                  text: group.groupName,
                                  width: AppTokens.s7 + AppTokens.s6,
                                  height: AppTokens.s7 + AppTokens.s6,
                                  isCircle: true,
                                  isGroup: true),
                              title: Text(group.groupName ?? group.groupID,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Styles.ts_0C1C33_17sp
                                      .copyWith(fontWeight: FontWeight.w500)),
                              subtitle: Text(
                                  'profileCommonGroupsMembers'.trParams(
                                      {'count': '${group.memberCount ?? 0}'}),
                                  style: Styles.ts_8E9AB0_14sp),
                              trailing: Icon(Icons.chevron_right,
                                  color: Styles.c_8E9AB0),
                              enabled: !_opening,
                              onTap: () => _open(group),
                            ),
                            if (index < groups.length - 1)
                              Divider(
                                height: 1,
                                thickness: 0.5,
                                indent: AppTokens.s5 * 2 +
                                    AppTokens.s7 +
                                    AppTokens.s6,
                                endIndent: AppTokens.s5,
                                color: Styles.c_E8EAEF,
                              ),
                          ]),
                        );
                      },
                    ),
                  );
                },
              )),
            ])),
      );

  Widget _footer() => _pullRefreshing
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.all(AppTokens.s7),
          child: Center(
              child: _store.busy
                  ? const CircularProgressIndicator()
                  : _store.failed
                      ? TextButton(
                          onPressed: _store.items.isEmpty
                              ? _store.refresh
                              : _store.loadMore,
                          child: Text('profileCommonGroupsRetry'.tr))
                      : _store.hasMore
                          ? TextButton(
                              onPressed: _store.loadMore,
                              child: Text('profileCommonGroupsLoadMore'.tr))
                          : Text(
                              (_store.items.isEmpty
                                      ? 'profileCommonGroupsEmpty'
                                      : 'profileCommonGroupsEnd')
                                  .tr,
                              style: Styles.ts_8E9AB0_12sp)),
        );
}
