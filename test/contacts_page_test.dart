import 'dart:io';
import 'package:visibility_detector/visibility_detector.dart';
import 'dart:ui' as ui;

import 'package:azlistview/azlistview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/contacts_logic.dart';
import 'package:openim/pages/contacts/contacts_view.dart';
import 'package:openim/pages/contacts/star_friend_store.dart';
import 'package:openim/pages/contacts/presence_store.dart';
import 'package:openim_common/openim_common.dart';

class _FakeContactsLogic implements ContactsLogic {
  @override
  void setPresenceVisible(String id, bool visible) {}
  @override
  final presence = PresenceStore();
  @override
  final stars = StarFriendStore();
  @override
  final friends = <ISUserInfo>[].obs;
  @override
  final friendsLoading = false.obs;
  @override
  int get friendApplicationCount => 2;
  @override
  int get groupApplicationCount => 0;
  int searches = 0;
  int openedFriends = 0;

  @override
  void searchContacts() => searches++;
  @override
  void addContacts() {}
  @override
  void newFriend() {}
  @override
  void newGroup() {}
  @override
  void myGroup() {}
  @override
  void viewFriend(ISUserInfo friend) => openedFriends++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => VisibilityDetectorController.instance.updateInterval = Duration.zero);
  tearDown(() => VisibilityDetectorController.instance.updateInterval = const Duration(milliseconds: 500));
  testWidgets('contacts page shows reference layout and keeps search working',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final logic = _FakeContactsLogic();
    for (final name in [
      'contact_new_99chat.png',
      'contact_notice_99chat.png',
      'contact_groups_99chat.png',
      'contact_plus_99chat.png',
      'nav_chat_99chat.png',
      'nav_chat_active_99chat.png',
      'nav_group_conv_99chat.png',
      'nav_contact_99chat.png',
      'nav_contact_active_99chat.png',
      'nav_profile_99chat.png',
      'nav_profile_active_99chat.png',
    ]) {
      expect(
        (await rootBundle.load('packages/openim_common/assets/images/$name'))
            .lengthInBytes,
        greaterThan(0),
      );
    }
    final previewKey = GlobalKey();
    Styles.isDark = false;
    addTearDown(() => Styles.isDark = false);

    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        home:
            RepaintBoundary(key: previewKey, child: ContactsPage(logic: logic)),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('通讯录'), findsOneWidget);
    expect(find.text('新的朋友'), findsOneWidget);
    expect(find.text('群通知'), findsOneWidget);
    expect(find.text('我的群聊'), findsOneWidget);
    expect(find.byType(AzListView), findsOneWidget);
    await tester.tap(find.text('搜索'));
    expect(logic.searches, 1);
    logic.friends.add(IMUtils.setAzPinyinAndTag(
      ISUserInfo.fromJson({'userID': 'u1', 'nickname': '李雷'}),
    ) as ISUserInfo);
    await tester.pumpAndSettle();
    expect(find.text('李雷'), findsOneWidget);
    logic.stars.apply(StarFriend.fromJson({
      'friendUserID': 'u1',
      'starred': true,
      'version': 1,
      'updatedAt': 1,
    }));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    logic.stars.apply(StarFriend.fromJson({
      'friendUserID': 'u1',
      'starred': false,
      'version': 2,
      'updatedAt': 2,
    }));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star_rounded), findsNothing);
    await tester.tap(find.text('李雷'));
    expect(logic.openedFriends, 1);
    expect(tester.takeException(), isNull);
    const output = String.fromEnvironment('CONTACTS_LAYOUT_PREVIEW');
    if (output.isNotEmpty) {
      for (final name in [
        'contact_new_99chat.png',
        'contact_notice_99chat.png',
        'contact_groups_99chat.png',
      ]) {
        await tester.runAsync(() => precacheImage(
              AssetImage('assets/images/$name', package: 'openim_common'),
              previewKey.currentContext!,
            ));
      }
      await tester.pumpAndSettle();
      final boundary = previewKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(output).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
    logic.presence.dispose();
    logic.stars.dispose();
  });
}
