import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';

import 'group_list_logic.dart';

class GroupListPage extends StatelessWidget {
  final logic = Get.find<GroupListLogic>();

  GroupListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TitleBar.back(title: StrRes.myGroup),
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
                  ? _buildICreatedListView()
                  : _buildIJoinedListView(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildICreatedListView() => SmartRefresher(
        key: logic.iCreateGlobalKey,
        controller: logic.iCreateRefreshController,
        header: IMViews.buildHeader(30),
        footer: IMViews.buildFooter(),
        enablePullUp: true,
        enablePullDown: true,
        onRefresh: logic.iCreatedInitial,
        onLoading: logic.iCreatedLoadMore,
        child: ListView.builder(
          physics: const BouncingScrollPhysics(),
          itemCount: logic.iCreatedList.length,
          itemBuilder: (_, index) => _buildItemView(logic.iCreatedList[index],
              showDivider: index < logic.iCreatedList.length - 1),
        ),
      );

  Widget _buildIJoinedListView() => SmartRefresher(
        key: logic.iJoinGlobalKey,
        controller: logic.iJoinRefreshController,
        header: IMViews.buildHeader(30),
        footer: IMViews.buildFooter(),
        enablePullUp: true,
        enablePullDown: true,
        onRefresh: logic.iJoinedInitial,
        onLoading: logic.iJoinedLoadMore,
        child: ListView.builder(
          physics: const BouncingScrollPhysics(),
          itemCount: logic.iJoinedList.length,
          itemBuilder: (_, index) => _buildItemView(logic.iJoinedList[index],
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
            leading: AvatarView(
              url: info.faceURL,
              text: info.groupName,
              isGroup: true,
              isCircle: true,
              width: AppTokens.s7 + AppTokens.s6,
              height: AppTokens.s7 + AppTokens.s6,
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
