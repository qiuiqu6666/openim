import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/folders/folder_name_dialog.dart';

class _DialogResult {
  String? value;
  bool completed = false;
}

class _PopObserver extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}

Future<_DialogResult> _openDialog(
  WidgetTester tester, {
  FolderNameDialog dialog = const FolderNameDialog(),
  bool dark = false,
  Locale locale = const Locale('zh', 'CN'),
  bool nestedPage = false,
  List<NavigatorObserver> observers = const [],
}) async {
  final result = _DialogResult();
  final launcher = Scaffold(
    body: Builder(builder: (context) {
      return TextButton(
        onPressed: () async {
          result.value = await showCupertinoDialog<String>(
            context: context,
            barrierDismissible: true,
            builder: (_) => dialog,
          );
          result.completed = true;
        },
        child: const Text('打开'),
      );
    }),
  );
  await tester.pumpWidget(MaterialApp(
    navigatorObservers: observers,
    locale: locale,
    supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
    home: nestedPage
        ? Scaffold(body: Builder(builder: (context) {
            return TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => launcher)),
              child: const Text('进入分组页'),
            );
          }))
        : launcher,
  ));
  if (nestedPage) {
    await tester.tap(find.text('进入分组页'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
  return result;
}

Future<void> _disposeHost(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  for (final trigger in ['confirm twice', 'IME then confirm', 'cancel twice']) {
    testWidgets('queued $trigger only pops the dialog above a nested page',
        (tester) async {
      final observer = _PopObserver();
      final result = await _openDialog(tester,
          nestedPage: true, observers: [observer]);
      await tester.enterText(find.byType(CupertinoTextField), '  测试分组  ');
      final confirm = tester.widget<CupertinoDialogAction>(find.ancestor(
        of: find.text('确定'),
        matching: find.byType(CupertinoDialogAction),
      )).onPressed!;
      final cancel = tester.widget<CupertinoDialogAction>(find.ancestor(
        of: find.text('取消'),
        matching: find.byType(CupertinoDialogAction),
      )).onPressed!;
      // Deliver queued events before the closing animation rebuilds the page.
      if (trigger == 'IME then confirm') {
        await tester.testTextInput.receiveAction(TextInputAction.done);
        confirm();
      } else if (trigger == 'cancel twice') {
        cancel();
        cancel();
      } else {
        confirm();
        confirm();
      }
      await tester.pumpAndSettle();
      expect(observer.popCount, 1);
      expect(result.completed, isTrue);
      expect(result.value, trigger == 'cancel twice' ? null : '测试分组');
      expect(find.byType(FolderNameDialog), findsNothing);
      expect(find.text('打开'), findsOneWidget);
      expect(find.text('进入分组页'), findsNothing);
      await _disposeHost(tester);
    });
  }

  for (final confirm in [false, true]) {
    testWidgets(
        'folder dialog closes cleanly when ${confirm ? 'confirmed' : 'cancelled'}',
        (tester) async {
      final result = await _openDialog(tester);
      final controller =
          tester.widget<CupertinoTextField>(find.byType(CupertinoTextField))
              .controller!;
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('新建分组'), findsOneWidget);
      expect(find.text('保存'), findsNothing);
      if (confirm) {
        await tester.enterText(find.byType(CupertinoTextField), '  测试分组  ');
      }
      await tester.tap(find.text(confirm ? '确定' : '取消'));
      await tester.pumpAndSettle();

      expect(result.completed, isTrue);
      expect(result.value, confirm ? '测试分组' : null);
      expect(find.byType(FolderNameDialog), findsNothing);
      expect(() => controller.addListener(() {}), throwsFlutterError);
      expect(tester.takeException(), isNull);
      await _disposeHost(tester);
    });
  }

  testWidgets('whitespace names keep the dialog open without validation',
      (tester) async {
    final validated = <String>[];
    final result = await _openDialog(tester,
        dialog: FolderNameDialog(validator: (name) {
      validated.add(name);
      return null;
    }));
    await tester.enterText(find.byType(CupertinoTextField), '   ');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(result.completed, isFalse);
    expect(find.byType(FolderNameDialog), findsOneWidget);
    expect(validated, isEmpty);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(result.completed, isFalse);
    expect(validated, isEmpty);
    await tester.enterText(find.byType(CupertinoTextField), '  家人  ');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(result.value, '家人');
    expect(validated, ['家人']);
    await _disposeHost(tester);
  });

  testWidgets('renaming preserves the existing name and accepts keyboard done',
      (tester) async {
    final result = await _openDialog(tester,
        dialog: const FolderNameDialog(initialName: '旧分组'));
    final input =
        tester.widget<CupertinoTextField>(find.byType(CupertinoTextField));
    expect(find.text('重命名分组'), findsOneWidget);
    expect(input.controller!.text, '旧分组');
    expect(input.textInputAction, TextInputAction.done);
    await tester.enterText(find.byType(CupertinoTextField), '  新分组  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(result.completed, isTrue);
    expect(result.value, '新分组');
    await _disposeHost(tester);
  });

  testWidgets('input enforces the reference sixteen-character limit',
      (tester) async {
    final result = await _openDialog(tester);
    final input =
        tester.widget<CupertinoTextField>(find.byType(CupertinoTextField));
    expect(input.maxLength, 16);
    expect(input.autofocus, isTrue);
    expect(input.placeholder, '分组名称');
    await tester.enterText(find.byType(CupertinoTextField), '12345678901234567');
    expect(input.controller!.text, '1234567890123456');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(result.value, '1234567890123456');
    await _disposeHost(tester);
  });

  for (final dark in [false, true]) {
    testWidgets('Cupertino folder dialog follows ${dark ? 'dark' : 'light'} theme',
        (tester) async {
      await _openDialog(tester, dark: dark);
      final dialog = tester.widget<CupertinoAlertDialog>(
          find.byType(CupertinoAlertDialog));
      final content = dialog.content! as Padding;
      expect(content.padding, const EdgeInsets.only(top: 12));
      final inputContext = tester.element(find.byType(CupertinoTextField));
      expect(CupertinoTheme.of(inputContext).brightness,
          dark ? Brightness.dark : Brightness.light);
      final confirm = tester.widget<CupertinoDialogAction>(find.ancestor(
        of: find.text('确定'),
        matching: find.byType(CupertinoDialogAction),
      ));
      expect(confirm.isDefaultAction, isTrue);
      expect(confirm.isDestructiveAction, isFalse);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await _disposeHost(tester);
    });
  }

  for (final rename in [false, true]) {
    testWidgets('folder dialog uses English labels (${rename ? 'rename' : 'new'})',
        (tester) async {
      final result = await _openDialog(tester,
          locale: const Locale('en', 'US'),
          dialog: FolderNameDialog(initialName: rename ? 'Friends' : null));
      expect(find.text(rename ? 'Rename folder' : 'New folder'), findsOneWidget);
      expect(tester.widget<CupertinoTextField>(find.byType(CupertinoTextField))
          .placeholder, 'Folder name');
      expect(find.text('OK'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result.completed, isTrue);
      expect(result.value, isNull);
      await _disposeHost(tester);
    });
  }

  testWidgets('validator receives a trimmed name and rejection preserves input',
      (tester) async {
    final validated = <String>[];
    final result = await _openDialog(tester,
        dialog: FolderNameDialog(validator: (name) {
      validated.add(name);
      return name == '朋友' ? '分组名称已存在' : null;
    }));
    final controller =
        tester.widget<CupertinoTextField>(find.byType(CupertinoTextField))
            .controller!;
    await tester.enterText(find.byType(CupertinoTextField), '  朋友  ');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(validated, ['朋友']);
    expect(result.completed, isFalse);
    expect(find.byType(FolderNameDialog), findsOneWidget);
    expect(find.text('分组名称已存在'), findsOneWidget);
    expect(controller.text, '  朋友  ');
    expect(tester.widget<CupertinoTextField>(find.byType(CupertinoTextField))
        .controller, same(controller));

    await tester.enterText(find.byType(CupertinoTextField), '同事');
    await tester.pumpAndSettle();
    expect(find.text('分组名称已存在'), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(validated, ['朋友', '同事']);
    expect(result.value, '同事');
    await _disposeHost(tester);
  });

  testWidgets('cancel after a rejected name disposes the controller cleanly',
      (tester) async {
    final result = await _openDialog(tester,
        dialog: FolderNameDialog(validator: (_) => '分组名称已存在'));
    final controller =
        tester.widget<CupertinoTextField>(find.byType(CupertinoTextField))
            .controller!;
    await tester.enterText(find.byType(CupertinoTextField), '朋友');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('分组名称已存在'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result.completed, isTrue);
    expect(result.value, isNull);
    expect(() => controller.addListener(() {}), throwsFlutterError);
    await _disposeHost(tester);
  });
}
