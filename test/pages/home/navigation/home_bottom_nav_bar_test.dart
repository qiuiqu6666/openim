import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/home/navigation/glass_bottom_nav_bar.dart';
import 'package:openim/pages/home/navigation/home_bottom_nav_bar.dart';
import 'package:openim_common/openim_common.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

void platformTest(String description, WidgetTesterCallback callback,
        {TargetPlatform platform = TargetPlatform.iOS}) =>
    testWidgets(description, callback,
        variant: TargetPlatformVariant.only(platform));

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const capability = MethodChannel('openim/home-navigation');
  final updates = <Map<Object?, Object?>>[];
  final views = <int>[];
  var available = true;
  var failUpdate = false;
  var selected = 0;
  var badges = [8, 0, 128, 0, 0];
  var brightness = Brightness.light;
  var title = 'Messages';
  late StateSetter rebuild;

  Future<void> emitSelection(int index, {int? viewId}) async {
    final result = Completer<void>();
    binding.defaultBinaryMessenger.handlePlatformMessage(
      'openim/home-navigation/${viewId ?? views.last}',
      const StandardMethodCodec().encodeMethodCall(MethodCall('select', index)),
      (_) => result.complete(),
    );
    await result.future;
  }

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            bottomNavigationBar: HomeBottomNavBar(
              config: NavBarConfig(
                selectedIndex: selected,
                items: [
                  ItemConfig(icon: const Icon(Icons.chat), title: title),
                  ItemConfig(icon: const Icon(Icons.group), title: 'Groups'),
                  ItemConfig(
                      icon: const Icon(Icons.contacts), title: 'Contacts'),
                  ItemConfig(icon: const Icon(Icons.wallet), title: 'Wallet'),
                  ItemConfig(icon: const Icon(Icons.person), title: 'Me'),
                ],
                onItemSelected: (_) =>
                    fail('Native bar bypassed entry callback'),
              ),
              unreadCounts: badges,
              // Simulate an entry guard which declines the wallet destination.
              onItemSelected: (index) {
                if (index != 3) setState(() => selected = index);
              },
            ),
          ),
        );
      }),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    NavigationGlassController.instance.load();
    updates.clear();
    views.clear();
    available = true;
    failUpdate = false;
    selected = 0;
    badges = [8, 0, 128, 0, 0];
    brightness = Brightness.light;
    title = 'Messages';
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(capability, (call) async => available);
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
      if (call.method == 'create') {
        final args = call.arguments as Map;
        final id = args['id'] as int;
        views.add(id);
        binding.defaultBinaryMessenger.setMockMethodCallHandler(
            MethodChannel('openim/home-navigation/$id'), (call) async {
          if (failUpdate) throw PlatformException(code: 'missing-tab-icon');
          updates.add(Map<Object?, Object?>.from(call.arguments as Map));
          return null;
        });
      }
      return null;
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(capability, null);
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final id in views) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
          MethodChannel('openim/home-navigation/$id'), null);
    }
  });

  platformTest(
      'keyboard removes native navigation and restores selection and badges',
      (tester) async {
    addTearDown(tester.view.reset);
    await pumpHost(tester);
    await emitSelection(1);
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(find.byType(UiKitView), findsNothing);
    expect(find.byType(GlassBottomNavBar), findsNothing);
    rebuild(() => badges = [0, 27, 0, 0, 0]);
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    expect(find.byType(UiKitView), findsOneWidget);
    expect(updates.last['selectedIndex'], 1);
    expect(((updates.last['items'] as List)[1] as Map)['badge'], '27');
  });

  platformTest('keyboard also hides and restores the Flutter navigation',
      (tester) async {
    addTearDown(tester.view.reset);
    await pumpHost(tester);
    expect(find.byType(GlassBottomNavBar), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(find.byType(GlassBottomNavBar), findsNothing);
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    expect(find.byType(GlassBottomNavBar), findsOneWidget);
  }, platform: TargetPlatform.android);

  platformTest(
      'native updates badges, theme, labels and authoritative selection',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    await pumpHost(tester);
    expect(find.byType(UiKitView), findsOneWidget);
    expect(tester.getSize(find.byType(UiKitView)).height, 98);
    final items = updates.last['items'] as List;
    expect(updates.last['accent'], AppTokens.accent.toARGB32());
    expect(updates.last['inactive'],
        AppTokens.textSecondary(dark: false).toARGB32());
    expect((items[0] as Map)['badge'], '8');
    expect((items[2] as Map)['badge'], '99+');
    expect((items[0] as Map)['icon'], contains('packages/openim_common/'));
    expect((items[3] as Map)['icon'], 'assets/wallet.png');
    await emitSelection(3);
    await tester.pumpAndSettle();
    expect(selected, 0);
    await emitSelection(1);
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(updates.last['selectedIndex'], 1);
    await emitSelection(-1);
    await emitSelection(99);
    expect(selected, 1);

    rebuild(() {
      selected = 4; // Programmatic navigation, e.g. notification/deep link.
      badges = [0, 22, 0, 0, 0];
      brightness = Brightness.dark;
      title = '消息';
    });
    await tester.pumpAndSettle();
    expect(views.length, 1); // Reuse the native view for state updates.
    expect(updates.last['dark'], true);
    expect(updates.last['inactive'],
        AppTokens.textSecondary(dark: true).toARGB32());
    expect(updates.last['selectedIndex'], 4);
    final updatedItems = updates.last['items'] as List;
    expect((updatedItems[0] as Map)['badge'], '');
    expect((updatedItems[1] as Map)['badge'], '22');
    expect((updatedItems[0] as Map)['title'], '消息');
    final oldView = views.last;
    await tester.pumpWidget(const SizedBox.shrink());
    await emitSelection(2, viewId: oldView);
    expect(selected, 4); // Disposed bar cannot act on a stale callback.
    expect(tester.takeException(), isNull);
  });

  platformTest('older iOS falls back', (tester) async {
    available = false;
    await pumpHost(tester);
    expect(find.byType(GlassBottomNavBar), findsOneWidget);
    expect(views, isEmpty);
  });

  platformTest('missing native registration falls back', (tester) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(capability, null);
    await pumpHost(tester);
    expect(find.byType(GlassBottomNavBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  platformTest('Android never requests a native view', (tester) async {
    await pumpHost(tester);
    expect(find.byType(GlassBottomNavBar), findsOneWidget);
    expect(views, isEmpty);
  }, platform: TargetPlatform.android);

  platformTest('native update failure restores functional Flutter navigation',
      (tester) async {
    failUpdate = true;
    await pumpHost(tester);
    expect(find.byType(GlassBottomNavBar), findsOneWidget);
    await tester.tap(find.text('Contacts'));
    await tester.pumpAndSettle();
    expect(selected, 2);
    expect(tester.takeException(), isNull);
  });

  platformTest('explicit translucent preference retains Flutter renderer',
      (tester) async {
    await NavigationGlassController.instance
        .setMode(NavigationGlassMode.translucent);
    await pumpHost(tester);
    expect(find.byType(GlassBottomNavBar), findsOneWidget);
    expect(views, isEmpty);
  });
}
