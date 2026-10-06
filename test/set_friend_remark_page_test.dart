import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/user_profile_panel/set_remark/set_remark_logic.dart';
import 'package:openim/pages/contacts/user_profile_panel/set_remark/set_remark_view.dart';
import 'package:openim/pages/mine/settings/pages/edit_nickname_page.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';
import 'package:openim_common/openim_common.dart';

class _FakeNicknameService extends StubSettingsService {
  final names = <String>[];
  bool fail = false;

  @override
  bool get isBackendAvailable => true;

  @override
  Future<void> updateNickname(String nickname) async {
    if (fail) throw StateError('unavailable');
    names.add(nickname);
  }
}

class _FakeRemarkLogic implements SetFriendRemarkLogic {
  @override
  final inputCtrl = TextEditingController(text: '原备注');

  @override
  String? get avatarURL => null;

  @override
  String? get avatarName => '用户';

  int saves = 0;

  @override
  void save() => saves++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _editorFrame = ValueKey('name-editor-frame');

Future<void> _mountEditor(
    WidgetTester tester, Widget home, Brightness brightness) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24);
  tester.view.viewPadding = const FakeViewPadding(top: 24);
  addTearDown(tester.view.reset);
  Styles.isDark = brightness == Brightness.dark;
  addTearDown(() => Styles.isDark = false);
  await tester.pumpWidget(RepaintBoundary(
    key: _editorFrame,
    child: ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        builder: EasyLoading.init(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(brightness: brightness),
        home: home,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _expectUniformEditorSurface(WidgetTester tester) async {
  final editor = find.byType(SetFriendRemarkPage);
  final scaffold = find.descendant(of: editor, matching: find.byType(Scaffold));
  final header =
      find.descendant(of: editor, matching: find.byType(GlassAppBar));
  final expected = Styles.c_F4F5F7;
  expect(tester.widget<Scaffold>(scaffold).backgroundColor, expected);
  expect(tester.widget<GlassAppBar>(header).backgroundColor, expected);
  expect(find.descendant(of: header, matching: find.byType(LiquidGlassSurface)),
      findsNothing);

  final headerRect = tester.getRect(header);
  final pageRect = tester.getRect(scaffold);
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_editorFrame));
  final origin = boundary.localToGlobal(Offset.zero);
  final samples = [
    Offset(headerRect.center.dx, pageRect.top + 12),
    Offset(headerRect.center.dx, headerRect.center.dy),
    Offset(pageRect.left + 2, headerRect.bottom + 12),
  ];
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final pixels =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      for (final sample in samples) {
        final point = sample - origin;
        final offset = (point.dy.floor() * image.width + point.dx.floor()) * 4;
        final actual = Color.fromARGB(
            pixels.getUint8(offset + 3),
            pixels.getUint8(offset),
            pixels.getUint8(offset + 1),
            pixels.getUint8(offset + 2));
        expect(actual, expected,
            reason:
                'The editor navigation and page must paint the same color.');
      }
    } finally {
      image.dispose();
    }
  });
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
        'nickname reuses remark editor and saves the validated result: $brightness',
        (tester) async {
      final store = SettingsDraftStore();
      addTearDown(store.dispose);
      final service = _FakeNicknameService();
      var avatarChanges = 0;
      String? result;
      await _mountEditor(
          tester,
          Builder(
              builder: (context) => Scaffold(
                    body: TextButton(
                      child: const Text('打开'),
                      onPressed: () async {
                        result = await Navigator.of(context)
                            .push<String>(MaterialPageRoute(
                          builder: (_) => EditNicknamePage(
                            initialNickname: '秋',
                            service: service,
                            store: store,
                            onChangeAvatar: () async => avatarChanges++,
                          ),
                        ));
                      },
                    ),
                  )),
          brightness);
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.byType(SetFriendRemarkPage), findsOneWidget);
      await _expectUniformEditorSurface(tester);
      expect(find.text('1/22'), findsOneWidget);
      expect(
          tester.widget<AvatarView>(find.byType(AvatarView)).isCircle, isTrue);
      await tester.tap(find.byType(AvatarView));
      await tester.pumpAndSettle();
      expect(avatarChanges, 1);
      expect(find.text('1/22'), findsOneWidget);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(service.names, isEmpty);
      expect(find.text('名字长度为 2-22 个字符'), findsOneWidget);
      await EasyLoading.dismiss(animation: false);
      await tester.pump();
      await tester.enterText(
          find.byType(TextField), List.filled(23, '字').join());
      await tester.pump();
      expect(find.text('22/22'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '🌻秋');
      await tester.pump();
      expect(find.text('2/22'), findsOneWidget);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(service.names, ['🌻秋']);
      expect(store.profileNickname, '🌻秋');
      expect(result, '🌻秋');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'shared group name editor keeps avatar and save actions: $brightness',
        (tester) async {
      final controller = TextEditingController(text: '测试群聊');
      addTearDown(controller.dispose);
      var avatarTaps = 0;
      final savedNames = <String>[];
      await _mountEditor(
          tester,
          SetFriendRemarkPage.editor(
            controller: controller,
            onSave: () => savedNames.add(controller.text),
            maxLength: 30,
            isGroupAvatar: true,
            onAvatarTap: () => avatarTaps++,
          ),
          brightness);
      await _expectUniformEditorSurface(tester);
      await tester.tap(find.byType(AvatarView));
      expect(avatarTaps, 1);
      await tester.enterText(find.byType(TextField), '新群名称');
      await tester.pump();
      await tester.tap(find.text('确定'));
      expect(savedNames, ['新群名称']);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'remark page shows count and enforces the 30 character limit: $brightness',
        (tester) async {
      final logic = _FakeRemarkLogic();
      addTearDown(logic.inputCtrl.dispose);
      await _mountEditor(tester, SetFriendRemarkPage(logic: logic), brightness);
      await _expectUniformEditorSurface(tester);

      expect(find.text('确定'), findsOneWidget);
      expect(find.text('3/30'), findsOneWidget);
      await tester.enterText(
          find.byType(TextField), List.filled(31, '字').join());
      await tester.pumpAndSettle();
      expect(logic.inputCtrl.text, List.filled(30, '字').join());
      expect(find.text('30/30'), findsOneWidget);
      await tester.tap(find.text('确定'));
      expect(logic.saves, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
