import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/data/wallet_operation_pending_store.dart';
import 'package:openim/pages/wallet/withdrawal/form/wallet_chain_withdrawal_screen.dart';
import 'package:openim/pages/wallet/widgets/pay_password_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../operations/support/wallet_operation_test_support.dart';

const _recipient = 'TP4TT7nd1UEf52K2VXL3678qGbPMYnKaqj';

/// Local reads only; an accidental payment call fails this test immediately.
class _StabilityApi extends WalletOperationTestApi {
  int withdrawalCalls = 0;

  WalletDepositAddress response() => WalletDepositAddress(
        status: 'ready',
        network: 'TRON',
        address: walletOperationTestAddress,
        currencies: const [FundCurrency.usdt, FundCurrency.trx],
        confirmations: 19,
        usdtContract: 'fixture-contract',
        currencyRules: {
          FundCurrency.usdt: WalletCurrencyRule(
            currency: FundCurrency.usdt,
            minWithdrawAmount: '0.1',
            withdrawFee: '0.25',
            withdrawFeeCurrency: FundCurrency.usdt,
          ),
        },
      );

  @override
  Future<WalletDepositAddress> fetchDepositAddress() {
    depositAddressCalls++;
    return onDepositAddress?.call() ?? Future.value(response());
  }

  @override
  Future<WalletWithdrawResult> withdraw({
    required String clientOrderID,
    required FundAmount amount,
    required String toAddress,
    required String payPassword,
    String? verifyChallengeID,
    String? verifyCode,
  }) {
    withdrawalCalls++;
    throw StateError('A stability test must never submit a withdrawal.');
  }
}

Finder _key(String suffix) => find.byKey(ValueKey('wallet-chain-$suffix'));

ScrollableState _scrollable(WidgetTester tester) =>
    tester.state<ScrollableState>(find
        .descendant(of: _key('scroll'), matching: find.byType(Scrollable))
        .first);

class _Geometry {
  _Geometry.capture(WidgetTester tester)
      : offset = _scrollable(tester).position.pixels,
        extent = _scrollable(tester).position.maxScrollExtent,
        rects = {
          for (final suffix in const [
            'address',
            'network',
            'amount',
            'balance',
            'received',
            'fee',
            'fee-info',
            'total-debit',
            'submit',
          ])
            suffix: tester.getRect(_key(suffix)),
        };

  final double offset, extent;
  final Map<String, Rect> rects;

  void expectUnchanged(WidgetTester tester, String phase) {
    expect(_scrollable(tester).position.pixels, closeTo(offset, .01),
        reason: '$phase: the scroll position must not move');
    expect(_scrollable(tester).position.maxScrollExtent, closeTo(extent, .01),
        reason: '$phase: refresh indicators must not change content height');
    for (final entry in rects.entries) {
      final current = tester.getRect(_key(entry.key));
      expect(current.left, closeTo(entry.value.left, .01),
          reason: '$phase: ${entry.key} left');
      expect(current.top, closeTo(entry.value.top, .01),
          reason: '$phase: ${entry.key} top');
      expect(current.width, closeTo(entry.value.width, .01),
          reason: '$phase: ${entry.key} width');
      expect(current.height, closeTo(entry.value.height, .01),
          reason: '$phase: ${entry.key} height');
    }
    expect(tester.takeException(), isNull, reason: phase);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final brightness in Brightness.values) {
    testWidgets(
        'closing fee information keeps every frame stable ${brightness.name}',
        (tester) async {
      final api = _StabilityApi();
      final settings = WalletOperationTestSettings();
      await _mountReady(tester, api, settings, brightness: brightness);
      final geometry = _Geometry.capture(tester);
      expect(geometry.offset, greaterThan(0),
          reason: 'Exercise the fee entry after scrolling on a small screen.');
      final reads = (api.balanceCalls, api.depositAddressCalls);

      await tester.tap(_key('fee-info'));
      await _stableFrames(tester, geometry, 'opening info', loading: false);
      expect(_key('info-dialog'), findsOneWidget);
      expect((api.balanceCalls, api.depositAddressCalls), reads,
          reason:
              'A local read-only explanation must not restart wallet reads.');

      await tester.tap(_key('info-close'));
      await _stableFrames(tester, geometry, 'closing info',
          loading: false, frames: 40);
      expect(_key('info-dialog'), findsNothing);
      expect((api.balanceCalls, api.depositAddressCalls), reads);
      _expectDraft(tester);
      _expectNoPayment(api, settings);
      await _unmount(tester);
    });
  }

