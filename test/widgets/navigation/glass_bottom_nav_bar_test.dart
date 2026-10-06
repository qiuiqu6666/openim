import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/home/glass_bottom_nav_bar.dart';
import 'package:openim_common/openim_common.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _badgedIcon(IconData icon, int count) => SizedBox(
      width: 32,
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(icon),
          Positioned(top: -2, right: -2, child: UnreadCountView(count: count)),
        ],
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    await NavigationGlassController.instance
        .setMode(NavigationGlassMode.translucent);
  });

  final items = [
    ItemConfig(icon: _badgedIcon(Icons.chat, 8), title: 'Messages'),
    ItemConfig(icon: const Icon(Icons.group), title: 'Groups'),
    ItemConfig(icon: _badgedIcon(Icons.contacts, 128), title: 'Contacts'),
    ItemConfig(icon: const Icon(Icons.account_balance_wallet), title: 'Wallet'),
    ItemConfig(icon: const Icon(Icons.person), title: 'Me'),
  ];

  for (final brightness in Brightness.values) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets(
          '${brightness.name} ${platform.name} glass preserves safe area and tab selection',
          (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(bottom: 34);
        addTearDown(tester.view.reset);
        var selected = 0;
        var reducedMotion = false;
        late StateSetter updateHost;
        await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => MaterialApp(
            theme: ThemeData(brightness: brightness, platform: platform),
            home: StatefulBuilder(builder: (context, setState) {
              updateHost = setState;
              return MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(disableAnimations: reducedMotion),
                child: Scaffold(
                  extendBody: true,
                  body: const ColoredBox(color: Colors.blue),
                  bottomNavigationBar: GlassBottomNavBar(
                    config: NavBarConfig(
                        items: items,
                        selectedIndex: selected,
                        onItemSelected: (index) =>
                            setState(() => selected = index)),
                  ),
                ),
              );
            }),
          ),
        ));
        await tester.pumpAndSettle();

        final surface = find.descendant(
            of: find.byType(GlassBottomNavBar),
            matching: find.byType(LiquidGlassSurface));
        expect(tester.getRect(find.byType(GlassBottomNavBar)),
            const Rect.fromLTWH(0, 722, 375, 90));
        expect(tester.getRect(surface), const Rect.fromLTWH(12, 722, 351, 56));
        final material = tester.widget<LiquidGlassSurface>(surface);
        expect(material.borderRadius, BorderRadius.circular(28));
        expect(material.opacity, brightness == Brightness.dark ? .40 : .44);
        expect(material.preferLiquid, isTrue);
        expect(tester.getRect(find.byType(BottomNavigationBar)).bottom, 778);
        expect(
            tester
                .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
                .backgroundColor,
            Colors.transparent);
        expect(
            find.descendant(of: surface, matching: find.byType(BackdropFilter)),
            findsOneWidget);
        expect(SystemChrome.latestStyle!.systemNavigationBarColor,
            Colors.transparent);
        expect(SystemChrome.latestStyle!.systemNavigationBarIconBrightness,
            brightness == Brightness.dark ? Brightness.light : Brightness.dark);

        final selection = find.byKey(const ValueKey('home-nav-selection'));
        expect(selection, findsOneWidget);
        final initialSelection = tester.getRect(selection);
        await tester.tap(find.text('Wallet'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 110));
        final movingSelection = tester.getRect(selection);
        await tester.pumpAndSettle();
        final walletSelection = tester.getRect(selection);
        expect(
            movingSelection.center.dx, greaterThan(initialSelection.center.dx));
        expect(movingSelection.center.dx, lessThan(walletSelection.center.dx));

        expect(
            tester
                .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
                .items,
            hasLength(5));
        for (final count in ['8', '99+']) {
          final badge = tester.getRect(find.text(count));
          final capsule = tester.getRect(surface);
          expect(badge.top, greaterThanOrEqualTo(capsule.top));
          expect(badge.bottom, lessThanOrEqualTo(capsule.bottom));
          expect(badge.left, greaterThanOrEqualTo(capsule.left));
          expect(badge.right, lessThanOrEqualTo(capsule.right));
        }
        for (var index = 0; index < items.length; index++) {
          await tester.tap(find.text(items[index].title!));
          await tester.pumpAndSettle();
          expect(selected, index);
          expect(
              tester
                  .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
                  .currentIndex,
              index);
        }
        updateHost(() => reducedMotion = true);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Messages'));
        await tester.pump();
        expect(tester.getRect(selection), initialSelection,
            reason: 'Reduced motion selects the destination in one frame.');
        expect(tester.getRect(surface).height, 56);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('persistent tabs keep the scroll position behind the glass bar',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
        home: PersistentTabView(
          navBarOverlap: const NavBarOverlap.full(),
          screenTransitionAnimation: const ScreenTransitionAnimation.none(),
          navBarBuilder: (config) => GlassBottomNavBar(config: config),
          tabs: [
            PersistentTabConfig(
              item: items.first,
              screen: Builder(
                  builder: (context) => Scaffold(
                        body: ListView.builder(
                          controller: scroll,
                          padding: EdgeInsets.only(
                              bottom: MediaQuery.paddingOf(context).bottom),
                          itemCount: 30,
                          itemExtent: 64,
                          itemBuilder: (_, index) => Text('Row $index'),
                        ),
                      )),
            ),
            PersistentTabConfig(
                item: items.last,
                screen: const Scaffold(body: Text('Profile'))),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final offset = scroll.offset;
    expect(tester.getRect(find.text('Row 29')).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(GlassBottomNavBar)).top));
    await tester.tap(find.text('Me').hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);
    await tester.tap(find.text('Messages').hitTestable().first);
    await tester.pumpAndSettle();
    expect(scroll.offset, offset);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
