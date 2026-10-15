import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/widgets/mine_profile_view.dart';

void main() {
  for (final dark in [false, true]) {
    for (final width in [320.0, 1024.0]) {
      testWidgets(
          'profile fits at 200% text and reduced motion: $width / $dark',
          (tester) async {
        tester.view.physicalSize = Size(width, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: MediaQuery(
                data: MediaQueryData(
                    size: Size(width, 812),
                    textScaler: const TextScaler.linear(2),
                    disableAnimations: true),
                child: MineProfileView(
                    nickname: 'Long user nickname',
                    userId: '@sample-account',
                    avatarUrl: '',
                    signature: 'A long signature with emoji 👨‍👩‍👧‍👦',
                    onProfileTap: () {},
                    onQrTap: () {},
                    onFavoritesTap: () {},
                    onCallsTap: () {},
                    onNotificationsTap: () {},
                    onShareAppTap: () {},
                    onSettingsTap: () {},
                    onFeatureTap: (_) {},
                    onUnavailableFeatureTap: (_) {}))));
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(seconds: 3));
        final scaffold = tester.element(find.byType(Scaffold));
        expect(MediaQuery.textScalerOf(scaffold).scale(16), 32);
        expect(tester.hasRunningAnimations, isFalse);
        expect(find.text('Coming soon'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