  testWidgets('foreground refresh under an open info dialog preserves geometry',
      (tester) async {
    final api = _StabilityApi();
    final settings = WalletOperationTestSettings();
    await _mountReady(tester, api, settings);
    await tester.tap(_key('fee-info'));
    await tester.pumpAndSettle();
    expect(_key('info-dialog'), findsOneWidget);
    final geometry = _Geometry.capture(tester);
    final reads = (api.balanceCalls, api.depositAddressCalls);
    final pending = Completer<WalletDepositAddress>();
    api.onDepositAddress = () => pending.future;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _stableFrames(tester, geometry, 'background info',
        loading: false, frames: 2);
    expect((api.balanceCalls, api.depositAddressCalls), reads);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _waitForRead(tester, api, reads.$2 + 1);
    expect((api.balanceCalls, api.depositAddressCalls),
        (reads.$1 + 1, reads.$2 + 1));
    expect(_key('info-dialog'), findsOneWidget);
    await _stableFrames(tester, geometry, 'foreground overlay',
        loading: true, frames: 8);

    // Closing the explanation during a genuine pending refresh must neither
    // restart that request nor shift the page hidden underneath the dialog.
    await tester.tap(_key('info-close'));
    await _stableFrames(tester, geometry, 'closing during refresh',
        loading: true, frames: 40);
    expect(_key('info-dialog'), findsNothing);
    expect((api.balanceCalls, api.depositAddressCalls),
        (reads.$1 + 1, reads.$2 + 1));

    pending.complete(api.response());
    await tester.pump();
    await _stableFrames(tester, geometry, 'refresh overlay removed',
        loading: false, frames: 8);
    expect((api.balanceCalls, api.depositAddressCalls),
        (reads.$1 + 1, reads.$2 + 1));
    _expectDraft(tester);
    _expectNoPayment(api, settings);
    await _unmount(tester);
  });

  for (final infoOpen in [false, true]) {
    testWidgets('opaque route still resumes reads with info open=$infoOpen',
        (tester) async {
      final api = _StabilityApi();
      final settings = WalletOperationTestSettings();
      await _mountReady(tester, api, settings);
      if (infoOpen) {
        await tester.tap(_key('fee-info'));
        await tester.pumpAndSettle();
        expect(_key('info-dialog'), findsOneWidget);
      }
      final geometry = _Geometry.capture(tester);
      final reads = (api.balanceCalls, api.depositAddressCalls);
      final navigator = Navigator.of(tester.element(_key('withdrawal-screen')),
          rootNavigator: true);
      unawaited(navigator.push<void>(PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) =>
            const Scaffold(body: Center(child: Text('opaque fixture route'))),
      )));
      await tester.pumpAndSettle();
      expect(find.text('opaque fixture route'), findsOneWidget);
      expect((api.balanceCalls, api.depositAddressCalls), reads,
          reason: 'An opaque covering route must pause this wallet page.');

      final pending = Completer<WalletDepositAddress>();
      api.onDepositAddress = () => pending.future;
      navigator.pop();
      await _waitForRead(tester, api, reads.$2 + 1);
      expect((api.balanceCalls, api.depositAddressCalls),
          (reads.$1 + 1, reads.$2 + 1));
      expect(find.text('opaque fixture route'), findsNothing);
      expect(_key('info-dialog'), infoOpen ? findsOneWidget : findsNothing);
      await _stableFrames(tester, geometry, 'opaque resume overlay',
          loading: true, frames: 8);

      pending.complete(api.response());
      await tester.pump();
      await _stableFrames(tester, geometry, 'opaque overlay removed',
          loading: false, frames: 8);
      if (infoOpen) {
        await tester.tap(_key('info-close'));
        await _stableFrames(tester, geometry, 'close info after opaque return',
            loading: false, frames: 40);
      }
      expect((api.balanceCalls, api.depositAddressCalls),
          (reads.$1 + 1, reads.$2 + 1));
      _expectDraft(tester);
      _expectNoPayment(api, settings);
      await _unmount(tester);
    });
  }

  testWidgets('account change while info is open hides the old draft on close',
      (tester) async {
    var owner = 'original-info-fixture-owner';
    final api = _StabilityApi();
    final settings = WalletOperationTestSettings();
    await _mountReady(tester, api, settings,
        accountProvider: () => owner,
        isCurrent: () => owner == 'original-info-fixture-owner');
    await tester.tap(_key('fee-info'));
    await tester.pumpAndSettle();
    expect(_key('info-dialog'), findsOneWidget);
    final reads = (api.balanceCalls, api.depositAddressCalls);

    owner = 'different-info-fixture-owner';
    await tester.tap(_key('info-close'));
    await tester.pumpAndSettle();
    expect(_key('info-dialog'), findsNothing);
    for (final suffix in [
      'address',
      'amount',
      'balance',
      'received',
      'fee',
      'total-debit'
    ]) {
      expect(_key(suffix), findsNothing,
          reason:
              'Closing local information must not retain another account\'s $suffix.');
    }
    expect(tester.widget<FilledButton>(_key('submit')).onPressed, isNull);
    expect(_key('error'), findsOneWidget);
    expect((api.balanceCalls, api.depositAddressCalls), reads,
        reason: 'An invalid owner must not refresh the previous account.');
    expect(tester.takeException(), isNull);
    _expectNoPayment(api, settings);
    await _unmount(tester);
  });
}

