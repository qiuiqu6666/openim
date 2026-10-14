import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/server_nodes/node_availability_probe.dart';
import 'package:openim/core/server_nodes/node_endpoint.dart';
import 'package:openim/core/server_nodes/manual_node_switch_service.dart';
import 'package:openim/core/server_nodes/startup_node_selection.dart';
import 'package:openim/pages/mine/settings/pages/node_switch_page.dart';
import 'package:openim/pages/mine/settings/node_switch/node_probe_controller.dart';
import 'package:openim/pages/mine/settings/settings_draft_store.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putServerConfig({
      'authUrl': NodeEndpoint.direct.chatApi,
      'apiUrl': NodeEndpoint.direct.imApi,
      'wsUrl': NodeEndpoint.direct.imWs,
    });
    StartupNodeSelection.last = NodeSelection(NodeEndpoint.direct, [
      const NodeAvailability(NodeEndpoint.direct,
          available: true, latencyMs: 80),
    ]);
  });
  tearDown(() => StartupNodeSelection.last = null);
  for (final dark in [false, true]) {
    for (final size in [const Size(320, 700), const Size(700, 320)]) {
      for (final scale in [1.0, 1.6]) {
        testWidgets('node selection dark=$dark size=$size scale=$scale',
            (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final store = SettingsDraftStore();
          addTearDown(store.dispose);
          var active = NodeEndpoint.direct;
          var connections = 0;
          var preparations = 0;
          var probes = 0;
          final controller = NodeProbeController(
            readEndpoint: () => active,
            switchService: ManualNodeSwitchService(
              readEndpoint: () => active,
              readSession: () => 'user',
              canSwitch: () => true,
              prepareTarget: (_) async {
                preparations++;
              },
              probe: (node) async {
                probes++;
                return NodeAvailability(node, available: true, latencyMs: 10);
              },
              connect: (node, _) async {
                connections++;
                active = node;
              },
            ),
          );
          controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
          addTearDown(controller.dispose);
          await tester.pumpWidget(ScreenUtilInit(
            designSize: const Size(375, 812),
            builder: (_, __) => MaterialApp(
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [Locale('zh', 'CN')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light),
              builder: (context, child) => EasyLoading.init()(
                  context,
                  MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                          textScaler: TextScaler.linear(scale),
                          disableAnimations: true),
                      child: child!)),
              home: NodeSwitchPage(
                  controller: controller,
                  store: store,
                  service: const StubSettingsService()),
            ),
          ));
          expect(find.text('节点01'), findsOneWidget);
          expect(find.text('节点02'), findsOneWidget);
          expect(find.text('节点03'), findsOneWidget);
          expect(find.text('异常'), findsNothing);
          expect(find.text('正常 (80ms)'), findsOneWidget);
          expect(find.byIcon(Icons.check_rounded), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (size.height > size.width && scale == 1.0) {
            await tester.tap(find.text('节点01'));
            await tester.pump();
            expect(find.text('切换中'), findsNothing);
            expect(active, NodeEndpoint.direct);
            await tester.tap(find.text('节点01'));
            await tester.pump();
            expect(connections, 0);
            await tester.pumpAndSettle();
            expect(active, NodeEndpoint.direct);
            expect(
                find.descendant(
                    of: find.byKey(const ValueKey('node-row-0')),
                    matching: find.byIcon(Icons.check_rounded)),
                findsOneWidget);
            await tester.pump(const Duration(seconds: 3));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.tap(find.text('节点03'));
            await tester.pumpAndSettle();
            final notice = find.text('该节点仅在其他节点不可用时切换');
            expect(notice, findsOneWidget);
            expect(tester.getCenter(notice).dx, closeTo(size.width / 2, 1));
            expect(tester.getCenter(notice).dy, closeTo(size.height / 2, 1));
            expect(connections, 0);
            expect(preparations, 0);
            expect(probes, 0);
            expect(active, NodeEndpoint.direct);
            expect(find.text('切换中'), findsNothing);
            expect(find.byKey(const ValueKey('node-notice-2')), findsNothing);
            expect(
                find.descendant(
                    of: find.byKey(const ValueKey('node-row-0')),
                    matching: find.byIcon(Icons.check_rounded)),
                findsOneWidget);
            await tester.pump(const Duration(seconds: 3));
            await tester.pumpAndSettle();
            expect(notice, findsNothing);
            await tester.tap(find.text('节点02'));
            await tester.pumpAndSettle();
            expect(active, NodeEndpoint.backup);
            expect(connections, 1);
          }
        });
      }
    }
  }
}
