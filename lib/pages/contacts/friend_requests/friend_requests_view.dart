import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'friend_requests_logic.dart';
import '../empty/contact_list_placeholder.dart';
import 'widgets/friend_request_item.dart';
import 'widgets/friend_request_edit_bar.dart';
import '../request_history/presentation/request_history_labels.dart';
import '../request_history/presentation/request_history_style.dart';
import '../request_history/data/request_history_store.dart';
import '../request_history/widgets/request_history_app_bar.dart';
import '../request_history/widgets/request_history_swipe_row.dart';

class FriendRequestsPage extends StatelessWidget {
  final logic = Get.find<FriendRequestsLogic>();

  FriendRequestsPage({super.key});

  @override
  Widget build(BuildContext context) => Obx(() => Scaffold(
        appBar: RequestHistoryAppBar(
          title: RequestHistoryLabels.friends,
          confirmation: 'requestHistoryClearFriends'.tr,
          enabled: !logic.cleaning.value,
          onClear: logic.clearRequests,
          actions: [
            if (logic.editing.value)
              TextButton(
                key: const ValueKey('friend-requests-select-all'),
                onPressed: logic.cleaning.value ? null : logic.toggleAll,
                style: TextButton.styleFrom(foregroundColor: AppTokens.accent),
                child: Text(
                    logic.allSelected
                        ? RequestHistoryLabels.deselect
                        : StrRes.selectAll,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            if (logic.applicationList.isNotEmpty || logic.editing.value)
              TextButton(
                key: const ValueKey('friend-requests-edit'),
                onPressed: logic.cleaning.value ? null : logic.toggleEditing,
                style: TextButton.styleFrom(foregroundColor: AppTokens.accent),
                child: Text(logic.editing.value ? StrRes.done : StrRes.edit,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
        backgroundColor: RequestHistoryStyle.background(context),
        body: logic.applicationList.isEmpty
            ? contactListPlaceholder(context,
                title: RequestHistoryLabels.emptyFriends,
                loading: logic.loading.value,
                failed: logic.loadFailed.value,
                onRetry: logic.loadRequests)
            : _buildList(context),
        bottomNavigationBar: logic.editing.value
            ? FriendRequestEditBar(
                count: logic.selected.length,
                busy: logic.cleaning.value,
                onDelete: logic.deleteSelected,
              )
            : null,
      ));

  Widget _buildList(BuildContext context) {
    final received = logic.applicationList
        .where((item) => !logic.isISendRequest(item))
        .toList();
    final sent = logic.applicationList.where(logic.isISendRequest).toList();
    int displayTime(FriendApplicationInfo item) {
      final time =
          (item.handleTime ?? 0) > 0 ? item.handleTime! : item.createTime ?? 0;
      return time < 100000000000 ? time * 1000 : time;
    }

    received.sort((a, b) {
      if (a.isWaitingHandle != b.isWaitingHandle) {
        return a.isWaitingHandle ? -1 : 1;
      }
      return displayTime(b).compareTo(displayTime(a));
    });
    sent.sort((a, b) => displayTime(b).compareTo(displayTime(a)));
    final rows = <Object>[
      if (received.isNotEmpty) RequestHistoryLabels.incoming,
      ...received,
      if (sent.isNotEmpty) RequestHistoryLabels.outgoing,
      ...sent,
    ];
    return SlidableAutoCloseBehavior(
        child: RefreshIndicator(
      onRefresh: logic.loadRequests,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        itemCount: rows.length,
        itemBuilder: (_, index) {
          final row = rows[index];
          if (row is String) {
            return Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.s5,
                  vertical: RequestHistoryStyle.sectionVertical),
              child: Text(row,
                  style: RequestHistoryStyle.subtitle(context).copyWith(
                      fontSize: AppTokens.captionFontSize,
                      fontWeight: FontWeight.w500)),
            );
          }
          return _buildItemView(row as FriendApplicationInfo);
        },
      ),
    ));
  }

  Widget _buildItemView(FriendApplicationInfo info) => RequestHistorySwipeRow(
        key: ValueKey(RequestHistoryEntry.friend(info).id),
        enabled: !logic.cleaning.value && !logic.editing.value,
        onDelete: () => logic.deleteRequest(info),
        child: FriendRequestItem(
          application: info,
          outgoing: logic.isISendRequest(info),
          onView: () => logic.acceptFriendApplication(info),
          onOpenChat: () => logic.openChat(info),
          onSelect:
              logic.editing.value ? () => logic.toggleSelection(info) : null,
          selected: logic.selected.contains(logic.selectionKey(info)),
        ),
      );
}
