import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/home/glass_bottom_nav_bar.dart';
import 'package:openim_common/openim_common.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
  });

  Future<void> mount(WidgetTester tester,
      {required ValueChanged<int> configSelect,
      ValueChanged<int>? intercept}) async {
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
        home: Scaffold(
          bottomNavigationBar: GlassBottomNavBar(
            config: NavBarConfig(
              items: [
                ItemConfig(icon: const Icon(Icons.chat), title: 'Messages'),
                ItemConfig(
                    icon: const Icon(Icons.account_balance_wallet),
                    title: 'Wallet'),
              ],
              selectedIndex: 0,
              onItemSelected: configSelect,
            ),
            onItemSelected: intercept,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('wallet navigation interceptor owns selection before tab change',
      (tester) async {
    final configCalls = <int>[];
    final intercepted = <int>[];
    await mount(tester,
        configSelect: configCalls.add, intercept: intercepted.add);
    await tester.tap(find.text('Wallet'));
    await tester.pumpAndSettle();
    expect(intercepted, [1]);
    expect(configCalls, isEmpty);
    expect(
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .currentIndex,
      0,
      reason: 'The gate can keep the existing tab while awaiting status.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a navigation bar without interception preserves its callback',
      (tester) async {
    final configCalls = <int>[];
    await mount(tester, configSelect: configCalls.add);
    await tester.tap(find.text('Wallet'));
    await tester.pumpAndSettle();
    expect(configCalls, [1]);
    expect(tester.takeException(), isNull);
  });
}
