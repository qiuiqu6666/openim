import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/group_requests/group_requests_logic.dart';
import 'package:openim/pages/contacts/group_requests/group_requests_view.dart';
import 'package:openim_common/openim_common.dart';

import 'support/group_requests_test_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GroupRequestsFixture fixture;

  setUp(() async {
    fixture = GroupRequestsFixture();
    await fixture.initialize();
  });

  tearDown(() async {
    Styles.isDark = false;
    await fixture.dispose();
  });

  for (final brightness in Brightness.values) {
    testWidgets('actual rows update handler names in ${brightness.name}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Styles.isDark = brightness == Brightness.dark;
      fixture.recipient = [
        request(user: 'accepted-user', result: 1, handler: 'accepted-admin'),
        request(
            group: 'group-b',
            user: 'rejected-user',
            result: -1,
            handler: 'rejected-admin'),
        request(group: 'group-c', user: 'pending-user', handler: 'ignored'),
        request(group: 'group-d', user: 'unattributed-user', result: 1),
      ];
      fixture.profiles.addAll({
        'accepted-admin': '阿秋',
        'rejected-admin': '阿冬',
        'ignored': '未处理记录不得展示此人',
      });
      final logic = Get.put(GroupRequestsLogic());

      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          locale: const Locale('zh', 'CN'),
          translations: TranslationService(),
          theme: ThemeData(brightness: brightness),
          builder: EasyLoading.init(),
          home: GroupRequestsPage(),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 2));
      await tester.pumpAndSettle();

      expect(find.text('处理人：阿秋'), findsOneWidget);
      expect(find.text('处理人：阿冬'), findsOneWidget);
      expect(find.textContaining('未处理记录不得展示此人'), findsNothing);
      expect(find.text(StrRes.approved), findsNWidgets(2));
      expect(find.text(StrRes.rejected), findsOneWidget);
      expect(find.text(StrRes.lookOver), findsOneWidget);
      expect(tester.takeException(), isNull);

      logic.userInfoList.assignAll([
        UserInfo(userID: 'accepted-admin', nickname: '阿秋的新昵称'),
        UserInfo(userID: 'rejected-admin', nickname: '阿冬'),
      ]);
      await tester.pump();

      expect(find.text('处理人：阿秋'), findsNothing);
      expect(find.text('处理人：阿秋的新昵称'), findsOneWidget);
      expect(find.text('处理人：阿冬'), findsOneWidget);
      expect(find.text(StrRes.approved), findsNWidgets(2));
      expect(find.text(StrRes.rejected), findsOneWidget);
      expect(find.text(StrRes.lookOver), findsOneWidget);
      final label = tester.widget<Text>(find.text('处理人：阿秋的新昵称'));
      expect(label.style!.color, Styles.c_8E9AB0);
      expect(tester.takeException(), isNull);
    });
  }
}
