import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/server_nodes/feedback/network_recovery_overlay.dart';
import 'package:openim/core/server_nodes/feedback/network_recovery_progress.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  late NetworkRecoveryProgress progress;
  setUp(() {
    Get.testMode = true;
    progress = NetworkRecoveryProgress();
    configureEasyLoadingInteractions();
    configureEasyLoadingAppearance();
  });
  tearDown(() {
    progress.dispose();
    Get.reset();
  });

  Future<void> mount(WidgetTester tester,
      {Brightness brightness = Brightness.light}) async {
    await tester.pumpWidget(GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(brightness: brightness),
      builder: EasyLoading.init(),
      home: NetworkRecoveryOverlay(
        progress: progress,
        child: const Scaffold(
          key: ValueKey('normal-page'),
          body: TextField(key: ValueKey('draft')),
        ),
      ),
    ));
    await tester.pump();
  }

  for (final brightness in Brightness.values) {
    testWidgets(
        'shared HUD keeps the page and draft during recovery $brightness',
        (tester) async {
      await mount(tester, brightness: brightness);
      await tester.enterText(find.byKey(const ValueKey('draft')), '保留草稿');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      final page = tester.element(find.byKey(const ValueKey('normal-page')));
      final operation = progress.begin(NetworkRecoveryStage.startingShield);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('正在连接备用线路…'), findsOneWidget);
      expect(find.byKey(const ValueKey('global-feedback-content')),
          findsOneWidget);
      expect(tester.element(find.byKey(const ValueKey('normal-page'))),
          same(page));
      operation.update(NetworkRecoveryStage.retrying);
      await tester.pump();
      await tester.pump();
      expect(find.text('正在恢复连接，稍后自动重试…'), findsOneWidget);
      expect(find.text('重试'), findsNothing);
      expect(find.text('保留草稿'), findsOneWidget);
      operation.close();
      await tester.pump();
      await tester.pump();
      expect(EasyLoading.isShow, isFalse);
      expect(tester.element(find.byKey(const ValueKey('normal-page'))),
          same(page));
      expect(find.text('保留草稿'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('does not replace or dismiss an existing video save HUD',
      (tester) async {
    await mount(tester);
    EasyLoading.show(status: '正在保存视频…', dismissOnTap: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final video = EasyLoading.instance.w;
    final operation = progress.begin(NetworkRecoveryStage.startingShield);
    await tester.pump();
    expect(EasyLoading.instance.w, same(video));
    operation.close();
    await tester.pump();
    expect(EasyLoading.instance.w, same(video));
    expect(find.text('正在保存视频…'), findsOneWidget);
    await EasyLoading.dismiss(animation: false);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'later feedback survives completion of an older network operation',
      (tester) async {
    await mount(tester);
    final old = progress.begin(NetworkRecoveryStage.startingShield);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final next = progress.begin(NetworkRecoveryStage.retrying);
    old.close();
    expect(progress.value, NetworkRecoveryStage.retrying);
    EasyLoading.show(status: '正在保存视频…', dismissOnTap: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final video = EasyLoading.instance.w;
    next.close();
    await tester.pump();
    expect(EasyLoading.instance.w, same(video));
    await EasyLoading.dismiss(animation: false);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
