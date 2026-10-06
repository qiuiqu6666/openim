import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';
import 'package:openim/pages/wallet/entry/wallet_entry_coordinator.dart';

class WalletEntrySettings extends StubSettingsService {
  bool ready = true;
  bool readyAfterSave = true;
  Object? saveError;
  Future<bool> Function(int)? check;
  final submitted = <String>[];
  final events = <String>[];
  int checks = 0;

  @override
  bool get isBackendAvailable => true;

  @override
  Future<bool> hasTradePassword() async {
    events.add('check');
    checks++;
    return check == null ? ready : await check!(checks);
  }

  @override
  Future<void> setTradePassword(String password) async {
    events.add('save');
    submitted.add(password);
    if (saveError != null) throw saveError!;
    ready = readyAfterSave;
  }
}

class WalletEntryFixture {
  WalletEntryFixture(this.settings) {
    coordinator = WalletEntryCoordinator(
      settingsFactory: () => settings,
      sessionKey: () => session,
    );
  }

  final WalletEntrySettings settings;
  late final WalletEntryCoordinator coordinator;
  final rootNavigator = GlobalKey<NavigatorState>();
  final nestedNavigator = GlobalKey<NavigatorState>();
  late BuildContext context;
  bool active = true;
  String session = 'viewer:token-a';
  final allowed = <String>[];
  final results = <bool>[];

  Future<bool> enter([String source = 'wallet']) async {
    final result = await coordinator.enter(
      context,
      isActive: () => active,
      onAllowed: () => allowed.add(source),
    );
    results.add(result);
    return result;
  }

  Future<void> mount(WidgetTester tester,
      {Locale locale = const Locale('zh', 'CN'), bool nested = false}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(coordinator.dispose);
    Widget entryBuilder(BuildContext entryContext) {
      context = entryContext;
      return Scaffold(
        body: Column(children: [
          TextButton(
            key: const ValueKey('entry-wallet-tab'),
            onPressed: () => unawaited(enter()),
            child: const Text('Wallet tab'),
          ),
          TextButton(
            key: const ValueKey('entry-profile-wallet'),
            onPressed: () => unawaited(enter('profile')),
            child: const Text('Profile wallet'),
          ),
          TextButton(
            key: const ValueKey('entry-other-tab'),
            onPressed: () {
              active = false;
              coordinator.cancel();
            },
            child: const Text('Other tab'),
          ),
        ]),
      );
    }

    await tester.pumpWidget(MaterialApp(
      navigatorKey: rootNavigator,
      locale: locale,
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('zh', 'TW'),
        Locale('en', 'US'),
        Locale('ja', 'JP'),
        Locale('ko', 'KR'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(),
      builder: EasyLoading.init(),
      home: nested
          ? Navigator(
              key: nestedNavigator,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: entryBuilder,
              ),
            )
          : Builder(builder: entryBuilder),
    ));
    await tester.pumpAndSettle();
  }
}

Future<void> enterPaymentPin(WidgetTester tester,
    [String pin = '123456']) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.byKey(ValueKey('trade-password-key-$digit')));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> dismissEntryTip(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}
