import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'friend_requests_logic.dart';
import 'widgets/friend_request_item.dart';

class FriendRequestsPage extends StatelessWidget {
  final logic = Get.find<FriendRequestsLogic>();

  FriendRequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TitleBar.back(
          title: StrRes.newFriend, backIconColor: Styles.c_0089FF),
      backgroundColor: Styles.c_F8F9FA,
      body: Obx(() => ListView.builder(
            padding: EdgeInsets.only(top: 10.h),
            itemCount: logic.applicationList.length,
            itemBuilder: (_, index) =>
                _buildItemView(logic.applicationList[index]),
          )),
    );
  }

  Widget _buildItemView(FriendApplicationInfo info) {
    return FriendRequestItem(
      application: info,
      outgoing: info.fromUserID == OpenIM.iMManager.userID,
      onView: () => logic.acceptFriendApplication(info),
    );
  }
}
