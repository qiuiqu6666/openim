import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/widgets/settings_widgets.dart';
import 'package:openim/pages/mine/widgets/mine_profile_view.dart';
import 'package:openim_common/openim_common.dart';

const _size = Size(375, 600);
const _firstRow = ValueKey('first-settings-row');
const _toolbarAction = ValueKey('settings-toolbar-action');

Future<void> _pumpPage(
  WidgetTester tester, {
  required Widget page,
  required Brightness brightness,
  required double topInset,
}) async {
  tester.view.physicalSize = _size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final previousDark = Styles.isDark;
  Styles.isDark = brightness == Brightness.dark;
  addTearDown(() => Styles.isDark = previousDark);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
      theme: ThemeData(brightness: brightness),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MediaQuery(
        data: MediaQueryData(
          size: _size,
          padding: EdgeInsets.only(top: topInset, bottom: 24),
          viewPadding: EdgeInsets.only(top: topInset, bottom: 24),
        ),
        child: page,
      ),
    ),
  ));
  // Mine's ecosystem cards animate continuously; settling would never finish.
  await tester.pump(const Duration(milliseconds: 100));
}

List<Widget> _settingsRows(VoidCallback onFirstTap) => [
      for (var index = 0; index < 20; index++)
        SettingsGroup(children: [
          SettingsCell(
            key: index == 0 ? _firstRow : ValueKey('settings-row-$index'),
            title: '设置项目 $index',
            showDivider: false,
            onTap: index == 0 ? onFirstTap : () {},
          ),
        ]),
    ];

void main() {
  for (final brightness in Brightness.values) {
    for (final topInset in [24.0, 44.0]) {
      final variant = '${brightness.name}, status inset $topInset';

      testWidgets('mine content clears and scrolls behind glass ($variant)',
          (tester) async {
        var profileTaps = 0;
        var favoritesTaps = 0;
        var settingsTaps = 0;
        await _pumpPage(
          tester,
          brightness: brightness,
          topInset: topInset,
          page: MineProfileView(
            nickname: '本地测试用户',
            userId: 'test-user',
            avatarUrl: '',
            signature: '测试签名',
            onProfileTap: () => profileTaps++,
            onQrTap: () {},
            onFavoritesTap: () => favoritesTaps++,
            onCallsTap: () {},
            onNotificationsTap: () {},
            onShareAppTap: () {},
            onSettingsTap: () => settingsTaps++,
            onFeatureTap: (_) {},
            onUnavailableFeatureTap: (_) {},
          ),
        );

        final appBar = find.byKey(const ValueKey('mine-main-appbar'));
        final profile = find.byKey(const ValueKey('mine-profile-header'));
        final header = tester.getRect(appBar);
        expect(header.bottom, closeTo(topInset + kToolbarHeight, .01));
        expect(tester.getRect(profile).top, closeTo(header.bottom, .01));
        expect(find.byType(BackdropFilter), findsOneWidget);
        await tester.tap(profile);
        expect(profileTaps, 1);

        final scroll = tester.state<ScrollableState>(find.descendant(
          of: find.byKey(const PageStorageKey<String>('mine-profile-scroll')),
          matching: find.byType(Scrollable),
        ));
        const offset = 100.0;
        expect(scroll.position.maxScrollExtent, greaterThan(offset));
        scroll.position.jumpTo(offset);
        await tester.pump();
        expect(tester.getRect(profile).top, lessThan(header.bottom));
        expect(tester.getRect(profile).bottom, greaterThan(header.top));
        expect(tester.getRect(appBar), header);

        await tester.tap(find.byKey(const ValueKey('mine-top-settings')));
        await tester.pump();
        expect(settingsTaps, 1);
        expect(profileTaps, 1,
            reason: 'toolbar taps must not reach the profile');
        await tester.tap(find.byKey(const ValueKey('mine-menu-favorites')));
        await tester.pump();
        expect(favoritesTaps, 1);
        expect(scroll.position.pixels, offset);
        expect(tester.takeException(), isNull);
      });

      testWidgets('settings retain gap and scroll beneath glass ($variant)',
          (tester) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        var rowTaps = 0;
        var actionTaps = 0;
        await _pumpPage(
          tester,
          brightness: brightness,
          topInset: topInset,
          page: SettingsScaffold(
            title: '设置',
            scrollController: controller,
            actions: [
              IconButton(
                key: _toolbarAction,
                onPressed: () => actionTaps++,
                icon: const Icon(Icons.done),
              ),
            ],
            children: _settingsRows(() => rowTaps++),
          ),
        );

        final appBar = find.byType(GlassAppBar);
        final header = tester.getRect(appBar);
        expect(header.bottom, closeTo(topInset + kToolbarHeight, .01));
        expect(tester.getRect(find.byKey(_firstRow)).top,
            closeTo(header.bottom + 12, .01));
        expect(find.byType(BackdropFilter), findsOneWidget);
        await tester.tap(find.byKey(_firstRow));
        expect(rowTaps, 1);

        controller.jumpTo(48);
        await tester.pump();
        final scrolledRow = tester.getRect(find.byKey(_firstRow));
        expect(scrolledRow.top, lessThan(header.bottom));
        expect(scrolledRow.bottom, greaterThan(header.bottom));
        expect(tester.getRect(appBar), header);
        await tester.tap(find.byKey(_toolbarAction));
        await tester.pump();
        expect(actionTaps, 1);
        expect(rowTaps, 1, reason: 'the glass toolbar covers the scrolled row');
        await tester.tapAt(Offset(40, header.bottom + 10));
        await tester.pump();
        expect(rowTaps, 2);
        expect(controller.offset, 48);
        expect(tester.takeException(), isNull);
      });

      testWidgets('embedded and fixed settings keep geometry ($variant)',
          (tester) async {
        await _pumpPage(
          tester,
          brightness: brightness,
          topInset: topInset,
          page: SettingsScaffold(
            title: '内嵌设置',
            embedded: true,
            children: _settingsRows(() {}),
          ),
        );
        expect(find.byType(GlassAppBar), findsNothing);
        expect(tester.getRect(find.byKey(_firstRow)).top, closeTo(12, .01));

        const fixedContent = ValueKey('fixed-settings-content');
        await _pumpPage(
          tester,
          brightness: brightness,
          topInset: topInset,
          page: const SettingsScaffold(
            title: '固定设置内容',
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(key: fixedContent, width: 100, height: 80),
            ),
            children: [],
          ),
        );
        final header = tester.getRect(find.byType(GlassAppBar));
        expect(header.bottom, closeTo(topInset + kToolbarHeight, .01));
        expect(tester.getRect(find.byKey(fixedContent)).top,
            closeTo(header.bottom, .01));
        expect(
            tester
                .widget<Scaffold>(find.byType(Scaffold))
                .extendBodyBehindAppBar,
            isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
