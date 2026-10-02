import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/widgets/mine_profile_view.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mine profile matches the 99chat information architecture',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? tappedFeature;
    var favoritesTapped = false;

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) {
          Styles.isDark = false;
          return MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: MineProfileView(
              nickname: 'OpenIM User',
              userId: 'openim-001',
              avatarUrl: '',
              signature: '未设置',
              onProfileTap: () {},
              onQrTap: () {},
              onFavoritesTap: () => favoritesTapped = true,
              onCallsTap: () {},
              onNotificationsTap: () {},
              onShareAppTap: () {},
              onSettingsTap: () {},
              onFeatureTap: (feature) => tappedFeature = feature,
              onUnavailableFeatureTap: (feature) => tappedFeature = 'closed:$feature',
            ),
          );
        },
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppTokens.backgroundLight);
    expect(MediaQuery.textScalerOf(tester.element(find.byType(Scaffold))).scale(17), 17);
    final overlay = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
    );
    expect(overlay.value.systemNavigationBarColor, Colors.transparent);

    expect(find.text('我的'), findsOneWidget);
    expect(find.text('OpenIM User'), findsOneWidget);
    expect(find.text('99号ID: openim-001'), findsOneWidget);
    expect(find.text('个性签名: 未设置'), findsOneWidget);

    for (final text in const [
      '热门生态',
      'AI助手',
      '生活缴费',
      '数字资产',
      '社区广场',
      '收藏',
      '通话',
      '消息通知',
      '分享应用',
      '设置',
    ]) {
      expect(find.text(text), findsOneWidget, reason: 'missing $text');
    }

    expect(find.text('账号设置'), findsNothing);
    expect(find.text('关于我们'), findsNothing);
    expect(find.text('退出登录'), findsNothing);

    await tester.tap(find.text('收藏'));
    await tester.pump();
    expect(favoritesTapped, isTrue);
    expect(tappedFeature, isNull);

    await tester.tap(find.text('生活缴费'));
    await tester.pump();
    expect(tappedFeature, 'closed:生活缴费');
  });

  testWidgets('mine profile uses 99chat mobile width formulas without a 430px cap',
      (tester) async {
    tester.view.physicalSize = const Size(504, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) {
          Styles.isDark = false;
          return MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: MineProfileView(
              nickname: '冬',
              userId: 'im_test',
              avatarUrl: '',
              signature: '未设置',
              onProfileTap: () {},
              onQrTap: () {},
              onFavoritesTap: () {},
              onCallsTap: () {},
              onNotificationsTap: () {},
              onShareAppTap: () {},
              onSettingsTap: () {},
              onFeatureTap: (_) {},
              onUnavailableFeatureTap: (_) {},
            ),
          );
        },
      ),
    );

    final signatureText = tester.widget<Text>(find.text('个性签名: 未设置'));
    expect(signatureText.style?.fontSize, closeTo(504 * 0.034, 0.001));

    final hotEcoText = tester.widget<Text>(find.text('热门生态'));
    expect(hotEcoText.style?.fontSize, closeTo(504 * 0.043, 0.001));
  });


  testWidgets('mine profile locks source-level 99chat geometry and colors',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (_, __) {
          Styles.isDark = false;
          return MaterialApp(
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: MineProfileView(
              nickname: '冬',
              userId: 'im_test',
              avatarUrl: '',
              signature: '未设置',
              onProfileTap: () {},
              onQrTap: () {},
              onFavoritesTap: () {},
              onCallsTap: () {},
              onNotificationsTap: () {},
              onShareAppTap: () {},
              onSettingsTap: () {},
              onFeatureTap: (_) {},
              onUnavailableFeatureTap: (_) {},
            ),
          );
        },
      ),
    );

    final titleRect = tester.getRect(
      find.byKey(const ValueKey('mine-title-text')),
    );
    final indicatorLine = tester.getRect(
      find.byKey(const ValueKey('mine-title-indicator-line')),
    );
    final indicatorDot = tester.getRect(
      find.byKey(const ValueKey('mine-title-indicator-dot')),
    );
    expect(
      indicatorLine.size,
      const Size(
        AppTokens.mainTabIndicatorWidth,
        AppTokens.mainTabIndicatorHeight,
      ),
    );
    expect(
      indicatorDot.size,
      const Size.square(AppTokens.mainTabIndicatorDotSize),
    );
    expect(
      indicatorDot.left - indicatorLine.right,
      AppTokens.mainTabIndicatorGap,
    );
    expect(indicatorLine.top - titleRect.bottom, closeTo(0, 0.001));
    final lineWidget = tester.widget<Container>(
      find.byKey(const ValueKey('mine-title-indicator-line')),
    );
    final lineDecoration = lineWidget.decoration! as BoxDecoration;
    expect(lineDecoration.color, AppTokens.accent);
    final dotWidget = tester.widget<Container>(
      find.byKey(const ValueKey('mine-title-indicator-dot')),
    );
    final dotDecoration = dotWidget.decoration! as BoxDecoration;
    expect(
      dotDecoration.color,
      AppTokens.accent.withValues(alpha: 0.78),
    );

    final signature = tester.widget<Container>(
      find.byKey(const ValueKey('mine-signature-pill')),
    );
    final signatureDecoration = signature.decoration! as BoxDecoration;
    expect(
      signatureDecoration.color,
      AppTokens.profileSignatureBgLight.withValues(alpha: 0.78),
    );

    final qrIcon = tester.widget<AppQrIcon>(
      find.byKey(const ValueKey('mine-profile-qr-icon')),
    );
    expect(qrIcon.size, AppTokens.profileQrIconSize);
    expect(qrIcon.color, AppTokens.accent);

    final editIcon = tester.widget<Icon>(
      find.byKey(const ValueKey('mine-signature-edit-icon')),
    );
    expect(editIcon.icon, Icons.edit_rounded);
    expect(editIcon.size, closeTo(375 * 0.034, 0.001));
    expect(editIcon.color, AppTokens.profileSignatureTextLight);

    final topSettingsIcon = tester.widget<AppSettingsGearIcon>(
      find.descendant(
        of: find.byKey(const ValueKey('mine-top-settings')),
        matching: find.byType(AppSettingsGearIcon),
      ),
    );
    expect(topSettingsIcon.size, AppIconTokens.large);
    expect(topSettingsIcon.color, AppTokens.textPrimaryLight);

    final favoritesRect = tester.getRect(
      find.byKey(const ValueKey('mine-menu-favorites')),
    );
    final callsRect = tester.getRect(
      find.byKey(const ValueKey('mine-menu-calls')),
    );
    final notificationsRect = tester.getRect(
      find.byKey(const ValueKey('mine-menu-notifications')),
    );
    final shareRect = tester.getRect(
      find.byKey(const ValueKey('mine-menu-share-app')),
    );
    final settingsRect = tester.getRect(
      find.byKey(const ValueKey('mine-menu-settings')),
    );
    expect(favoritesRect.height, 56);
    expect(callsRect.top - favoritesRect.bottom, 0);
    expect(notificationsRect.top - callsRect.bottom, 0);
    expect(shareRect.top - notificationsRect.bottom, 0);
    expect(settingsRect.top - shareRect.bottom, 14);

    final titleRow = tester.getRect(
      find.byKey(const ValueKey('mine-hot-eco-title-row')),
    );
    final tilesRow = tester.getRect(
      find.byKey(const ValueKey('mine-hot-eco-tiles-row')),
    );
    expect(titleRow.height, closeTo(375 * 0.11, 0.001));
    expect(tilesRow.top - titleRow.bottom, closeTo(0, 0.001));
  });

}
