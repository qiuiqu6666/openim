import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_entry_scope.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_panel.dart';
import 'package:openim/pages/mine/settings/widgets/settings_widgets.dart'
    show SettingsGroup;

void main() {
  for (final dark in [false, true]) {
    testWidgets('unbound services remain visible and fit 320px dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var retries = 0;
      final capture = GlobalKey();
      final export = Platform.environment['PROFILE_SERVICES_CAPTURE'] == '1';
      if (export) {
        await tester.runAsync(() async {
          final bytes = ByteData.sublistView(
              await File('C:/Windows/Fonts/msyh.ttc').readAsBytes());
          await (FontLoader('ProfileServicesCjk')..addFont(Future.value(bytes)))
              .load();
        });
      }
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
              fontFamily: export ? 'ProfileServicesCjk' : null),
          home: Scaffold(
              body: RepaintBoundary(
                  key: capture,
                  child: SangongProfileEntryScope(
                      userID: 'target',
                      groups: [
                        GroupInfo.fromJson({
                          'groupID': 'normal-group',
                          'groupName': '很长的普通群名称，没有旧三公配置也要展示服务入口'
                        })
                      ],
                      selectedGroupID: 'normal-group',
                      loading: false,
                      error: '该群暂无三公运营权限，请联系群内负责人确认后重试。',
                      onRetry: () => retries++,
                      onSelectGroup: (_) {},
                      child: const SingleChildScrollView(
                          child: Column(children: [
                        Text('详细资料'),
                        SangongInlineProfilePanel(userID: 'target'),
                        Text('普通资料继续使用'),
                      ])))))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sangong-profile-services')),
          findsOneWidget);
      expect(find.byType(SettingsGroup), findsNothing);
      expect(find.text('三公服务'), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.byType(TextField), findsNWidgets(3));
      for (final field
          in tester.widgetList<TextField>(find.byType(TextField))) {
        expect(field.enabled, isFalse);
        expect(field.textAlign, TextAlign.right);
      }
      expect(find.text('当前积分 —'), findsOneWidget);
      expect(find.text('取消合庄'), findsOneWidget);
      for (final action in ['上分', '下分', '定庄', '限额', '设置', '取消合庄', '发送']) {
        for (final ink in tester.widgetList<InkWell>(find.ancestor(
            of: find.text(action), matching: find.byType(InkWell)))) {
          expect(ink.onTap, isNull);
        }
      }
      await tester.tap(find.text('重试'));
      expect(retries, 1);
      expect(find.text('普通资料继续使用'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (Platform.environment['PROFILE_SERVICES_CAPTURE'] == '1') {
        final boundary =
            capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final pixels = await boundary.toImage();
          final bytes = await pixels.toByteData(format: ui.ImageByteFormat.png);
          await File('.temp/profile-services-${dark ? 'dark' : 'light'}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          pixels.dispose();
        });
      }
    });
  }
}
