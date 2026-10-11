import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/widgets/settings_widgets.dart';
import 'package:openim_common/openim_common.dart';

Future<BuildContext> _mount(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.android,
  Brightness brightness = Brightness.light,
  Size size = const Size(375, 812),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  late BuildContext context;
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(platform: platform, brightness: brightness),
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => MediaQuery(
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Builder(builder: (value) {
      context = value;
      return const Scaffold(body: Text('Page'));
    }),
  ));
  return context;
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'settings confirmation stays Cupertino ($platform, $brightness)',
          (tester) async {
        final context =
            await _mount(tester, platform: platform, brightness: brightness);
        final result = showSettingsConfirm(context,
            title: '删除',
            message: '确认删除选中内容？',
            confirmText: '删除',
            destructive: true);
        await tester.pumpAndSettle();
        final dialog = find.byType(CupertinoAlertDialog);
        expect(dialog, findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(
            CupertinoTheme.of(tester.element(dialog)).brightness, brightness);
        final action = tester.widget<CupertinoDialogAction>(
            find.widgetWithText(CupertinoDialogAction, '删除'));
        expect(action.isDestructiveAction, isTrue);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(dialog, findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(await result, isFalse);
        expect(find.text('Page'), findsOneWidget);
      });
    }
  }

  testWidgets('choice dismissal differs from choosing the false action',
      (tester) async {
    final context = await _mount(tester);
    Future<bool?> open() => showAppAlert<bool>(context,
        title: '上次收藏未完成',
        message: '重试上次收藏，或选择新的文件？',
        barrierDismissible: true,
        actions: const [AppAction('选择新文件', false), AppAction('重试', true)]);
    final dismissed = open();
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(await dismissed, isNull);
    final choice = open();
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择新文件'));
    await tester.pumpAndSettle();
    expect(await choice, isFalse);
  });

  testWidgets('disabled actions and rapid confirmation cannot pop the page',
      (tester) async {
    final context = await _mount(tester);
    final result = showAppAlert<int>(context, title: '操作', actions: const [
      AppAction('不可用', 1, enabled: false),
      AppAction('确定', 2),
    ]);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<CupertinoDialogAction>(
                find.widgetWithText(CupertinoDialogAction, '不可用'))
            .onPressed,
        isNull);
    final callback = tester
        .widget<CupertinoDialogAction>(
            find.widgetWithText(CupertinoDialogAction, '确定'))
        .onPressed!;
    callback();
    callback();
    await tester.pumpAndSettle();
    expect(await result, 2);
    expect(find.text('Page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 568), const Size(812, 375)]) {
    testWidgets('long message and large text keep actions reachable ($size)',
        (tester) async {
      final context = await _mount(tester, size: size, scale: 2);
      final result = showAppAlert<void>(context,
          title: '交易安全验证',
          message: List.filled(15, '请先绑定手机号，再进行本次交易短信验证。').join('\n'),
          actions: const [AppAction('知道了', null)]);
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      await result;
      expect(find.text('Page'), findsOneWidget);
    });
  }

  testWidgets('legacy dialog retains content and custom button callbacks',
      (tester) async {
    final context = await _mount(tester);
    var confirms = 0;
    final result = showDialog<bool>(
        context: context,
        builder: (dialog) => CustomDialog(
              title: '提示',
              content: '已有提示内容',
              leftText: '返回',
              rightText: '继续',
              onTapLeft: () => Navigator.of(dialog).pop(false),
              onTapRight: () {
                confirms++;
                Navigator.of(dialog).pop(true);
              },
            ));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.text('已有提示内容'), findsOneWidget);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    expect(confirms, 1);
  });
}
