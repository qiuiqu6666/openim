import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';
import 'package:sprintf/sprintf.dart';

import 'group_requests_logic.dart';
import 'pagination/group_application_footer.dart';
import 'widgets/group_request_handler_label.dart';
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
          backgroundColor: Styles.c_F8F9FA,
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
                padding: EdgeInsets.only(top: 10.h),
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

  Widget _buildItemView(GroupApplicationInfo info) {
    final isISendRequest = info.userID == OpenIM.iMManager.userID;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: Styles.c_FFFFFF,
        border: BorderDirectional(
          bottom: BorderSide(color: Styles.c_F8F9FA, width: 1.h),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AvatarView(
                  url: info.userFaceURL,
                  text: info.nickname,
                ),
                10.horizontalSpace,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      (info.nickname ?? '').toText
                        ..style = Styles.ts_0C1C33_17sp
                        ..maxLines = 1
                        ..overflow = TextOverflow.ellipsis,
                      4.verticalSpace,
                      if (!logic.isInvite(info))
                        RichText(
                          text: TextSpan(
                            text: StrRes.applyJoin,
                            style: Styles.ts_8E9AB0_14sp,
                            children: [
                              WidgetSpan(child: 2.horizontalSpace),
                              TextSpan(
                                text: logic.getGroupName(info),
                                style: Styles.ts_0089FF_14sp,
                              ),
                            ],
                          ),
                        )
                      else
                        RichText(
                          text: TextSpan(
                            text: logic.getInviterNickname(info),
                            style: Styles.ts_0089FF_14sp,
                            children: [
                              WidgetSpan(child: 2.horizontalSpace),
                              TextSpan(
                                text: StrRes.invite,
                                style: Styles.ts_8E9AB0_14sp,
                              ),
                              WidgetSpan(child: 2.horizontalSpace),
                              TextSpan(
                                text: info.nickname,
                                style: Styles.ts_0089FF_14sp,
                              ),
                              WidgetSpan(child: 2.horizontalSpace),
                              TextSpan(
                                text: StrRes.joinIn,
                                style: Styles.ts_8E9AB0_14sp,
                              ),
                              WidgetSpan(child: 2.horizontalSpace),
                              TextSpan(
                                text: logic.getGroupName(info),
                                style: Styles.ts_0089FF_14sp,
                              ),
                            ],
                          ),
                        ),
                      if (null != IMUtils.emptyStrToNull(info.reqMsg))
                        Padding(
                          padding: EdgeInsets.only(top: 4.h),
                          child:
                              sprintf(StrRes.applyReason, [info.reqMsg!]).toText
                                ..style = Styles.ts_8E9AB0_14sp
                                ..maxLines = 1
                                ..overflow = TextOverflow.ellipsis,
                        ),
                      if ((info.handleResult == 1 || info.handleResult == -1) &&
                          IMUtils.isNotNullEmptyStr(info.handleUserID?.trim()))
                        Obx(() => GroupRequestHandlerLabel(
                              nickname: logic.getHandlerNickname(info),
                            )),
                    ],
                  ),
                )
              ],
            ),
          ),
          if (/*info.handleResult == 0 && */ isISendRequest)
            ImageRes.sendRequests.toImage
              ..width = 20.w
              ..height = 20.h,
          if (info.handleResult == 0 && !isISendRequest)
            Button(
              text: StrRes.lookOver,
              textStyle: Styles.ts_FFFFFF_14sp,
              height: 28.h,
              padding: EdgeInsets.symmetric(horizontal: 13.w),
              onTap: () => logic.handle(info),
            ),
          if (info.handleResult == 0 && isISendRequest)
            StrRes.waitingForVerification.toText..style = Styles.ts_8E9AB0_14sp,
          if (info.handleResult == -1)
            StrRes.rejected.toText..style = Styles.ts_8E9AB0_14sp,
          if (info.handleResult == 1)
            StrRes.approved.toText..style = Styles.ts_8E9AB0_14sp,
        ],
      ),
    );
  }
}
