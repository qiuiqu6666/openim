import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/mine/secondary/calls/recent_calls_page.dart';
import 'package:openim_common/openim_common.dart';

import '../../../support/contact_remark_fixture.dart';
import 'recent_call_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    testWidgets('stored call names follow live remarks in ${brightness.name}',
        (tester) async {
      Get.testMode = true;
      OpenIM.iMManager.userID = 'account-a';
      final contacts = ContactRemarkFixture()..remarks['peer-1'] = '好友备注';
      contacts.remarks['team'] = '与群ID相同的好友备注';
      Get.put<ContactRemarkSource>(contacts);
      final record = callFixture(nickname: '公开昵称');
      final group = callFixture(room: 'group-room', nickname: '原群名称')
        ..roomType = 'group'
        ..groupID = 'team';
      final box = RecentCallMemoryBox()
        ..backingMap['account-a'] = [record, group];
      final cache = CacheController(
          accountIDProvider: () => 'account-a', boxOpener: () async => box);
      await tester.pumpWidget(GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        theme: ThemeData(brightness: brightness),
        home: RecentCallsPage(cacheController: cache),
      ));
      await tester.pumpAndSettle();
      final initialWrites = box.writes;
      expect(find.text('好友备注'), findsOneWidget);
      expect(find.text('原群名称'), findsOneWidget);
      expect(find.text('与群ID相同的好友备注'), findsNothing);
      contacts.remarks['peer-1'] = '已修改的备注';
      await tester.pump();
      expect(find.text('已修改的备注'), findsOneWidget);
      contacts.remarks.remove('peer-1');
      await tester.pump();
      expect(find.text('公开昵称'), findsOneWidget);
      expect(record.nickname, '公开昵称');
      expect(cache.callRecordList, hasLength(2));
      expect(box.writes, initialWrites);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
