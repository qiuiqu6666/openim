import 'package:flutter/material.dart';
import '../../group_features/widgets/group_live_avatar.dart';
import '../../group_features/models/group_features.dart';
import '../../group_features/live/widgets/live_list_scope.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';

import 'group_list_logic.dart';
import '../empty/contact_list_placeholder.dart';

class GroupListPage extends StatelessWidget {
  final logic = Get.find<GroupListLogic>();

  GroupListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = logic.groupFeatures;
    if (store == null) return _build(context);
    return GroupLiveListScope(
      store: store,
      userID: OpenIM.iMManager.userID,
      sessionCurrent: () => store.active,
      child: Builder(builder: _build),
    );
  }

  Widget _build(BuildContext context) {
    return Scaffold(
      appBar:
          TitleBar.back(title: StrRes.myGroup, backIconColor: Styles.c_0089FF),
      backgroundColor: Styles.c_F8F9FA,
      body: Column(
        children: [
          Obx(
            () => CustomTabBar(
              labels: [StrRes.iCreatedGroup, StrRes.iJoinedGroup],
              index: logic.index.value,
              onTabChanged: (i) => logic.switchTab(i),
              showUnderline: true,
            ),
          ),
          Expanded(
            child: Obx(
              () => logic.index.value == 0
                  ? _buildICreatedListView(context)
                  : _buildIJoinedListView(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildICreatedListView(BuildContext context) => SmartRefresher(
        key: logic.iCreateGlobalKey,
        controller: logic.iCreateRefreshController,
        header: IMViews.buildHeader(30),
        footer: IMViews.buildFooter(),
        enablePullUp: logic.canLoadMore(true),
        enablePullDown: true,
        onRefresh: () {
          GroupLiveListScope.maybeOf(context)?.refreshVisible();
          logic.iCreatedInitial();
        },
        onLoading: logic.iCreatedLoadMore,
        child: logic.iCreatedList.isEmpty
            ? contactListPlaceholder(
                context,
                title: Localizations.localeOf(context).languageCode == 'zh'
                    ? '暂无创建的群聊'
                    : 'No groups created yet',
                loading: logic.loading[true]!,
                failed: logic.loadFailed[true]!,
                onRetry: logic.iCreatedInitial,
              )
            : ListView.builder(
                physics: const BouncingScrollPhysics(),
                itemCount: logic.iCreatedList.length,
                itemBuilder: (_, index) => _buildItemView(
                    logic.iCreatedList[index],
                    showDivider: index < logic.iCreatedList.length - 1),
              ),
      );

  Widget _buildIJoinedListView(BuildContext context) => SmartRefresher(
        key: logic.iJoinGlobalKey,
        controller: logic.iJoinRefreshController,
        header: IMViews.buildHeader(30),
        footer: IMViews.buildFooter(),
        enablePullUp: logic.canLoadMore(false),
        enablePullDown: true,
        onRefresh: () {
          GroupLiveListScope.maybeOf(context)?.refreshVisible();
          logic.iJoinedInitial();
        },
        onLoading: logic.iJoinedLoadMore,
        child: logic.iJoinedList.isEmpty
            ? contactListPlaceholder(
                context,
                title: Localizations.localeOf(context).languageCode == 'zh'
                    ? '暂无加入的群聊'
                    : 'No groups joined yet',
                loading: logic.loading[false]!,
                failed: logic.loadFailed[false]!,
                onRetry: logic.iJoinedInitial,
              )
            : ListView.builder(
                physics: const BouncingScrollPhysics(),
                itemCount: logic.iJoinedList.length,
                itemBuilder: (_, index) => _buildItemView(
                    logic.iJoinedList[index],
                    showDivider: index < logic.iJoinedList.length - 1),
              ),
      );

  Widget _buildItemView(GroupInfo info, {required bool showDivider}) =>
      Material(
        color: Styles.c_FFFFFF,
        child: Column(children: [
          ListTile(
            key: ValueKey(info.groupID),
            minVerticalPadding: AppTokens.s3,
            horizontalTitleGap: AppTokens.s5,
            contentPadding: const EdgeInsets.symmetric(
                horizontal: AppTokens.s5, vertical: AppTokens.s2),
            leading: GroupLiveAvatar(
              store: logic.groupFeatures,
              groupID: info.groupID,
              features: GroupFeatures.fromEx(info.ex),
              child: AvatarView(
                url: info.faceURL,
                text: info.groupName,
                isGroup: true,
                isCircle: true,
                width: AppTokens.s7 + AppTokens.s6,
                height: AppTokens.s7 + AppTokens.s6,
              ),
            ),
            title: Text(
              (info.groupName ?? '').trim().isEmpty
                  ? info.groupID
                  : info.groupName!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  Styles.ts_0C1C33_17sp.copyWith(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
                'profileCommonGroupsMembers'
                    .trParams({'count': '${info.memberCount ?? 0}'}),
                style: Styles.ts_8E9AB0_14sp),
            trailing: Icon(Icons.chevron_right, color: Styles.c_8E9AB0),
            onTap: () => logic.toGroupChat(info),
          ),
          if (showDivider)
            Divider(
                height: 1,
                thickness: 0.5,
                indent: AppTokens.s5 * 2 + AppTokens.s7 + AppTokens.s6,
                endIndent: AppTokens.s5,
                color: Styles.c_E8EAEF),
        ]),
      );
}
