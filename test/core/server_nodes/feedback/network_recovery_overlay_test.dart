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
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
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

  NetworkRecoveryOperation start() =>
      progress.begin(NetworkRecoveryStage.checking,
          context: NetworkRecoveryContext.startup);

  Future<void> reveal(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(NetworkRecoveryOverlay.revealDelay);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  void background(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  void resume(WidgetTester tester) {
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets(
        'cold-start HUD keeps copy, size, identity and page across retries $brightness',
        (tester) async {
      await mount(tester, brightness: brightness);
      await tester.enterText(find.byKey(const ValueKey('draft')), '保留草稿');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      final page = tester.element(find.byKey(const ValueKey('normal-page')));
      final operation = start();
      await reveal(tester);
      expect(find.text('正在连接…'), findsOneWidget);
      expect(find.byKey(const ValueKey('global-feedback-content')),
          findsOneWidget);
      final hud = EasyLoading.instance.w;
      final size =
          tester.getSize(find.byKey(const ValueKey('global-feedback-content')));
      expect(tester.element(find.byKey(const ValueKey('normal-page'))),
          same(page));
      for (final stage in [
        NetworkRecoveryStage.startingShield,
        NetworkRecoveryStage.retrying,
        NetworkRecoveryStage.startingShield
      ]) {
        operation.update(stage);
        await tester.pump();
        await tester.pump();
        expect(find.text('正在连接…'), findsOneWidget);
        expect(EasyLoading.instance.w, same(hud));
        expect(
            tester
                .getSize(find.byKey(const ValueKey('global-feedback-content'))),
            size);
      }
      expect(find.text('正在连接备用线路…'), findsNothing);
      expect(find.text('正在恢复连接，稍后自动重试…'), findsNothing);
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

  testWidgets('quick startup finishes without flashing a HUD', (tester) async {
    await mount(tester);
    final operation = start();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(EasyLoading.isShow, isFalse);
    operation.close();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(EasyLoading.isShow, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'runtime recovery stays silent and interactive after resume $brightness',
        (tester) async {
      await mount(tester, brightness: brightness);
      final page = tester.element(find.byKey(const ValueKey('normal-page')));
      final operation = progress.begin(NetworkRecoveryStage.startingShield);
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(EasyLoading.isShow, isFalse);
      await tester.tap(find.byKey(const ValueKey('draft')));
      await tester.enterText(find.byKey(const ValueKey('draft')), '继续输入');
      for (final stage in [
        NetworkRecoveryStage.retrying,
        NetworkRecoveryStage.startingShield
      ]) {
        background(tester);
        operation.update(stage);
        await tester.pump(const Duration(seconds: 5));
        resume(tester);
        await tester.pump();
        await tester.pump(const Duration(seconds: 5));
        expect(EasyLoading.isShow, isFalse);
      }
      expect(tester.element(find.byKey(const ValueKey('normal-page'))),
          same(page));
      expect(find.text('继续输入'), findsOneWidget);
      operation.close();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('resume waits again and does not replay a completed startup HUD',
      (tester) async {
    await mount(tester);
    final operation = start();
    await reveal(tester);
    expect(EasyLoading.isShow, isTrue);
    background(tester);
    await tester.pump();
    expect(EasyLoading.isShow, isFalse);
    resume(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(EasyLoading.isShow, isFalse);
    operation.close();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(EasyLoading.isShow, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('runtime operation replaces startup HUD without reviving it',
      (tester) async {
    await mount(tester);
    final startup = start();
    await reveal(tester);
    final runtime = progress.begin(NetworkRecoveryStage.checking);
    await tester.pump();
    await tester.pump();
    expect(EasyLoading.isShow, isFalse);
    startup.update(NetworkRecoveryStage.retrying);
    startup.close();
    expect(progress.value?.context, NetworkRecoveryContext.reconnect);
    await tester.pump(const Duration(seconds: 3));
    expect(EasyLoading.isShow, isFalse);
    runtime.close();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dispose cancels a delayed reveal', (tester) async {
    await mount(tester);
    final operation = start();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    expect(EasyLoading.isShow, isFalse);
    operation.close();
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not replace or dismiss an existing video save HUD',
      (tester) async {
    await mount(tester);
    EasyLoading.show(status: '正在保存视频…', dismissOnTap: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final video = EasyLoading.instance.w;
    final operation = start();
    await reveal(tester);
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
    final old = start();
    await reveal(tester);
    final next = progress.begin(NetworkRecoveryStage.retrying,
        context: NetworkRecoveryContext.startup);
    old.close();
    expect(progress.value?.stage, NetworkRecoveryStage.retrying);
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

  testWidgets('startup yields to video feedback then resumes stable copy',
      (tester) async {
    await mount(tester);
    EasyLoading.show(status: '正在保存视频…', dismissOnTap: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final video = EasyLoading.instance.w;
    final operation = start();
    await reveal(tester);
    expect(EasyLoading.instance.w, same(video));
    await EasyLoading.dismiss(animation: false);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('正在连接…'), findsOneWidget);
    operation.close();
    await tester.pump();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