Future<void> _mountReady(
  WidgetTester tester,
  _StabilityApi api,
  WalletOperationTestSettings settings, {
  Brightness brightness = Brightness.light,
  String Function()? accountProvider,
  bool Function()? isCurrent,
}) async {
  final operation = testWalletOperation(WalletOperationKind.withdraw, api,
      accountID: 'chain-info-stability-fixture', isCurrent: isCurrent);
  addTearDown(operation.dispose);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await pumpWalletOperation(
    tester,
    WalletChainWithdrawalScreen(
      coin: withdrawalTestCoin(FundCurrency.usdt),
      payMethod: withdrawalTestMethod(FundCurrency.usdt),
      api: api,
      coordinator: operation,
      accountProvider: accountProvider ?? () => operation.accountKey,
      settingsService: settings,
      initialAddress: _recipient,
      scanAddress: (_) async => _recipient,
      securityAuthorizer: (_, __) async => null,
    ),
    size: const Size(320, 640),
    brightness: brightness,
  );
  await tester.enterText(_key('amount'), '12.5');
  tester.testTextInput.hide();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(_key('network'));
  await tester.tap(_key('network'));
  await tester.pumpAndSettle();
  await tester.tap(_key('network-tron'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(_key('fee-info'));
  await tester.pumpAndSettle();
  expect(_key('loading'), findsNothing);
  expect(_key('error'), findsNothing);
  _expectDraft(tester);
}

Future<void> _stableFrames(
  WidgetTester tester,
  _Geometry geometry,
  String phase, {
  required bool loading,
  int frames = 24,
}) async {
  for (var frame = 0; frame < frames; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    geometry.expectUnchanged(tester, '$phase frame $frame');
    expect(_key('loading'), loading ? findsOneWidget : findsNothing,
        reason: '$phase frame $frame');
    expect(find.byType(PayPasswordPrompt), findsNothing);
  }
}

Future<void> _waitForRead(
    WidgetTester tester, _StabilityApi api, int count) async {
  for (var frame = 0; frame < 8 && api.depositAddressCalls < count; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(milliseconds: 16));
  expect(api.depositAddressCalls, count,
      reason:
          'A foreground or opaque-route resume still refreshes real state.');
  expect(_key('loading'), findsOneWidget);
}

void _expectDraft(WidgetTester tester) {
  String input(String suffix) => tester
      .widget<TextField>(
          find.descendant(of: _key(suffix), matching: find.byType(TextField)))
      .controller!
      .text;
  expect(input('address'), _recipient);
  expect(input('amount'), '12.5');
  expect(find.descendant(of: _key('network'), matching: find.text('TRON')),
      findsOneWidget);
  expect(tester.widget<Text>(_key('received')).data, '12.5 USDT');
  expect(tester.widget<FilledButton>(_key('submit')).onPressed, isNotNull);
}

void _expectNoPayment(_StabilityApi api, WalletOperationTestSettings settings) {
  expect(api.withdrawalCalls, 0);
  expect(api.writes, isEmpty);
  expect(settings.statusCalls, 0);
  expect(find.byType(PayPasswordPrompt), findsNothing);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}
