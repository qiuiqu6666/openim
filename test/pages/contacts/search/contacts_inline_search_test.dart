import 'package:azlistview/azlistview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/contacts_view.dart';
import 'package:openim/pages/contacts/navigation/contacts_header.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'support/contacts_inline_fixture.dart';

class _Routes extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

final _entry = find.byKey(const ValueKey('contacts-search-button'));
final _input = find.byKey(const ValueKey('chat-history-search-input'));
final _cancel = find.byKey(const ValueKey('chat-history-search-cancel'));

Future<InlineContactsFixture> _mount(
  WidgetTester tester, {
  required Brightness brightness,
  required _Routes routes,
  required List<bool> modes,
  double scale = 1,
  bool reducedMotion = false,
}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Styles.isDark = brightness == Brightness.dark;
  final logic = InlineContactsFixture(count: scale == 1 ? 50 : 0);
  addTearDown(() => logic.onDelete());
  Get.put<InlineContactsFixture>(logic);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      navigatorObservers: [routes],
      theme: ThemeData(brightness: brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.only(top: 24, bottom: 34),
          textScaler: TextScaler.linear(scale),
          disableAnimations: reducedMotion,
        ),
        child: child!,
      ),
      home: ContactsPage(logic: logic, onSearchModeChanged: modes.add),
    ),
  ));
  await tester.pumpAndSettle();
  return logic;
}

void main() {
  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });
  tearDown(() {
    Styles.isDark = false;
    VisibilityDetectorController.instance.updateInterval =
        const Duration(milliseconds: 500);
    Get.reset();
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'contacts moves one input both ways and preserves scroll: $brightness',
        (tester) async {
      final modes = <bool>[];
      final routes = _Routes();
      final logic = await _mount(tester,
          brightness: brightness, routes: routes, modes: modes);
      final scrollFinder = find
          .descendant(
              of: find.byType(AzListView), matching: find.byType(Scrollable))
          .first;
      await tester.drag(scrollFinder, const Offset(0, -500));
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(scrollFinder);
      final offset = scroll.position.pixels;
      expect(offset, greaterThan(0));
      final origin = tester.getRect(_entry);
      final inputState = tester.state(_input);
      final pushes = routes.pushes;
      await tester.tapAt(Offset(origin.right - 8, origin.center.dy));
      await tester.pump();
      expect(tester.getRect(_entry), origin);
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.getRect(_entry).top, lessThan(origin.top));
      expect(tester.getRect(_entry).width, lessThan(origin.width));
      expect(tester.state(_input), same(inputState));
      await tester.pumpAndSettle();
      expect(find.byType(ContactsHeader), findsNothing);
      expect(tester.getRect(_entry).top, closeTo(32, 1));
      expect(tester.widget<TextField>(_input).focusNode!.hasFocus, isTrue);
      expect(routes.pushes, pushes);
      expect(logic.legacySearches, 0);
      final expanded = tester.getRect(_entry);
      await tester.tap(_cancel);
      await tester.pump();
      expect(tester.getRect(_entry), expanded);
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.getRect(_entry).top,
          inExclusiveRange(expanded.top, origin.top));
      expect(tester.getRect(_entry).width,
          inExclusiveRange(expanded.width, origin.width));
      await tester.pumpAndSettle();
      expect(tester.getRect(_entry), origin);
      expect(tester.state(_input), same(inputState));
      expect(tester.widget<TextField>(_input).readOnly, isTrue);
      expect(scroll.position.pixels, closeTo(offset, 1));
      expect(find.byType(ContactsHeader), findsOneWidget);
      expect(modes, [true, false]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      logic.presence.dispose();
      logic.stars.dispose();
    });

    testWidgets(
        'contacts large header and reduced motion return correctly: $brightness',
        (tester) async {
      final modes = <bool>[];
      final routes = _Routes();
      final logic = await _mount(tester,
          brightness: brightness,
          routes: routes,
          modes: modes,
          scale: 2,
          reducedMotion: true);
      final height = tester
          .widget<ContactsHeader>(find.byType(ContactsHeader))
          .toolbarHeight;
      expect(height, greaterThan(kToolbarHeight));
      final origin = tester.getRect(_entry);
      expect(origin.top, closeTo(24 + height + 8, 1));
      final inputState = tester.state(_input);
      await tester.tap(_entry);
      await tester.pump();
      expect(tester.getRect(_entry).top, closeTo(32, 1));
      await tester.pumpAndSettle();
      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).first);
      await navigator.maybePop();
      await tester.pumpAndSettle();
      expect(tester.getRect(_entry), origin);
      expect(tester.state(_input), same(inputState));
      expect(tester.widget<TextField>(_input).readOnly, isTrue);
      expect(modes, [true, false]);
      expect(routes.pushes, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      logic.presence.dispose();
      logic.stars.dispose();
    });
  }
}
