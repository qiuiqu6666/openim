import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/server_nodes/node_availability_probe.dart';
import 'package:openim/core/server_nodes/node_endpoint.dart';
import 'package:openim/core/server_nodes/startup_node_selection.dart';
import 'package:openim/pages/mine/settings/pages/node_switch_page.dart';
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
      const NodeAvailability(NodeEndpoint.primary,
          available: false, latencyMs: 3000),
      const NodeAvailability(NodeEndpoint.direct,
          available: true, latencyMs: 80),
    ]);
  });
  tearDown(() => StartupNodeSelection.last = null);
  for (final dark in [false, true]) {
    for (final size in [const Size(320, 700), const Size(700, 320)]) {
      for (final scale in [1.0, 1.6]) {
        testWidgets('selected fallback dark=$dark size=$size scale=$scale',
            (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final store = SettingsDraftStore();
          addTearDown(store.dispose);
          await tester.pumpWidget(ScreenUtilInit(
            designSize: const Size(375, 812),
            builder: (_, __) => MaterialApp(
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [Locale('zh', 'CN')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scale),
                      disableAnimations: true),
                  child: child!),
              home: NodeSwitchPage(
                  store: store, service: const StubSettingsService()),
            ),
          ));
          expect(find.text('节点01'), findsOneWidget);
          expect(find.text('节点02'), findsOneWidget);
          expect(find.text('异常'), findsOneWidget);
          expect(find.text('正常 (80ms)'), findsOneWidget);
          expect(find.byIcon(Icons.check_rounded), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
