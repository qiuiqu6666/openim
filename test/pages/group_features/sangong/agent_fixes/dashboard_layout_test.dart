import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_dashboard_page.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import '../sangong_test_support.dart';

void main() {
  for (final dark in [false, true]) {
    for (final width in [320.0, 375.0, 512.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('dashboard filters width=$width dark=$dark scale=$scale',
            (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final api = SangongTestApi()
            ..respond = (_) => {
                  'version': 1,
                  'nextBeforeId': 0,
                  'summary': {
                    'totalBalance': -279884,
                    'totalTurnover': 1511560,
                    'playerTurnover': 1433658,
                    'bankerTurnover': 77902,
                    'memberCount': 207,
                    'directMemberCount': 14,
                    'totalUp': 219193,
                    'totalDown': 118097,
                    'totalProfitLoss': -79306
                  },
                  'members': [
                    for (final i in [0, 2])
                      {
                        'imUserId': 'user$i',
                        'nickname': i == 0 ? '点点' : '日入三千%发财号',
                        'levelNo': i,
                        'balance': i,
                        'rebatePct': 1.8,
                        'playerTurnover': i == 0 ? 100 : 0,
                        'bankerTurnover': 0
                      }
                  ]
                };
          final runtime = SangongRuntime(sangongTestContext(api));
          addTearDown(runtime.dispose);
          addTearDown(() => unmountSangong(tester));
          final boundary = GlobalKey();
          const output = String.fromEnvironment('DASHBOARD_PREVIEW');
          if (output.isNotEmpty) {
            await tester.runAsync(() async {
              final bytes = ByteData.sublistView(
                  await File('C:/Windows/Fonts/msyh.ttc').readAsBytes());
              await (FontLoader('DashboardFont')..addFont(Future.value(bytes)))
                  .load();
              await (FontLoader('MaterialIcons')
                    ..addFont(
                        rootBundle.load('fonts/MaterialIcons-Regular.otf')))
                  .load();
            });
          }
          await pumpSangongPage(
              tester, runtime, const SangongAgentDashboardPage(),
              dark: dark,
              boundary: boundary,
              fontFamily: output.isEmpty ? null : 'DashboardFont');
          expect(tester.takeException(), isNull);
          if (output.isNotEmpty && scale == 1) {
            final render = boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await render.toImage();
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              await File('$output/dashboard-$width-$dark.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.scrollUntilVisible(find.byType(TextField), 200,
              scrollable: find.byType(Scrollable).first);
          await tester.enterText(find.byType(TextField), 'user2');
          await tester.pumpAndSettle();
          expect(find.text('余额 ¥2'), findsOneWidget);
          expect(find.text('余额 ¥0'), findsNothing);
          await tester.enterText(find.byType(TextField), '');
          await tester.tap(find.byTooltip('选择排序方式'));
          await tester.pumpAndSettle();
          await tester
              .tap(find.widgetWithText(PopupMenuItem<int>, '按总流水（从高到低）'));
          await tester.pumpAndSettle();
          expect(find.text('余额 ¥0'), findsOneWidget);
          expect(find.text('余额 ¥2'), findsOneWidget);
          expect(tester.getTopLeft(find.text('余额 ¥0')).dy,
              lessThan(tester.getTopLeft(find.text('余额 ¥2')).dy));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
