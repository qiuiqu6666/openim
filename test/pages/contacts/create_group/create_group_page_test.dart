import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/create_group/create_group_logic.dart';
import 'package:openim/pages/contacts/create_group/create_group_view.dart';
import 'package:openim/pages/mine/settings/pages/legal_document_page.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/create_group_test_logic.dart';

const _create = ValueKey('create-group-create');
const _avatar = ValueKey('create-group-avatar');
const _nameInput = ValueKey('create-group-name-input');
const _nameCount = ValueKey('create-group-name-count');
const _addMembers = ValueKey('create-group-add-members');
const _addMemberTile = ValueKey('create-group-add-member-tile');
const _terms = ValueKey('create-group-terms');

Future<void> _mount(
  WidgetTester tester,
  CreateGroupTestLogic logic, {
  bool dark = false,
  Size size = const Size(375, 812),
  double textScale = 1,
  double keyboardHeight = 0,
  bool reducedMotion = false,
}) async {
  Get.testMode = true;
  Styles.isDark = dark;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  Get.put<CreateGroupLogic>(logic);
  final landscape = size.width > size.height;
  final safePadding = landscape
      ? const EdgeInsets.fromLTRB(44, 24, 44, 21)
      : const EdgeInsets.fromLTRB(0, 24, 0, 34);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    fontSizeResolver: (size, _) => size.toDouble(),
    builder: (_, __) => GetMaterialApp(
      debugShowCheckedModeBanner: false,
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          platform: TargetPlatform.android,
          colorSchemeSeed: AppTokens.accent),
      builder: EasyLoading.init(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: safePadding.copyWith(
                bottom: keyboardHeight > 0 ? 0 : safePadding.bottom),
            viewPadding: safePadding,
            viewInsets: EdgeInsets.only(bottom: keyboardHeight),
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reducedMotion,
          ),
          child: child!,
        ),
      ),
      home: CreateGroupPage(),
    ),
  ));
  await tester.pumpAndSettle();
}

