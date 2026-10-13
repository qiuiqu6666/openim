import 'package:flutter/material.dart';
import '../../group_features/identity/group_name_label.dart';
import '../../group_features/widgets/group_live_avatar.dart';
import '../../group_features/models/group_features.dart';
import '../../group_features/live/widgets/live_list_scope.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';

import 'group_list_logic.dart';
import 'count/group_count_footer.dart';
import '../empty/contact_list_placeholder.dart';
import '../select_contacts/contact_card/contact_card_picker_tokens.dart';

class GroupListPage extends StatelessWidget {
  final GroupListLogic logic;
  final ValueChanged<GroupInfo>? onSelected;
  final Set<String>? allowedGroupIDs;
  final String? title;
  final String? disabledReason;

  GroupListPage(
      {super.key,
      GroupListLogic? logic,
      this.onSelected,
      this.allowedGroupIDs,
      this.title,
      this.disabledReason})
      : logic = logic ?? Get.find<GroupListLogic>();

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
      appBar: TitleBar.back(
          title: title ?? StrRes.myGroup, backIconColor: Styles.c_0089FF),
      backgroundColor: Styles.c_F8F9FA,
      body: Column(
        children: [
          SearchBox(
            key: const ValueKey('my-groups-search'),
            controller: logic.search.controller,
            enabled: true,
            height: ContactCardPickerTokens.searchHeight(context),
            margin: ContactCardPickerTokens.searchPadding,
            borderRadius:
                BorderRadius.circular(ContactCardPickerTokens.searchRadius),
            surfaceColor: Styles.c_FFFFFF,
            backgroundColor: Styles.c_F4F5F7,
            textStyle: ContactCardPickerTokens.searchStyle(context),
            hintStyle: ContactCardPickerTokens.searchStyle(context, hint: true),
            searchIconColor: ContactCardPickerTokens.secondary(context),
            onChanged: logic.search.change,
            onCleared: () => logic.search.change(''),
            onSubmitted: (value) {
              logic.search.change(value);
              logic.search.run();
              FocusScope.of(context).unfocus();
            },
          ),
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
              () => logic.search.query.isNotEmpty
                  ? _buildSearchResults(context)
                  : _buildDirectory(context, created: logic.index.value == 0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(BuildContext context) {
    final search = logic.search;
    final groups = search.groupsFor(created: logic.index.value == 0);
    if (search.loading.value || search.failed.value || groups.isEmpty) {
      return contactListPlaceholder(
        context,
        title: StrRes.searchNotFound,
        loading: search.loading.value,
        failed: search.failed.value,
        onRetry: search.run,
        footer: const GroupCountFooter(count: 0),
      );
    }
    return _buildList(
      groups,
      key: ValueKey('group-search-${logic.index.value}-${search.query.value}'),
      showCount: true,
    );
  }

  Widget _buildDirectory(BuildContext context, {required bool created}) {
    final groups = (created ? logic.iCreatedList : logic.iJoinedList)
        .toList(growable: false);
    final refresh = created ? logic.iCreatedInitial : logic.iJoinedInitial;
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final strings = RefreshLocalizations.of(context)?.currentLocalization ??
        (chinese ? ChRefreshString() : EnRefreshString());
    final list = SmartRefresher(
      key: created ? logic.iCreateGlobalKey : logic.iJoinGlobalKey,
      controller: created
          ? logic.iCreateRefreshController
          : logic.iJoinRefreshController,
      header: IMViews.buildHeader(30),
      footer: ClassicFooter(
        textStyle: ContactCardPickerTokens.subtitleStyle(context),
        idleText: strings.idleLoadingText,
        loadingText: strings.loadingText,
        canLoadingText: strings.canLoadingText,
        failedText: strings.loadFailedText,
        noDataText: strings.noMoreText,
      ),
      enablePullUp: logic.canLoadMore(created),
      enablePullDown: true,
      onRefresh: () {
        GroupLiveListScope.maybeOf(context)?.refreshVisible();
        refresh();
      },
      onLoading: created ? logic.iCreatedLoadMore : logic.iJoinedLoadMore,
      child: groups.isEmpty
          ? contactListPlaceholder(
              context,
              title: chinese
                  ? (created ? '暂无创建的群聊' : '暂无加入的群聊')
                  : (created
                      ? 'No groups created yet'
                      : 'No groups joined yet'),
              loading: logic.loading[created]!,
              failed: logic.loadFailed[created]!,
              onRetry: refresh,
              footer: const GroupCountFooter(count: 0),
            )
          : _buildList(groups, showCount: logic.isComplete(created)),
    );
    final limit = logic.canLoadMore(created) ? null : 0.0;
    return RefreshConfiguration.of(context) == null
        ? RefreshConfiguration(maxUnderScrollExtent: limit, child: list)
        : RefreshConfiguration.copyAncestor(
            context: context, maxUnderScrollExtent: limit, child: list);
  }

  ListView _buildList(List<GroupInfo> groups,
          {Key? key, required bool showCount}) =>
      ListView.builder(
        key: key,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: groups.length + (showCount ? 1 : 0),
        itemBuilder: (_, index) => index == groups.length
            ? GroupCountFooter(count: groups.length)
            : _buildItemView(groups[index],
                showDivider: index < groups.length - 1),
      );

  Widget _buildItemView(GroupInfo info, {required bool showDivider}) =>
      Material(
        color: Styles.c_FFFFFF,
        child: Column(children: [
          ListTile(
            key: ValueKey(info.groupID),
            enabled: onSelected == null ||
                allowedGroupIDs == null ||
                allowedGroupIDs!.contains(info.groupID),
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
            title: GroupNameLabel(
              groupID: info.groupID,
              ex: info.ex,
              store: logic.groupFeatures,
              name: (info.groupName ?? '').trim().isEmpty
                  ? (onSelected == null ? info.groupID : '未命名群聊')
                  : info.groupName!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  Styles.ts_0C1C33_17sp.copyWith(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
                onSelected != null &&
                        allowedGroupIDs != null &&
                        !allowedGroupIDs!.contains(info.groupID) &&
                        disabledReason != null
                    ? disabledReason!
                    : 'profileCommonGroupsMembers'
                        .trParams({'count': '${info.memberCount ?? 0}'}),
                style: Styles.ts_8E9AB0_14sp),
            trailing: Icon(Icons.chevron_right, color: Styles.c_8E9AB0),
            onTap: () => onSelected == null
                ? logic.toGroupChat(info)
                : onSelected!(info),
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
