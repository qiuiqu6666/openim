import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_team_page.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import '../sangong_test_support.dart';

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('team layout and search, dark=$dark scale=$scale',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 740);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = SangongTestApi()
          ..respond = (_) => {
                'version': 1,
                'nextBeforeId': 0,
                'agent': {'balance': 100},
                'session': {
                  'businessDate': '2026-10-20',
                  'batchNo': '2026102001'
                },
                'members': [
                  {
                    'imUserId': 'winter',
                    'nickname': '冬天的一个很长很长的用户昵称',
                    'levelNo': 1,
                    'balance': 12345678.90,
                    'pendingRebate': 12,
                    'playerTurnover': 9396,
                    'bankerTurnover': 0
                  },
                  {
                    'imUserId': 'summer',
                    'nickname': '源源不断',
                    'levelNo': 2,
                    'balance': 16,
                    'pendingRebate': 0
                  },
                ]
              };
        final runtime = SangongRuntime(sangongTestContext(api));
        addTearDown(runtime.dispose);
        addTearDown(() => unmountSangong(tester));
        const output = String.fromEnvironment('TEAM_PREVIEW');
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final bytes = ByteData.sublistView(
                await File('C:/Windows/Fonts/msyh.ttc').readAsBytes());
            await (FontLoader('MaterialIcons')
                  ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
                .load();
            await (FontLoader('TeamPreview')..addFont(Future.value(bytes)))
                .load();
          });
        }
        final boundary = GlobalKey();
        await pumpSangongPage(
            tester,
            runtime,
            Builder(
                builder: (context) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: const SangongAgentTeamPage())),
            dark: dark,
            boundary: boundary,
            fontFamily: output.isEmpty ? null : 'TeamPreview');
        expect(tester.takeException(), isNull);
        expect(find.text('全部下级'), findsNothing);
        expect(find.textContaining('批次'), findsNothing);
        final requestsBeforeSort = api.calls.length;
        await tester.tap(find.text('积分排序 ↓'));
        await tester.pump();
        expect(find.text('积分排序 ↑'), findsOneWidget);
        final names = find.byWidgetPredicate((w) =>
            w is Text && (w.data == '源源不断' || w.data == '冬天的一个很长很长的用户昵称'));
        expect(tester.widget<Text>(names.first).data, '源源不断');
        await tester.tap(find.text('总流水排序'));
        await tester.pump();
        expect(find.text('总流水排序 ↓'), findsOneWidget);
        expect(tester.widget<Text>(names.first).data, '冬天的一个很长很长的用户昵称');
        await tester.tap(find.text('层级排序'));
        await tester.pump();
        expect(find.text('层级排序 ↑'), findsOneWidget);
        expect(tester.widget<Text>(names.first).data, '冬天的一个很长很长的用户昵称');
        await tester.tap(find.text('层级排序 ↑'));
        await tester.pump();
        expect(find.text('层级排序 ↓'), findsOneWidget);
        expect(tester.widget<Text>(names.first).data, '源源不断');
        expect(api.calls.length, requestsBeforeSort);

        await tester.scrollUntilVisible(find.text('划转').first, 100,
            scrollable: find.byType(Scrollable).first);
        expect(tester.takeException(), isNull);
        final button = find.byTooltip('划转积分').first;
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        if (output.isNotEmpty && scale == 1) {
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await File('$output/team-${dark ? 'dark' : 'light'}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.scrollUntilVisible(find.byType(TextField), -200,
            scrollable: find.byType(Scrollable).first);
        await tester.enterText(find.byType(TextField), '不存在的用户');
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('未找到匹配的下级'), findsOneWidget);
        await tester.ensureVisible(find.byTooltip('清空搜索'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('清空搜索'));
        await tester.pump();
        expect(find.text('共 2 人'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
