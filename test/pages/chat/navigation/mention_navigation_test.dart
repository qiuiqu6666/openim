import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim/routes/app_pages.dart';

void main() {
  testWidgets('mention picker returns members through a dynamic named route',
      (tester) async {
    List<GroupMembersInfo>? selected;
    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(body: TextButton(
        onPressed: () async {
          selected = await AppNavigator.startGroupMemberList<List<GroupMembersInfo>>(
            groupInfo: GroupInfo(groupID: 'test-group'),
          );
        },
        child: const Text('Open'),
      )),
      getPages: [GetPage<dynamic>(
        name: AppRoutes.groupMemberList,
        page: () => Scaffold(body: TextButton(
          onPressed: () => Get.back(result: <GroupMembersInfo>[
            GroupMembersInfo(userID: 'im_member', nickname: '成员'),
          ]),
          child: const Text('Select'),
        )),
      )],
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(selected?.single.userID, 'im_member');
    await tester.pumpWidget(const SizedBox());
    Get.reset();
  });
}