void _pageTest(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      await EasyLoading.dismiss(animation: false);
      await tester.pumpWidget(const SizedBox.shrink());
      Get.reset();
      Styles.isDark = false;
      await tester.pump(const Duration(milliseconds: 600));
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await NavigationGlassController.instance
        .setMode(NavigationGlassMode.translucent);
  });

  _pageTest('creation avatar and both member actions use the registered logic',
      (tester) async {
    final logic = CreateGroupTestLogic(members: createGroupTestMembers(2));
    await _mount(tester, logic);
    expect(find.text('新建群聊'), findsOneWidget);
    expect(find.text('创建'), findsOneWidget);
    expect(find.text('群类型'), findsNothing);
    expect(find.text(StrRes.completeCreation), findsNothing);
    expect(find.byType(Button), findsNothing);
    await tester.tap(find.byKey(_avatar));
    expect(logic.avatarSelections, 1);
    await tester.tap(find.byKey(_addMembers));
    await tester.ensureVisible(find.byKey(_addMemberTile));
    await tester.tap(find.byKey(_addMemberTile));
    expect(logic.memberOperations, [false, false]);
    await tester.enterText(find.byKey(_nameInput), '我们的小组');
    await tester.tap(find.byKey(_create));
    await tester.pumpAndSettle();
    expect(logic.submittedNames, ['我们的小组']);
    expect(logic.submittedMembers, [
      ['member-1', 'member-2']
    ]);
    expect(tester.takeException(), isNull);
  });

  _pageTest('name count and limit preserve complete emoji graphemes',
      (tester) async {
    final logic = CreateGroupTestLogic();
    await _mount(tester, logic);
    expect(find.byKey(_nameCount), findsOneWidget);
    expect(find.text('0/30'), findsOneWidget);
    await tester.enterText(find.byKey(_nameInput), '测试👩🏽‍💻');
    await tester.pump();
    expect(find.text('3/30'), findsOneWidget);
    const family = '👨‍👩‍👧‍👦';
    final thirty = '${List.filled(29, family).join()}👋🏽';
    await tester.enterText(find.byKey(_nameInput), '$thirty🚀');
    await tester.pump();
    expect(logic.nameCtrl.text, thirty);
    expect(logic.nameCtrl.text.characters.length, 30);
    expect(find.text('30/30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _pageTest(
      'member selection refreshes the count and exposes members after eight',
      (tester) async {
    final logic = CreateGroupTestLogic(members: createGroupTestMembers(2));
    await _mount(tester, logic);
    expect(find.text('群成员（2）'), findsOneWidget);
    logic.membersAfterSelection = createGroupTestMembers(12);
    await tester.tap(find.byKey(_addMembers));
    await tester.pumpAndSettle();
    expect(find.text('群成员（12）'), findsOneWidget);
    for (final member in logic.allList) {
      final name = find.text(member.nickname!);
      expect(name, findsOneWidget);
      await tester.ensureVisible(name);
      await tester.pump();
      final rect = tester.getRect(name);
      expect(rect.top, greaterThanOrEqualTo(24));
      expect(rect.bottom, lessThanOrEqualTo(812 - 34));
    }
    logic.allList.removeLast();
    await tester.pump();
    expect(find.text('群成员（11）'), findsOneWidget);
    expect(find.text('成员12'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  _pageTest('empty group name hints the latest members without becoming text',
      (tester) async {
    final logic = CreateGroupTestLogic(members: createGroupTestMembers(2));
    await _mount(tester, logic);
    TextField input() => tester.widget<TextField>(find.byKey(_nameInput));
    expect(input().controller!.text, isEmpty);
    expect(input().decoration!.hintText, '成员01、成员02');
    expect(find.text('0/30'), findsOneWidget);
    logic.allList.addAll(createGroupTestMembers(4).skip(2));
    await tester.pump();
    expect(input().decoration!.hintText, '成员01、成员02等4人');
    await tester.enterText(find.byKey(_nameInput), '原群名称');
    logic.allList.removeLast();
    await tester.pump();
    expect(input().controller!.text, '原群名称');
    await tester.enterText(find.byKey(_nameInput), '');
    await tester.pump();
    expect(input().decoration!.hintText, '成员01、成员02等3人');
  });

  _pageTest('existing group draft supports appending and editing in the middle',
      (tester) async {
    final logic =
        CreateGroupTestLogic(members: createGroupTestMembers(2), name: '原群名称');
    await _mount(tester, logic);
    expect(logic.nameCtrl.text, '原群名称');
    await tester.tap(find.byKey(_nameInput));
    await tester.pump();
    logic.nameCtrl.selection = const TextSelection.collapsed(offset: 4);
    tester.testTextInput.enterText('原群名称追加');
    await tester.pump();
    expect(logic.nameCtrl.text, '原群名称追加');
    logic.nameCtrl.selection = const TextSelection.collapsed(offset: 2);
    tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: '原群新名称追加', selection: TextSelection.collapsed(offset: 3)));
    await tester.pump();
    expect(logic.nameCtrl.text, '原群新名称追加');
    await tester.tap(find.byKey(_create));
    await tester.pumpAndSettle();
    expect(logic.submittedNames, ['原群新名称追加']);
  });

  _pageTest(
      'terms opens the existing legal document and preserves the group name',
      (tester) async {
    final logic = CreateGroupTestLogic(members: createGroupTestMembers(3));
    await _mount(tester, logic);
    await tester.enterText(find.byKey(_nameInput), '保留的群名👋🏽');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.ensureVisible(find.byKey(_terms));
    await tester.tap(find.byKey(_terms));
    await tester.pumpAndSettle();
    final legal =
        tester.widget<LegalDocumentPage>(find.byType(LegalDocumentPage));
    expect(legal.kind, LegalDocumentKind.terms);
    expect(find.byKey(const ValueKey('settings-legal-document-body')),
        findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(LegalDocumentPage),
        matching: find.byIcon(Icons.arrow_back_ios_new_rounded)));
    await tester.pumpAndSettle();
    expect(find.byType(CreateGroupPage), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(_nameInput)).controller?.text,
        '保留的群名👋🏽');
    expect(logic.submittedNames, isEmpty);
    expect(logic.allList, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  _pageTest('pending creation prevents duplicate submit and disables editing',
      (tester) async {
    final logic = CreateGroupTestLogic(members: createGroupTestMembers(2))
      ..creationGate = Completer<void>();
    await _mount(tester, logic);
    await tester.enterText(find.byKey(_nameInput), '等待创建');
    await tester.tap(find.byKey(_create));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(_nameInput)).enabled, isFalse);
    await tester.tap(find.byKey(_nameInput), warnIfMissed: false);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.tap(find.byKey(_create), warnIfMissed: false);
    await tester.tap(find.byKey(_avatar), warnIfMissed: false);
    await tester.tap(find.byKey(_addMembers), warnIfMissed: false);
    await tester.ensureVisible(find.byKey(_addMemberTile));
    await tester.tap(find.byKey(_addMemberTile), warnIfMissed: false);
    expect(logic.submittedNames, ['等待创建']);
    expect(logic.avatarSelections, 0);
    expect(logic.memberOperations, isEmpty);
    logic.creationGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
        tester.widget<TextField>(find.byKey(_nameInput)).enabled, isNot(false));
    expect(logic.nameCtrl.text, '等待创建');
    await tester.tap(find.byKey(_avatar));
    expect(logic.avatarSelections, 1);
    expect(tester.takeException(), isNull);
  });

  _pageTest('failed creation keeps edits and restores retry', (tester) async {
    final logic = CreateGroupTestLogic(members: createGroupTestMembers(2))
      ..failCreation = true;
    await _mount(tester, logic);
    await tester.enterText(find.byKey(_nameInput), '创建失败保留我');
    await tester.tap(find.byKey(_create));
    await tester.pumpAndSettle();
    expect(find.text('创建失败，请重试'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(logic.nameCtrl.text, '创建失败保留我');
    expect(
        tester.widget<TextField>(find.byKey(_nameInput)).enabled, isNot(false));
    logic.failCreation = false;
    await tester.tap(find.byKey(_create));
    await tester.pumpAndSettle();
    expect(logic.submittedNames, ['创建失败保留我', '创建失败保留我']);
    expect(tester.takeException(), isNull);
  });

  _pageTest(
      'finishing creation after leaving the page does not update disposed UI',
      (tester) async {
    final logic = CreateGroupTestLogic(members: createGroupTestMembers(2))
      ..creationGate = Completer<void>();
    await _mount(tester, logic);
    await tester.tap(find.byKey(_create));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    logic.creationGate!.complete();
    await tester.pump();
    expect(logic.submittedNames, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final scenario in [
      (
        name: 'phone',
        size: const Size(375, 812),
        scale: 1.0,
        keyboard: 0.0,
        reducedMotion: false,
      ),
      (
        name: 'narrow keyboard',
        size: const Size(320, 568),
        scale: 1.0,
        keyboard: 220.0,
        reducedMotion: false,
      ),
      (
        name: 'large landscape',
        size: const Size(812, 375),
        scale: 2.0,
        keyboard: 0.0,
        reducedMotion: false,
      ),
      (
        name: 'narrow large text and reduced motion',
        size: const Size(320, 568),
        scale: 2.0,
        keyboard: 0.0,
        reducedMotion: true,
      ),
    ]) {
      _pageTest(
          '${scenario.name} keeps creation and all content reachable ($dark)',
          (tester) async {
        final logic = CreateGroupTestLogic(members: createGroupTestMembers(12));
        await _mount(tester, logic,
            dark: dark,
            size: scenario.size,
            textScale: scenario.scale,
            keyboardHeight: scenario.keyboard,
            reducedMotion: scenario.reducedMotion);
        final create = tester.getRect(find.byKey(_create));
        expect(create.top, greaterThanOrEqualTo(24));
        expect(create.right, lessThanOrEqualTo(scenario.size.width));
        expect(create.bottom,
            lessThanOrEqualTo(scenario.size.height - scenario.keyboard));
        await tester.ensureVisible(find.byKey(_nameInput));
        await tester.enterText(find.byKey(_nameInput), '键盘和大字体仍可编辑');
        await tester.pump();
        expect(logic.nameCtrl.text, '键盘和大字体仍可编辑');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        for (final target in [
          find.text('成员12'),
          find.byKey(_addMemberTile),
          find.byKey(_terms),
        ]) {
          await tester.ensureVisible(target);
          await tester.pump();
          final rect = tester.getRect(target);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(scenario.size.width));
          final visible = rect.intersect(Rect.fromLTRB(0, create.bottom,
              scenario.size.width, scenario.size.height - scenario.keyboard));
          expect(visible.isEmpty, isFalse);
        }
        expect(tester.takeException(), isNull);
        final terms = tester.getRect(find.byKey(_terms));
        final termsEntry = terms.intersect(Rect.fromLTRB(0, create.bottom,
            scenario.size.width, scenario.size.height - scenario.keyboard));
        await tester.tapAt(termsEntry.center);
        await tester.pumpAndSettle();
        expect(
            tester
                .widget<LegalDocumentPage>(find.byType(LegalDocumentPage))
                .kind,
            LegalDocumentKind.terms);
        await tester.tap(find.descendant(
            of: find.byType(LegalDocumentPage),
            matching: find.byIcon(Icons.arrow_back_ios_new_rounded)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_create));
        await tester.pumpAndSettle();
        expect(logic.submittedNames, ['键盘和大字体仍可编辑']);
      });
    }
  }
}
