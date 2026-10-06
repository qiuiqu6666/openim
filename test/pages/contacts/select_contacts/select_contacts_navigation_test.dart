import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/select_contacts/group_list/group_list_logic.dart';
import 'package:openim/pages/contacts/select_contacts/group_list/group_list_view.dart';
import 'package:openim/pages/contacts/select_contacts/search_contacts/search_contacts_logic.dart';
import 'package:openim/pages/contacts/select_contacts/search_contacts/search_contacts_view.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_logic.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_view.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'friend_list/support/friend_picker_presence_fixture.dart';

const _previewDirectory = String.fromEnvironment('SELECT_CONTACTS_PREVIEW_DIR');

class _Selection extends SelectContactsLogic {
  _Selection(SelAction value) {
    action = value;
    openSelectedSheet = false;
  }

  @override
  // Only route initialization is replaced; all selection actions stay real.
  // ignore: must_call_super
  void onInit() {}

  @override
  void onReady() {}
}

class _Groups extends SelectContactsFromGroupLogic {
  _Groups(List<GroupInfo> groups) {
    allList.assignAll(groups);
  }

  @override
  void onReady() {}
}

class _Search extends SelectContactsFromSearchLogic {
  int submissions = 0;

  @override
  Future<void> search() async {
    submissions++;
  }
}

class _Fixture {
  _Fixture({SelAction action = SelAction.forward})
      : selection = _Selection(action);

  final _Selection selection;
  final navigator = GlobalKey<NavigatorState>();
  final boundary = GlobalKey();
  late Future<Object?> result;

  Future<void> open(
    WidgetTester tester, {
    required Widget Function() page,
    Brightness brightness = Brightness.light,
    Locale locale = const Locale('zh', 'CN'),
    double width = 375,
    String? fontFamily,
  }) async {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self');
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    Get.put<SelectContactsLogic>(selection, permanent: true);
    final oldDark = Styles.isDark;
    Styles.isDark = brightness == Brightness.dark;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 812);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      Get.reset();
      Styles.isDark = oldDark;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        navigatorKey: navigator,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: brightness, fontFamily: fontFamily),
        translations: TranslationService(),
        locale: locale,
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const Scaffold(body: Text('父聊天页面')),
      ),
    ));
    result = navigator.currentState!.push<Object?>(MaterialPageRoute(
      builder: (_) => RepaintBoundary(key: boundary, child: page()),
    ));
    await tester.pumpAndSettle();
  }
}

void _expectNavigation(
    WidgetTester tester, String title, Brightness brightness) {
  final bar = tester.widget<GlassAppBar>(find.byType(GlassAppBar));
  expect(bar.centerTitle, isTrue);
  expect(bar.toolbarHeight, NavigationGlassTokens.toolbarHeight);
  final titleFinder =
      find.descendant(of: find.byType(GlassAppBar), matching: find.text(title));
  expect(titleFinder, findsOneWidget);
  final label = tester.widget<Text>(titleFinder);
  expect(label.style?.fontSize, 17);
  expect(label.style?.fontWeight, FontWeight.w600);
  expect(label.style?.color,
      AppTokens.textPrimary(dark: brightness == Brightness.dark));
  expect(tester.getCenter(titleFinder).dx,
      closeTo(tester.view.physicalSize.width / 2, .01));
  final back = find.byKey(const ValueKey('select-contacts-back'));
  expect(tester.getSize(back), const Size(48, 48));
  final icon = tester
      .widget<Icon>(find.descendant(of: back, matching: find.byType(Icon)));
  expect(icon.icon, Icons.arrow_back_ios_new_rounded);
  expect(icon.color, AppTokens.accent);
  expect(icon.size, AppIconTokens.large);
  final glass = tester.widget<LiquidGlassSurface>(find.descendant(
      of: find.byType(GlassAppBar), matching: find.byType(LiquidGlassSurface)));
  expect(glass.tint, AppTokens.surface(dark: brightness == Brightness.dark));
}

void _expectCircularGroups(WidgetTester tester) {
  final groups = find
      .byWidgetPredicate((widget) => widget is AvatarView && widget.isGroup);
  expect(groups, findsWidgets);
  for (final element in groups.evaluate()) {
    final avatar = element.widget as AvatarView;
    expect(avatar.isCircle, isTrue);
    expect(
        find.descendant(
            of: find.byElementPredicate((value) => identical(value, element)),
            matching: find.byType(ClipOval)),
        findsOneWidget);
  }
}

