import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/moments/notifications/widgets/moments_notification_row.dart';
import 'package:openim/pages/moments/media/moments_media_image.dart';
import 'package:openim/services/moments_repository.dart';
import 'package:openim_common/openim_common.dart';
import '../support/moments_ui_host.dart';

class ImageApi extends MomentsApi {
  bool fail = false;
  int calls = 0;
  @override
  Future<Uint8List> downloadMedia(MomentMedia media,
      {bool thumbnail = false}) async {
    calls++;
    if (fail) throw const MomentsException('offline');
    final data = await rootBundle.load(
        'packages/openim_common/assets/images/chat_backgrounds/scenery.png');
    return data.buffer.asUint8List();
  }
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
        'notification shows text, protected thumbnail and opens at large text dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ImageApi();
      final repository = MomentsRepository(
          api: api,
          userIdProvider: () => 'me',
          environmentProvider: () => 'test',
          subscribeToSdk: false);
      addTearDown(repository.dispose);
      var opened = 0;
      Styles.isDark = dark;
      await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => MaterialApp(
              theme: dark ? ThemeData.dark() : ThemeData.light(),
              home: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: Scaffold(
                      body: MomentsNotificationRow(
                          repository: repository,
                          item: const MomentNotification(
                              notificationId: 'n',
                              actor:
                                  MomentUser(userId: 'friend', nickname: '林同学'),
                              comment: MomentComment(
                                  commentId: 'c',
                                  author: MomentUser(userId: 'friend'),
                                  text: '好漂亮，下次一起出发！'),
                              previewMedia: MomentMedia(mediaId: 'photo')),
                          text: '评论了你的朋友圈',
                          onTap: () => opened++,
                          showDivider: true))))));
      await settleVisibleMomentsUiMedia(tester);
      expect(find.text('林同学'), findsOneWidget);
      expect(find.text('好漂亮，下次一起出发！'), findsOneWidget);
      expect(find.byType(MomentsMediaImage), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(MomentsMediaImage), matching: find.byType(Image)),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('林同学'));
      expect(opened, 1);
      expect(api.calls, 1);
      final semantics = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
    });
  }
}
