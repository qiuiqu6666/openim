import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/group_requests/widgets/group_request_item.dart';
import 'package:openim/pages/contacts/group_requests/widgets/group_request_people.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';

void main() {
  tearDown(() {
    Get.reset();
    Styles.isDark = false;
  });
  for (final dark in [false, true]) {
    testWidgets('each person opens their ID without opening the row dark=$dark',
        (tester) async {
      final opened = <String>[];
      final features = GroupFeatureStore(
          api: GroupFeatureApi(),
          sessionCurrent: () => true,
          fetchGroups: (_) async => []);
      addTearDown(features.dispose);
      var chats = 0;
      Styles.isDark = dark;
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          theme:
              ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: Scaffold(
              body: SizedBox(
                  width: 375,
                  child: GroupRequestItem(
                    application: GroupApplicationInfo(
                        groupID: 'test-group',
                        userID: 'invitee-id',
                        nickname: '同名',
                        inviterUserID: 'inviter-id',
                        handleUserID: 'admin-id',
                        handleResult: 1),
                    groupName: '测试群',
                    groupFeatures: features,
                    groupAvatar: null,
                    outgoing: false,
                    inviter: '同名',
                    handler: '管理员',
                    onReview: () => fail('profile tap must not review'),
                    onOpenChat: () => chats++,
                    onViewUser: opened.add,
                  ))),
        ),
      ));
      await tester.pumpAndSettle();
      final paragraphFinder = find.descendant(
          of: find.byType(GroupRequestPeople), matching: find.byType(RichText));
      final paragraph = tester.renderObject<RenderParagraph>(paragraphFinder);
      final content = paragraph.text.toPlainText();
      for (final offset in [content.indexOf('同名'), content.lastIndexOf('同名')]) {
        final box = paragraph
            .getBoxesForSelection(
                TextSelection(baseOffset: offset, extentOffset: offset + 1))
            .first;
        await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
      }
      await tester.tap(find.text('处理管理员：管理员'));
      expect(opened, ['inviter-id', 'invitee-id', 'admin-id']);
      expect(chats, 0);
      expect(paragraph.maxLines, 1);
      expect(paragraph.overflow, TextOverflow.ellipsis);
      expect(find.byType(TextButton), findsNothing);
      expect(
          tester.getSize(find.byType(GroupRequestItem)).height, lessThan(120));
      expect(tester.takeException(), isNull);
      final initialColor = tester.widget<Text>(find.text('测试群')).style!.color;
      final height = tester.getSize(find.byType(GroupRequestItem)).height;
      for (final type in [1, 3, 0, 2, 4]) {
        features
            .seed(GroupInfo(groupID: 'test-group', ex: '{"gameType":$type}'));
        await tester.pump();
        expect(
            tester.widget<Text>(find.text('测试群')).style!.color, initialColor);
        expect(tester.getSize(find.byType(GroupRequestItem)).height, height);
      }
    });
  }
}
