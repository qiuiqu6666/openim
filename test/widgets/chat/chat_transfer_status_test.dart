import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('transfer states stay readable and queryable dark=$dark',
        (tester) async {
      final state = ValueNotifier<ChatTransferStatus?>(
          const ChatTransferStatus(ChatTransferStage.uploading, 42));
      var checks = 0;
      await tester.pumpWidget(GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 160,
                    child: ChatTransferStatusView(
                        status: state, onCheck: () => checks++)))),
      ));
      expect(find.text('上传中 42%'), findsOneWidget);
      state.value = const ChatTransferStatus(ChatTransferStage.unknown);
      await tester.pump();
      await tester.tap(find.text('待确认·点击查询'));
      expect(checks, 1);
      state.value = const ChatTransferStatus(ChatTransferStage.confirming);
      await tester.pump();
      expect(find.text('等待确认'), findsNothing);
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
      state.dispose();
    });
  }
}
