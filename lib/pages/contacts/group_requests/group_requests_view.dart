import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';

import 'group_requests_logic.dart';
import 'pagination/group_application_footer.dart';
import 'widgets/group_request_item.dart';
import '../request_history/presentation/request_history_style.dart';
import '../empty/contact_list_placeholder.dart';
import '../request_history/data/request_history_store.dart';
import '../request_history/widgets/request_history_app_bar.dart';
import '../request_history/widgets/request_history_swipe_row.dart';

class GroupRequestsPage extends StatelessWidget {
  final logic = Get.find<GroupRequestsLogic>();

  GroupRequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() => Scaffold(
          appBar: RequestHistoryAppBar(
            title: StrRes.newGroupRequest,
            confirmation: 'requestHistoryClearGroups'.tr,
            enabled: logic.list.isNotEmpty &&
                !logic.cleaning.value &&
                logic.applicationsLoaded.value &&
                !logic.loadingMore.value,
            onClear: logic.clearRequests,
          ),
          backgroundColor: RequestHistoryStyle.surface(context),
          body: Obx(() {
            if (logic.list.isEmpty) {
              return SafeArea(
                top: false,
                child: contactListPlaceholder(
                  context,
                  title: StrRes.emptyGroupNotification,
                  loading: !logic.applicationsLoaded.value &&
                      !logic.applicationsLoadFailed.value,
                  failed: logic.applicationsLoadFailed.value,
                  onRetry: logic.reloadApplications,
                ),
              );
            }
            return SlidableAutoCloseBehavior(
                child: SmartRefresher(
              controller: logic.refreshController,
              header: IMViews.buildHeader(30),
              footer: groupApplicationFooter(context),
              enablePullDown: true,
              enablePullUp:
                  logic.hasMore.value && logic.applicationsLoaded.value,
              onRefresh: logic.reloadApplications,
              onLoading: logic.loadMore,
              child: ListView.builder(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.paddingOf(context).bottom),
                itemCount: logic.list.length,
                itemBuilder: (_, index) {
                  final item = logic.list[index];
                  return RequestHistorySwipeRow(
                    key: ValueKey(RequestHistoryEntry.group(item).id),
                    enabled: !logic.cleaning.value,
                    onDelete: () => logic.deleteRequest(item),
                    child: _buildItemView(item),
                  );
                },
              ),
            ));
          }),
        ));
  }

  Widget _buildItemView(GroupApplicationInfo info) => GroupRequestItem(
        application: info,
        groupName: logic.getGroupName(info),
        groupAvatar: logic.getGroupAvatar(info),
        outgoing: info.userID == OpenIM.iMManager.userID,
        inviter: logic.isInvite(info) ? logic.getInviterNickname(info) : null,
        handler: logic.getHandlerNickname(info),
        onReview: () => logic.handle(info),
        onOpenChat: () => logic.openChat(info),
      );
}
