import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'friend_requests_logic.dart';
import '../empty/contact_list_placeholder.dart';
import 'widgets/friend_request_item.dart';
import '../request_history/data/request_history_store.dart';
import '../request_history/widgets/request_history_app_bar.dart';
import '../request_history/widgets/request_history_swipe_row.dart';

class FriendRequestsPage extends StatelessWidget {
  final logic = Get.find<FriendRequestsLogic>();

  FriendRequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() => Scaffold(
          appBar: RequestHistoryAppBar(
            title: StrRes.newFriend,
            confirmation: 'requestHistoryClearFriends'.tr,
            enabled: logic.applicationList.isNotEmpty &&
                !logic.cleaning.value &&
                !logic.loading.value,
            onClear: logic.clearRequests,
          ),
          backgroundColor: Styles.c_F8F9FA,
          body: Obx(() => logic.applicationList.isEmpty
              ? contactListPlaceholder(
                  context,
                  title: Localizations.localeOf(context).languageCode == 'zh'
                      ? '暂无好友申请'
                      : 'No friend requests yet',
                  loading: logic.loading.value,
                  failed: logic.loadFailed.value,
                  onRetry: logic.loadRequests,
                )
              : SlidableAutoCloseBehavior(
                  child: ListView.builder(
                  padding: EdgeInsets.only(top: 10.h),
                  itemCount: logic.applicationList.length,
                  itemBuilder: (_, index) =>
                      _buildItemView(logic.applicationList[index]),
                ))),
        ));
  }

  Widget _buildItemView(FriendApplicationInfo info) {
    return RequestHistorySwipeRow(
        key: ValueKey(RequestHistoryEntry.friend(info).id),
        enabled: !logic.cleaning.value,
        onDelete: () => logic.deleteRequest(info),
        child: FriendRequestItem(
          application: info,
          outgoing: info.fromUserID == OpenIM.iMManager.userID,
          onView: () => logic.acceptFriendApplication(info),
        ));
  }
}