List<GroupInfo> _groups() => [
      GroupInfo(groupID: 'locked', groupName: '已在群中', memberCount: 8),
      GroupInfo(groupID: 'group', groupName: '圆形群聊', memberCount: 22),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (_previewDirectory.isEmpty) return;
    for (final font in {
      'SelectContactsPreviewCjk': 'C:/Windows/Fonts/msyh.ttc',
      'MaterialIcons':
          'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)
            ..addFont(
                File(font.value).readAsBytes().then(ByteData.sublistView)))
          .load();
    }
    await (FontLoader('packages/font_awesome_flutter/FontAwesomeSolid')
          ..addFont(rootBundle.load(
              'packages/font_awesome_flutter/lib/fonts/fa-solid-900.ttf')))
        .load();
  });

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} forwarding title and recent group circle',
        (tester) async {
      final fixture = _Fixture();
      fixture.selection.conversationList.add(ConversationInfo(
        conversationID: 'sg_group',
        conversationType: ConversationType.superGroup,
        groupID: 'group',
        showName: '最近群聊',
      ));
      await fixture.open(tester,
          brightness: brightness, page: SelectContactsPage.new);
      _expectNavigation(tester, '选择多个会话', brightness);
      _expectCircularGroups(tester);
      await tester.tap(find.text('最近群聊'));
      await tester.pumpAndSettle();
      expect(fixture.selection.checkedList.keys, ['group']);
      await tester.tap(find.byKey(const ValueKey('select-contacts-back')));
      await tester.pumpAndSettle();
      expect(await fixture.result, isNull);
      expect(find.text('父聊天页面'), findsOneWidget);
      expect(fixture.selection.checkedList.keys, ['group']);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '${brightness.name} group navigation preserves disabled and select-all',
        (tester) async {
      final fixture = _Fixture();
      fixture.selection.defaultCheckedIDList.add('locked');
      await fixture.open(tester, brightness: brightness, page: () {
        Get.put<SelectContactsFromGroupLogic>(_Groups(_groups()),
            permanent: true);
        return SelectContactsFromGroupPage();
      });
      _expectNavigation(tester, StrRes.myGroup, brightness);
      _expectCircularGroups(tester);
      await tester.tap(find.text('已在群中'));
      await tester.pumpAndSettle();
      expect(fixture.selection.checkedList, isEmpty);
      await tester.tap(find.text(StrRes.selectAll));
      await tester.pumpAndSettle();
      expect(fixture.selection.checkedList.keys, ['group']);
      await tester.tap(find.text(StrRes.selectAll));
      await tester.pumpAndSettle();
      expect(fixture.selection.checkedList, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '${brightness.name} friend and member-purpose titles share navigation',
        (tester) async {
      final fixture = FriendPickerPresenceFixture(action: SelAction.addMember);
      await fixture.open(tester, brightness: brightness);
      _expectNavigation(tester, 'groupSelectContacts'.tr, brightness);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('friend subpage retains its purpose title', (tester) async {
    final fixture = FriendPickerPresenceFixture(action: SelAction.forward);
    await fixture.open(tester);
    _expectNavigation(tester, StrRes.myFriend, Brightness.light);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recommendation has its purpose title', (tester) async {
    final fixture = _Fixture(action: SelAction.recommend);
    await fixture.open(tester, page: SelectContactsPage.new);
    _expectNavigation(tester, StrRes.recommendToFriend, Brightness.light);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English forwarding title is localized', (tester) async {
    final fixture = _Fixture();
    await fixture.open(tester,
        locale: const Locale('en', 'US'), page: SelectContactsPage.new);
    _expectNavigation(tester, 'Select conversations', Brightness.light);
  });

  testWidgets('search keeps input submission, focus and circular group results',
      (tester) async {
    final fixture = _Fixture();
    late _Search search;
    await fixture.open(tester, page: () {
      search =
          Get.put<SelectContactsFromSearchLogic>(_Search(), permanent: true)
              as _Search;
      return SelectContactsFromSearchPage();
    });
    expect(find.byType(TextField), findsOneWidget);
    expect(search.focusNode.hasFocus, isTrue);
    await tester.enterText(find.byType(TextField), '圆形');
    search.resultList.add(_groups().last);
    await tester.pumpAndSettle();
    _expectCircularGroups(tester);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(search.submissions, 1);
    await tester.tap(find
        .byWidgetPredicate((widget) => widget is AvatarView && widget.isGroup));
    await tester.pumpAndSettle();
    expect(fixture.selection.checkedList.keys, ['group']);
    search.searchCtrl.clear();
    await tester.pumpAndSettle();
    expect(search.resultList, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final groupPage in [false, true]) {
      testWidgets(
          'export ${brightness.name} ${groupPage ? 'groups' : 'forward'} navigation',
          skip: _previewDirectory.isEmpty, (tester) async {
        final fixture = _Fixture();
        fixture.selection.conversationList.add(ConversationInfo(
            conversationID: 'sg_group',
            conversationType: ConversationType.superGroup,
            groupID: 'group',
            showName: '最近群聊'));
        await fixture.open(tester,
            brightness: brightness,
            fontFamily: 'SelectContactsPreviewCjk', page: () {
          if (!groupPage) return SelectContactsPage();
          Get.put<SelectContactsFromGroupLogic>(_Groups(_groups()),
              permanent: true);
          return SelectContactsFromGroupPage();
        });
        await tester.pumpAndSettle();
        final boundary = fixture.boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory(_previewDirectory);
          await directory.create(recursive: true);
          await File(
                  '${directory.path}/select-contacts-${groupPage ? 'groups' : 'forward'}-${brightness.name}.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
      });
    }
  }
}
