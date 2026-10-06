import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:permission_handler/permission_handler.dart';

import 'support/toolbox_fixture.dart';

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  testWidgets('each original capability delegates its callback across pages',
      (tester) async {
    final native = ToolboxPermissions()..install();
    addTearDown(native.uninstall);
    final fixture = ToolboxFixture();
    await mountToolbox(tester, fixture.full());
    for (final id in [
      'album',
      'camera',
      'favorites',
      'call',
      'card',
      'file',
      'red-packet',
      'transfer',
      'record',
      'audio',
      'location',
      'formatted-text',
      'emoji',
    ]) {
      await reachToolboxAction(tester, id);
      await tester.tap(toolboxAction(id));
      await tester.pumpAndSettle();
      expect(fixture.calls[id], 1, reason: '$id delegates exactly once');
    }
    expect(fixture.calls.length, 13);
    expect(
        native.requests.expand((request) => request),
        containsAll([
          Permission.camera.value,
          Permission.microphone.value,
          Permission.photos.value
        ]));
    expect(tester.takeException(), isNull);
  });

  testWidgets('media and call callbacks wait for permission then remain usable',
      (tester) async {
    final native = ToolboxPermissions()..install();
    addTearDown(native.uninstall);
    final fixture = ToolboxFixture();
    await mountToolbox(tester, fixture.full());
    for (final id in ['album', 'camera', 'call']) {
      native.status = 0;
      await reachToolboxAction(tester, id);
      await tester.tap(toolboxAction(id));
      await tester.pumpAndSettle();
      expect(fixture.calls[id], isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, StrRes.cancel));
      await tester.pumpAndSettle();
      native.status = 1;
      await tester.tap(toolboxAction(id));
      await tester.pumpAndSettle();
      expect(fixture.calls[id], 1);
      expect(find.byType(AlertDialog), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('group tools preserve extra actions and omit one-to-one calling',
      (tester) async {
    final fixture = ToolboxFixture();
    await mountToolbox(
        tester,
        fixture.full(group: true, extras: [
          ToolboxItemInfo(
              text: '群直播',
              icon: '',
              symbol: Icons.live_tv,
              onTap: fixture.action('live')),
          ToolboxItemInfo(
              text: '群公告',
              icon: '',
              symbol: Icons.campaign_outlined,
              onTap: fixture.action('announcement')),
        ]));
    expect(toolboxAction('call'), findsNothing);
    expect(
        find.byTooltip(StrRes.fundGroupTransfer).hitTestable(), findsOneWidget);
    expect(find.byTooltip('群直播').hitTestable(), findsOneWidget);
    expect(find.byTooltip('群公告').hitTestable(), findsNothing);
    await tester.tap(find.byTooltip('群直播'));
    await tester.tap(find.byTooltip(StrRes.fundGroupTransfer));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('群公告'));
    expect(fixture.calls, {'live': 1, 'transfer': 1, 'announcement': 1});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'shrinking available tools from a later page exposes remaining actions',
      (tester) async {
    var taps = 0;
    final extras = ValueNotifier(List.generate(
        16,
        (index) => ToolboxItemInfo(
            text: '扩展 $index',
            icon: '',
            symbol: Icons.extension,
            onTap: () => taps++)));
    addTearDown(extras.dispose);
    await mountToolbox(
        tester,
        ValueListenableBuilder<List<ToolboxItemInfo>>(
          valueListenable: extras,
          builder: (_, items, __) => ChatToolBox(
            extraItems: items,
            onTapFavorites: () => taps++,
          ),
        ));
    for (var page = 0; page < 2; page++) {
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('扩展 15'));
    expect(taps, 1);
    extras.value = [];
    await tester.pumpAndSettle();
    expect(find.byTooltip(StrRes.favoriteCollection).hitTestable(),
        findsOneWidget);
    await tester.tap(find.byTooltip(StrRes.favoriteCollection));
    expect(taps, 2);
    expect(tester.takeException(), isNull);
  });
}
