import 'index/group_indexed_list.dart';
import 'package:flutter/material.dart';
import '../../group_features/identity/group_name_label.dart';
import '../../group_features/widgets/group_live_avatar.dart';
import '../../group_features/models/group_features.dart';
import '../../group_features/live/widgets/live_list_scope.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

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
          Expanded(
            child: Obx(
              () => logic.search.query.isNotEmpty
                  ? _buildSearchResults(context)
                  : _buildDirectory(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(BuildContext context) {
    final search = logic.search;
    final groups = search.results.toList(growable: false);
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
      key: ValueKey('group-search-${search.query.value}'),
      showCount: true,
    );
  }

  Widget _buildDirectory(BuildContext context) {
    final groups = <String, GroupInfo>{
      for (final group in [...logic.iCreatedList, ...logic.iJoinedList])
        group.groupID: group,
    }.values.toList(growable: false);
    final loading = logic.loading[true]! || logic.loading[false]!;
    final failed = logic.loadFailed[true]! || logic.loadFailed[false]!;
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    return RefreshIndicator(
      onRefresh: () async {
        GroupLiveListScope.maybeOf(context)?.refreshVisible();
        await Future.wait([logic.iCreatedInitial(), logic.iJoinedInitial()]);
      },
      child: groups.isEmpty
          ? contactListPlaceholder(context,
              title: chinese ? '暂无群聊' : 'No groups yet',
              loading: loading,
              failed: failed, onRetry: () async {
              await Future.wait(
                  [logic.iCreatedInitial(), logic.iJoinedInitial()]);
            }, footer: const GroupCountFooter(count: 0))
          : Column(children: [
              if (loading) const LinearProgressIndicator(),
              if (failed)
                TextButton(
                  onPressed: () async {
                    await Future.wait(
                        [logic.iCreatedInitial(), logic.iJoinedInitial()]);
                  },
                  child: Text(chinese ? '加载失败，点击重试' : 'Loading failed. Retry'),
                ),
              Expanded(
                  child: _buildList(groups, showCount: !loading && !failed)),
            ]),
    );
  }

  Widget _buildList(List<GroupInfo> groups,
          {Key? key, required bool showCount}) =>
      GroupIndexedList(
        key: key,
        groups: groups,
        footer: showCount ? GroupCountFooter(count: groups.length) : null,
        itemBuilder: (info) => _buildItemView(info, showDivider: true),
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
