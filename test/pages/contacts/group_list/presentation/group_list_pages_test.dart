import 'dart:io';
import 'dart:ui' as ui;

import 'package:azlistview/azlistview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/group_list/group_list_logic.dart';
import 'package:openim/pages/contacts/group_list/group_list_view.dart';
import 'package:openim/pages/contacts/select_contacts/group_list/group_list_logic.dart';
import 'package:openim/pages/contacts/select_contacts/group_list/group_list_view.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_logic.dart';
import 'package:openim_common/openim_common.dart';

import '../../select_contacts/friend_list/support/friend_picker_presence_fixture.dart';

const previewDirectory = String.fromEnvironment('GROUP_LIST_PREVIEW_DIR');

class _Directory extends GroupListLogic {
  _Directory(List<GroupInfo> groups)
      : super(
            currentUserID: () => 'self',
            fetchPage: (offset, count) async =>
                groups.skip(offset).take(count).toList());

  @override
  get groupFeatures => null;

  @override
  // Exercise real paged loading without subscribing to the test IM stub.
  // ignore: must_call_super
  void onInit() {
    iCreatedInitial();
    iJoinedInitial();
  }
}

List<GroupInfo> samples({String owner = 'self'}) => [
      for (var i = 0; i < 40; i++)
        GroupInfo(
            groupID: '$owner-a$i',
            groupName: 'Alice $i',
            memberCount: 18,
            ownerUserID: owner),
      GroupInfo(
          groupID: '$owner-z',
          groupName: '张三的项目群',
          memberCount: 25,
          ownerUserID: owner),
      GroupInfo(
          groupID: '$owner-number',
          groupName: '999群',
          memberCount: 25,
          ownerUserID: owner),
    ];

Future<void> scrollTo(WidgetTester tester, Finder target,
    {double delta = 500}) async {
  await tester.scrollUntilVisible(target, delta,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 100,
      duration: const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (previewDirectory.isEmpty) return;
    for (final font in {
      'GroupListPreview': 'C:/Windows/Fonts/msyh.ttc',
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
    testWidgets(
        '${brightness.name} My Groups scrolls through every page and counts the unified directory',
        (tester) async {
      final fixture = FriendPickerPresenceFixture(action: SelAction.forward);
      await fixture.open(tester,
          brightness: brightness, width: 320, textScale: 2);
      final logic = Get.put(
          _Directory([...samples(), ...samples(owner: 'peer').skip(1)])
            ..count = 20);
      GroupInfo? selected;
      fixture.navigator.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => GroupListPage(
              logic: logic, onSelected: (group) => selected = group)));
      await tester.pumpAndSettle();
      expect(find.byType(IndexBar), findsOneWidget);
      expect(find.text(StrRes.iCreatedGroup), findsNothing);
      expect(find.text(StrRes.iJoinedGroup), findsNothing);
      expect(logic.iCreatedList, hasLength(42));
      expect(logic.iJoinedList, hasLength(41));
      await scrollTo(tester, find.text('共 83 个群聊'));
      expect(find.text('共 83 个群聊').hitTestable(), findsOneWidget);
      await tester.tap(
          find.descendant(of: find.byType(IndexBar), matching: find.text('Z')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('self-z')));
      expect(selected?.groupID, 'self-z');
      await scrollTo(tester, find.byKey(const ValueKey('peer-number')));
      await tester.tap(find.byKey(const ValueKey('peer-number')));
      expect(selected?.groupID, 'peer-number');
      logic.iCreatedList.clear();
      logic.iJoinedList.assignAll([selected!]);
      await tester.pumpAndSettle();
      await scrollTo(tester, find.byKey(const ValueKey('peer-number')),
          delta: -500);
      expect(find.byKey(const ValueKey('peer-number')).hitTestable(),
          findsOneWidget);
      expect(find.text('共 1 个群聊').hitTestable(), findsOneWidget);
      logic.iJoinedList.clear();
      await tester.pumpAndSettle();
      expect(find.text('共 0 个群聊').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '${brightness.name} group picker keeps SDK order and selection while scrolling and searching',
        (tester) async {
      final fixture = FriendPickerPresenceFixture(action: SelAction.forward);
      await fixture.open(tester,
          brightness: brightness, width: 320, textScale: 2);
      final data = samples();
      final logic = Get.put(SelectContactsFromGroupLogic(
          selection: fixture.selection, loadGroups: () async => data));
      fixture.navigator.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => SelectContactsFromGroupPage(
              logic: logic, selection: fixture.selection)));
      await tester.pumpAndSettle();
      expect(find.byType(IndexBar), findsNothing);
      expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('select-group-self-a0')))
              .dy,
          lessThan(tester
              .getTopLeft(find.byKey(const ValueKey('select-group-self-a1')))
              .dy));
      await scrollTo(tester, find.byKey(const ValueKey('select-group-self-z')));
      await tester.tap(find.byKey(const ValueKey('select-group-self-z')));
      await tester.pumpAndSettle();
      expect(fixture.selection.checkedList['self-z'], same(data[40]));
      await scrollTo(tester, find.byKey(const ValueKey('select-group-self-a0')),
          delta: -500);
      await tester.tap(find.byKey(const ValueKey('select-group-self-a0')));
      await tester.pumpAndSettle();
      expect(fixture.selection.checkedList.keys.toSet(), {'self-z', 'self-a0'});
      await tester.enterText(find.byType(TextField), '张三');
      await tester.pumpAndSettle();
      expect(logic.visibleGroups.single, same(data[40]));
      await tester.tap(find.byKey(const ValueKey('select-group-self-z')));
      await tester.pumpAndSettle();
      expect(fixture.selection.checkedList.keys, ['self-a0']);
      expect(tester.takeException(), isNull);
    });

    for (final picker in [false, true]) {
      testWidgets('export ${brightness.name} plain group list picker=$picker',
          skip: previewDirectory.isEmpty, (tester) async {
        final fixture = FriendPickerPresenceFixture(action: SelAction.forward);
        await fixture.open(tester,
            brightness: brightness, fontFamily: 'GroupListPreview');
        final groups = [
          for (final name in [
            '阿林项目群',
            '北京同事群',
            '京东上下分群',
            '京东统计群',
            '机器人测试群',
            '内部群',
            '张三的群',
            '999群'
          ])
            GroupInfo(
                groupID: name,
                groupName: name,
                memberCount: 19,
                ownerUserID: 'self'),
        ];
        final boundary = GlobalKey();
        final Widget page;
        if (picker) {
          final logic = Get.put(SelectContactsFromGroupLogic(
              selection: fixture.selection, loadGroups: () async => groups));
          page = SelectContactsFromGroupPage(
              logic: logic, selection: fixture.selection);
        } else {
          final logic = Get.put(_Directory(groups));
          page = GroupListPage(logic: logic, onSelected: (_) {});
        }
        fixture.navigator.currentState!.push(MaterialPageRoute<void>(
            builder: (_) => RepaintBoundary(key: boundary, child: page)));
        await tester.pumpAndSettle();
        if (!picker) {
          await scrollTo(tester, find.text('共 8 个群聊'));
          expect(find.text('共 8 个群聊').hitTestable(), findsOneWidget);
        }
        final images = tester.widgetList<Image>(find.byType(Image)).toList();
        await tester.runAsync(() async {
          for (final image in images) {
            await precacheImage(image.image, boundary.currentContext!);
          }
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final render = boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        await tester.runAsync(() async {
          await Directory(previewDirectory).create(recursive: true);
          final image = await render.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
                  '$previewDirectory/${picker ? 'group-picker' : 'my-groups'}-${brightness.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      });
    }
  }
}
