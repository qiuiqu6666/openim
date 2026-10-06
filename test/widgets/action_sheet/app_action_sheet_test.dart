import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/widgets/settings_widgets.dart';
import 'package:openim_common/openim_common.dart';

class _Fixture {
  final results = <int?>[];

  Future<void> open(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    Locale locale = const Locale('zh', 'CN'),
    String title = '',
    bool compatibilityEntry = false,
    List<AppAction<int>> actions = const [
      AppAction('保存到相册', 1, subtitle: '保存原图'),
      AppAction('暂不可用', 2, enabled: false, subtitle: '权限不足'),
      AppAction('删除', 3, destructive: true),
    ],
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: brightness),
      locale: locale,
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('zh', 'TW'),
        Locale('en', 'US'),
        Locale('ja', 'JP'),
        Locale('ko', 'KR'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = compatibilityEntry
                  ? await showSettingsActionSheet<int>(context,
                      title: title, actions: actions)
                  : await showAppActionSheet<int>(context,
                      title: title, actions: actions);
              results.add(result);
            },
            child: const Text('打开菜单'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('打开菜单'));
    await tester.pumpAndSettle();
  }
}

Finder _action(String label) =>
    find.widgetWithText(CupertinoActionSheetAction, label);

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} shared sheet preserves choice and theme',
        (tester) async {
      final fixture = _Fixture();
      await fixture.open(tester, brightness: brightness, title: '媒体操作');
      final sheet = tester
          .widget<CupertinoActionSheet>(find.byType(CupertinoActionSheet));
      expect(sheet.title, isNotNull);
      expect(sheet.actions, hasLength(3));
      expect(sheet.cancelButton, isNotNull);
      expect(find.byType(BottomSheet), findsNothing);
      final heading = tester.widget<Text>(find.text('媒体操作'));
      expect(heading.style?.fontSize, 13);
      expect(heading.style?.fontWeight, FontWeight.w600);
      final subtitle = tester.widget<Text>(find.text('保存原图'));
      expect(subtitle.style?.fontSize, 12);
      expect(
          subtitle.style?.color,
          CupertinoColors.secondaryLabel
              .resolveFrom(tester.element(find.text('保存原图'))));
      final disabled = tester.widget<Text>(find.text('暂不可用'));
      final detail = tester.widget<Text>(find.text('权限不足'));
      final disabledColor = CupertinoColors.systemGrey
          .resolveFrom(tester.element(find.text('暂不可用')));
      expect(disabled.style?.color, disabledColor);
      expect(detail.style?.color, disabledColor);
      final destructive =
          tester.widget<CupertinoActionSheetAction>(_action('删除'));
      expect(destructive.isDestructiveAction, isTrue);
      expect(
          DefaultTextStyle.of(tester.element(find.text('删除'))).style.color,
          CupertinoColors.systemRed
              .resolveFrom(tester.element(find.text('删除'))));
      await tester.tap(_action('保存到相册'));
      await tester.pumpAndSettle();
      expect(fixture.results, [1]);
      expect(find.byType(CupertinoActionSheet), findsNothing);
      expect(find.text('打开菜单'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '${brightness.name} disabled choice stays open and cannot resolve',
        (tester) async {
      final fixture = _Fixture();
      await fixture.open(tester, brightness: brightness, title: '   ');
      expect(
          tester
              .widget<CupertinoActionSheet>(find.byType(CupertinoActionSheet))
              .title,
          isNull);
      await tester.tap(_action('暂不可用'));
      await tester.pumpAndSettle();
      expect(fixture.results, isEmpty);
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      await tester.tap(_action('取消'));
      await tester.pumpAndSettle();
      expect(fixture.results, [null]);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '${brightness.name} settings compatibility keeps the same shared sheet',
        (tester) async {
      const AppAction<int> selected = SettingsAction<int>('当前选择', 7,
          key: ValueKey('selected-action'), selected: true, subtitle: '当前分组');
      final fixture = _Fixture();
      await fixture.open(tester,
          brightness: brightness,
          compatibilityEntry: true,
          actions: [
            selected,
            const SettingsAction('删除', 8, destructive: true)
          ]);
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      final selectionSemantics = find.ancestor(
          of: find.text('当前选择'),
          matching: find.byWidgetPredicate((widget) =>
              widget is Semantics && widget.properties.selected == true));
      expect(selectionSemantics, findsOneWidget);
      expect(find.byKey(const ValueKey('selected-action')).evaluate().single,
          selectionSemantics.evaluate().single);
      expect(find.byIcon(Icons.check), findsNothing,
          reason: 'Selected state does not add another visual menu layout.');
      await tester.tap(_action('当前选择'));
      await tester.pumpAndSettle();
      expect(fixture.results, [7]);
      expect(find.byType(CupertinoActionSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (locale, label) in const [
    (Locale('en', 'US'), 'Cancel'),
    (Locale('zh', 'TW'), '取消'),
    (Locale('ja', 'JP'), 'キャンセル'),
    (Locale('ko', 'KR'), '취소'),
  ]) {
    testWidgets('${locale.toLanguageTag()} cancel returns no operation',
        (tester) async {
      final fixture = _Fixture();
      await fixture.open(tester, locale: locale);
      expect(_action(label), findsOneWidget);
      await tester.tap(_action(label));
      await tester.pumpAndSettle();
      expect(fixture.results, [null]);
      expect(find.text('打开菜单'), findsOneWidget);
    });
  }

  testWidgets('repeated choice closes only its own sheet once', (tester) async {
    final fixture = _Fixture();
    await fixture.open(tester);
    final choose =
        tester.widget<CupertinoActionSheetAction>(_action('保存到相册')).onPressed;
    choose();
    choose();
    await tester.pumpAndSettle();
    expect(fixture.results, [1]);
    expect(find.byType(CupertinoActionSheet), findsNothing);
    expect(find.text('打开菜单'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final closeWithBack in [false, true]) {
    testWidgets(
        '${closeWithBack ? 'system back' : 'barrier'} closes without a choice',
        (tester) async {
      final fixture = _Fixture();
      await fixture.open(tester);
      if (closeWithBack) {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tapAt(const Offset(20, 20));
      }
      await tester.pumpAndSettle();
      expect(fixture.results, [null]);
      expect(find.byType(CupertinoActionSheet), findsNothing);
      expect(find.text('打开菜单'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
