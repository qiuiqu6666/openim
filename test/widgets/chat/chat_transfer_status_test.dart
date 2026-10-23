import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/progress/sector_progress_painter.dart';

void main() {
  for (final type in [MessageType.voice, MessageType.file]) {
    testWidgets('voice and file hide upload status but retain receipts $type',
        (tester) async {
      OpenIM.iMManager.userID = 'self';
      OpenIM.iMManager.userInfo = UserInfo(userID: 'self', nickname: 'Me');
      addTearDown(Get.reset);
      final transfer = ValueNotifier<ChatTransferStatus?>(
          const ChatTransferStatus(ChatTransferStage.uploading, 51));
      addTearDown(transfer.dispose);
      for (final status in [
        MessageStatus.sending,
        MessageStatus.failed,
        MessageStatus.succeeded,
      ]) {
        await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => GetMaterialApp(
            home: Scaffold(
              body: ChatItemView(
                key: ValueKey(status),
                message: Message.fromJson({
                  'clientMsgID': 'attachment',
                  'sendID': 'self',
                  'recvID': 'peer',
                  'contentType': type,
                  'sessionType': ConversationType.single,
                  'sendTime': 1000000,
                  'status': status,
                }),
                transferStatus: transfer,
                showAvatar: false,
                ignorePointer: true,
                onTapUserProfile: (_) {},
              ),
            ),
          ),
        ));
        await tester.pump(const Duration(seconds: 2));
        expect(find.byType(ChatTransferStatusView), findsNothing);
        expect(find.byType(CupertinoActivityIndicator), findsNothing);
        expect(find.byType(ChatSendFailedView),
            status == MessageStatus.failed ? findsOneWidget : findsNothing);
        expect(find.byType(ChatReadReceiptIcon),
            status == MessageStatus.succeeded ? findsOneWidget : findsNothing);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final dark in [false, true]) {
    testWidgets('transfer states stay readable and queryable dark=$dark',
        (tester) async {
      final state = ValueNotifier<ChatTransferStatus?>(
          const ChatTransferStatus(ChatTransferStage.uploading, 42));
      var checks = 0;
      await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) => GetMaterialApp(
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          theme:
              ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: Scaffold(
              body: Center(
                  child: SizedBox(
                      width: 160,
                      child: ChatTransferStatusView(
                          status: state, onCheck: () => checks++)))),
        ),
      ));
      final semantics = tester.ensureSemantics();
      final sector = find.byWidgetPredicate((widget) =>
          widget is CustomPaint && widget.painter is SectorProgressPainter);
      expect(find.text('上传中 42%'), findsNothing);
      expect(sector, findsOneWidget);
      expect(tester.getSemantics(find.bySemanticsLabel('上传中')).value, '42%');
      for (final percent in [0, 51, 100, -1, 120]) {
        state.value = ChatTransferStatus(ChatTransferStage.uploading, percent);
        await tester.pump();
        expect(
            (tester.widget<CustomPaint>(sector).painter
                    as SectorProgressPainter)
                .progress,
            percent.clamp(0, 100) / 100);
      }
      state.value = const ChatTransferStatus(ChatTransferStage.uploading);
      await tester.pump();
      expect(tester.getSemantics(find.bySemanticsLabel('上传中')).value, isEmpty);
      expect(find.byIcon(Icons.file_upload_outlined), findsOneWidget);
      state.value = const ChatTransferStatus(ChatTransferStage.unknown);
      await tester.pump();
      await tester.tap(find.text('待确认·点击查询'));
      expect(checks, 1);
      state.value = const ChatTransferStatus(ChatTransferStage.confirming);
      await tester.pump();
      expect(find.text('等待确认'), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 999));
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(
          tester
              .widget<CupertinoActivityIndicator>(
                  find.byType(CupertinoActivityIndicator))
              .animating,
          isTrue);
      state.value = const ChatTransferStatus(ChatTransferStage.unknown);
      await tester.pump();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
      state.dispose();
    });
  }
}
