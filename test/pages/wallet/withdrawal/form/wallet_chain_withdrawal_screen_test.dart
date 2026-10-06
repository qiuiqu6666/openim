import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/pages/trade_password_page.dart';
import 'package:openim/pages/fund/withdrawal_security/withdrawal_security.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/data/wallet_operation_coordinator.dart';
import 'package:openim/pages/wallet/data/wallet_operation_pending_store.dart';
import 'package:openim/pages/wallet/withdrawal/form/wallet_chain_withdrawal_screen.dart';
import 'package:openim/pages/wallet/widgets/pay_password_prompt.dart';
import 'package:openim/services/fund_api.dart' show FundApi, FundApiException;
import 'package:shared_preferences/shared_preferences.dart';

import '../../operations/support/wallet_operation_test_support.dart';

// Independent valid recipient; the API's own deposit address is different.
const _recipient = 'TP4TT7nd1UEf52K2VXL3678qGbPMYnKaqj';

class _PendingPasswordSettings extends WalletOperationTestSettings {
  final response = Completer<bool>();

  @override
  Future<bool> hasTradePassword() {
    statusCalls++;
    return response.future;
  }
}

class _SetupPasswordSettings extends WalletOperationTestSettings {
  _SetupPasswordSettings({required this.onCreated}) {
    passwordSet = false;
  }

  final VoidCallback onCreated;
  final createdPins = <String>[];

  @override
  bool get isSecurityBackendAvailable => true;

  @override
  Future<void> setTradePassword(String password) async {
    createdPins.add(password);
    passwordSet = true;
    onCreated();
  }
}

class _FormApi extends WalletOperationTestApi {
  _FormApi({this.currency = FundCurrency.usdt, this.securityTransport}) {
    rule = WalletCurrencyRule(
        currency: currency,
        minWithdrawAmount: '0.1',
        withdrawFee: '0.25',
        withdrawFeeCurrency: currency);
  }

  final FundCurrency currency;
  final FundApi? securityTransport;
  @override
  FundApi get transport => securityTransport ?? super.transport;
  WalletCurrencyRule? rule;
  String available = '100';

  WalletDepositAddress response() => WalletDepositAddress(
        status: 'ready',
        network: 'TRON',
        address: walletOperationTestAddress,
        currencies: const [FundCurrency.usdt, FundCurrency.trx],
        confirmations: 19,
        usdtContract: 'fixture-contract',
        currencyRules: rule == null ? const {} : {currency: rule!},
      );

  @override
  Future<WalletDepositAddress> fetchDepositAddress() {
    depositAddressCalls++;
    return onDepositAddress?.call() ?? Future.value(response());
  }

  @override
  Future<List<FundBalance>> fetchBalances() async {
    balanceCalls++;
    return FundCurrency.values
        .map((coin) => FundBalance(
              currency: coin,
              available:
                  FundAmount.parse(coin == currency ? available : '100', coin),
              frozen: FundAmount.zero(coin),
            ))
        .toList();
  }
}

class _FailedInteractionClearStore extends WalletOperationPendingStore {
  _FailedInteractionClearStore() : super(accountKey: 'chain-cleanup-test');

  @override
  Future<void> clearConfirmedWithdrawal(WalletOperationDraft draft) async =>
      throw StateError('无法清理本次提现记录');
}

FundApi _smsTransport(Dio client, List<RequestOptions> requests) {
  client.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
    requests.add(request);
    final isCheck = request.path.endsWith('/withdrawal-security/check');
    handler.resolve(
        Response<dynamic>(requestOptions: request, statusCode: 200, data: {
      'errCode': 0,
      'data': isCheck
          ? {
              'smsRequired': true,
              'reasons': ['new_device'],
              'blockedUntil': 0,
              'phoneMasked': '+86 138****8000',
              'currency': 'USDT',
              'smsThreshold': '0',
              'cooldownHours': 24,
            }
          : {
              'challengeID': 'live-sheet-proof',
              'expiresAt': DateTime.now()
                  .add(const Duration(minutes: 5))
                  .millisecondsSinceEpoch,
              'retryAfterSeconds': 60,
              'phoneMasked': '+86 138****8000',
            }
    }));
  }));
  return FundApi(
      client: client,
      baseUrl: 'https://chat.test',
      tokenProvider: () => 'fixture-token');
}

Finder _key(String suffix) => find.byKey(ValueKey('wallet-chain-$suffix'));

TextField _field(WidgetTester tester, String suffix) =>
    tester.widget<TextField>(
        find.descendant(of: _key(suffix), matching: find.byType(TextField)));

ButtonStyleButton _submit(WidgetTester tester) =>
    tester.widget<ButtonStyleButton>(_key('submit'));

void _expectNoResultCard() {
  expect(find.byKey(const ValueKey('wallet-operation-status')), findsNothing);
  expect(find.byKey(const ValueKey('wallet-operation-new')), findsNothing);
  expect(find.textContaining('业务单号：'), findsNothing);
}

Future<WalletOperationCoordinator> _mount(
  WidgetTester tester,
  _FormApi api, {
  WalletOperationCoordinator? operation,
  WalletOperationTestSettings? settings,
  String Function()? accountProvider,
  bool Function()? isCurrent,
  String initialAddress = '',
  Future<String?> Function(BuildContext)? scanAddress,
  Brightness brightness = Brightness.light,
  Future<FundSecurityProof?> Function(BuildContext, FundSecurityRequest)?
      securityAuthorizer,
  bool liveSecurity = false,
}) async {
  final coordinator = operation ??
      testWalletOperation(WalletOperationKind.withdraw, api,
          accountID: 'chain-form-test-owner', isCurrent: isCurrent);
  await pumpWalletOperation(
      tester,
      WalletChainWithdrawalScreen(
          coin: withdrawalTestCoin(api.currency),
          payMethod: withdrawalTestMethod(api.currency),
          api: api,
          coordinator: coordinator,
          accountProvider: accountProvider ?? () => coordinator.accountKey,
          settingsService: settings ?? WalletOperationTestSettings(),
          initialAddress: initialAddress,
          securityAuthorizer: liveSecurity
              ? null
              : securityAuthorizer ?? approveWalletSecurityForTest,
          scanAddress: scanAddress),
      brightness: brightness);
  return coordinator;
}

Future<void> _network(WidgetTester tester) async {
  await tester.ensureVisible(_key('network'));
  await tester.tap(_key('network'));
  await tester.pumpAndSettle();
  expect(_key('network-tron'), findsOneWidget);
  await tester.tap(_key('network-tron'));
  await tester.pumpAndSettle();
}

Future<void> _fill(WidgetTester tester, {String amount = '12.345678'}) async {
  await tester.enterText(_key('address'), _recipient);
  await tester.enterText(_key('amount'), amount);
  tester.testTextInput.hide();
  await tester.pump();
  await _network(tester);
}

Future<void> _pressSubmit(WidgetTester tester, {bool settle = true}) async {
  await tester.ensureVisible(_key('submit'));
  expect(_submit(tester).onPressed, isNotNull);
  await tester.tap(_key('submit'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('real transaction SMS sheet resumes to PIN using the same draft',
      (tester) async {
    final client = Dio();
    addTearDown(() => client.close(force: true));
    final requests = <RequestOptions>[];
    final api = _FormApi(securityTransport: _smsTransport(client, requests));
    final operation = await _mount(tester, api, liveSecurity: true);
    await _fill(tester, amount: '1.123456');
    await _pressSubmit(tester);
    expect(find.byKey(const ValueKey('fund-security-sheet')), findsOneWidget);
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(api.writes, isEmpty);
    expect(requests, hasLength(2));
    expect(requests[0].data, requests[1].data);
    expect(requests[0].data['withdrawal'], operation.draft!.withdrawalRequest);
    await tester.enterText(
        find.byKey(const ValueKey('fund-security-code')), '246810');
    tester.testTextInput.hide();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('fund-security-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fund-security-sheet')), findsNothing);
    expect(find.byType(PayPasswordPrompt), findsOneWidget);
    await enterWalletOperationPin(tester);
    expect(api.writes, hasLength(1));
    expect(api.writes.single['clientOrderID'],
        requests[0].data['withdrawal']['clientOrderID']);
    expect(api.writes.single['verifyChallengeID'], 'live-sheet-proof');
    expect(api.writes.single['verifyCode'], '246810');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'real SMS cancellation preserves editable draft inputs without PIN',
      (tester) async {
    final client = Dio();
    addTearDown(() => client.close(force: true));
    final requests = <RequestOptions>[];
    final api = _FormApi(securityTransport: _smsTransport(client, requests));
    final operation = await _mount(tester, api,
        liveSecurity: true, brightness: Brightness.dark);
    await _fill(tester, amount: '1.123456');
    await _pressSubmit(tester);
    expect(find.byKey(const ValueKey('fund-security-sheet')), findsOneWidget);
    expect(requests, hasLength(2));
    await tester.tap(find.byKey(const ValueKey('fund-security-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fund-security-sheet')), findsNothing);
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(api.writes, isEmpty);
    expect(operation.draft, isNull);
    expect(await operation.store.read(WalletOperationKind.withdraw), isNull);
    expect(_field(tester, 'amount').controller!.text, '1.123456');
    expect(_field(tester, 'address').controller!.text, _recipient);
    expect(_field(tester, 'amount').enabled, isTrue);
    expect(_submit(tester).onPressed, isNotNull);
    _expectNoResultCard();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('security verification freezes the exact ID before PIN and write',
      (tester) async {
    final api = _FormApi();
    final verification = Completer<FundSecurityProof?>();
    FundSecurityRequest? checked;
    final operation =
        await _mount(tester, api, securityAuthorizer: (_, request) {
      checked = request;
      return verification.future;
    });
    await _fill(tester, amount: '1.123456');
    await _pressSubmit(tester);
    expect(checked, isNotNull);
    expect(checked!.fields, operation.draft!.withdrawalRequest);
    expect(checked!.fields['mode'], 'chain');
    expect(checked!.fields['network'], 'TRON');
    expect(checked!.fields['toAddress'], _recipient);
    expect(operation.draft!.submitted, false);
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(api.writes, isEmpty);
    verification.complete(const FundSecurityProof(
        challengeID: 'transaction-proof', code: '246810'));
    await tester.pumpAndSettle();
    expect(find.byType(PayPasswordPrompt), findsOneWidget);
    await enterWalletOperationPin(tester);
    expect(
        api.writes.single['clientOrderID'], checked!.fields['clientOrderID']);
    expect(api.writes.single['amount'], checked!.fields['amount']);
    expect(api.writes.single['toAddress'], checked!.fields['toAddress']);
    expect(api.writes.single['verifyChallengeID'], 'transaction-proof');
    expect(api.writes.single['verifyCode'], '246810');
    final preferences = await SharedPreferences.getInstance();
    for (final key in preferences.getKeys()) {
      final saved = preferences.getString(key)!;
      expect(saved, isNot(contains('transaction-proof')));
      expect(saved, isNot(contains('246810')));
      expect(saved, isNot(contains('payPassword')));
    }
    expect(operation.draft, isNull);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(_field(tester, 'amount').controller!.text, isEmpty);
    _expectNoResultCard();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cancelled security does not open PIN or submit', (tester) async {
    final api = _FormApi();
    final operation =
        await _mount(tester, api, securityAuthorizer: (_, __) async => null);
    await _fill(tester);
    await _pressSubmit(tester);
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(api.writes, isEmpty);
    expect(operation.draft, isNull);
    expect(_field(tester, 'amount').controller!.text, '12.345678');
    expect(_field(tester, 'address').controller!.text, _recipient);
    expect(_field(tester, 'amount').enabled, isTrue);
    expect(_submit(tester).onPressed, isNotNull);
    _expectNoResultCard();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'a rejected SMS proof is replaced while retaining the business ID',
      (tester) async {
    final api = _FormApi();
    var checks = 0;
    api.onWithdraw = (_) {
      api.onWithdraw = null;
      return Future.error(const FundApiException(20078, '验证码已失效'));
    };
    final operation = await _mount(tester, api,
        securityAuthorizer: (_, __) async => FundSecurityProof(
            challengeID: 'proof-${++checks}', code: '246810'));
    await _fill(tester, amount: '1.123456');
    await _pressSubmit(tester);
    await enterWalletOperationPin(tester);
    expect(operation.draft!.submitted, false);
    expect(api.writes, hasLength(1));
    expect(checks, 1);
    await enterWalletOperationPin(tester);
    expect(api.writes, hasLength(2));
    expect(checks, 2);
    expect(api.writes[0]['clientOrderID'], api.writes[1]['clientOrderID']);
    expect(api.writes[0]['verifyChallengeID'], 'proof-1');
    expect(api.writes[1]['verifyChallengeID'], 'proof-2');
    expect(operation.receipt, isNull);
    expect(operation.draft, isNull);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(_field(tester, 'amount').controller!.text, isEmpty);
    _expectNoResultCard();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('account change discards a late transaction security proof',
      (tester) async {
    var current = true;
    final api = _FormApi();
    final verification = Completer<FundSecurityProof?>();
    await _mount(tester, api,
        isCurrent: () => current,
        securityAuthorizer: (_, __) => verification.future);
    await _fill(tester);
    await _pressSubmit(tester);
    current = false;
    verification.complete(const FundSecurityProof());
    await tester.pumpAndSettle();
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(api.writes, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final currency in [FundCurrency.usdt, FundCurrency.trx]) {
    testWidgets('${currency.code} has all fields and an exact fee-adjusted all',
        (tester) async {
      final api = _FormApi(currency: currency)
        ..available = '12.345678'
        ..rule = WalletCurrencyRule(
            currency: currency,
            minWithdrawAmount: '0.1',
            withdrawFee: '0.000001',
            withdrawFeeCurrency: currency);
      final settings = WalletOperationTestSettings();
      await _mount(tester, api,
          settings: settings,
          initialAddress: _recipient,
          brightness: currency == FundCurrency.trx
              ? Brightness.dark
              : Brightness.light);
      for (final suffix in ['address', 'network', 'amount', 'all', 'balance']) {
        expect(_key(suffix), findsOneWidget);
      }
      expect(_field(tester, 'address').controller!.text, _recipient);
      await tester.enterText(_key('amount'), '1.123456');
      tester.testTextInput.hide();
      await tester.pump();
      expect(_submit(tester).onPressed, isNull,
          reason: 'An address must not implicitly select a network');
      await _network(tester);
      expect(_submit(tester).onPressed, isNotNull);
      await tester.tap(_key('all'));
      await tester.pump();
      expect(_field(tester, 'amount').controller!.text, '12.345677');
      expect(_submit(tester).onPressed, isNotNull);
      expect(find.textContaining('12.345678'), findsWidgets,
          reason: 'The displayed balance must come from fresh API exact units');
      expect(settings.statusCalls, 0);
      expect(api.writes, isEmpty);
      expect(find.text('下一步'), findsNothing);
      await _pressSubmit(tester);
      final prompt =
          tester.widget<PayPasswordPrompt>(find.byType(PayPasswordPrompt));
      expect(prompt.amountText, '12.345678',
          reason: 'The payment header includes the one-unit fee');
      expect(prompt.amountCoin, currency.displayName);
      await enterWalletOperationPin(tester);
      expect(api.writes.single['amount'], '12.345677',
          reason: 'Only the principal is submitted; the server adds its fee');
      expect(api.writes.single['currency'], currency.code);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('checksum, own address and account names cannot open payment',
      (tester) async {
    final api = _FormApi();
    final settings = WalletOperationTestSettings();
    await _mount(tester, api, settings: settings);
    await _fill(tester);
    expect(_submit(tester).onPressed, isNotNull);
    for (final invalid in [
      'TP4TT7nd1UEf52K2VXL3678qGbPMYnKaqk',
      walletOperationTestAddress,
      '@public-account-name',
    ]) {
      await tester.enterText(_key('address'), invalid);
      tester.testTextInput.hide();
      await tester.pump();
      expect(_submit(tester).onPressed, isNull);
    }
    expect(settings.statusCalls, 0);
    expect(api.writes, isEmpty);
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('scan and paste update only the normalized receiving address',
      (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return {'text': '  tron:$_recipient  '};
      }
      return null;
    });
    try {
      final api = _FormApi();
      await _mount(tester, api,
          scanAddress: (_) async => 'tron:$_recipient?amount=99');
      await tester.enterText(_key('amount'), '1.234567');
      tester.testTextInput.hide();
      await tester.pump();
      await tester.tap(_key('scan'));
      await tester.pumpAndSettle();
      expect(_field(tester, 'address').controller!.text, _recipient);
      expect(_field(tester, 'amount').controller!.text, '1.234567');
      expect(_submit(tester).onPressed, isNull);
      await tester.enterText(_key('address'), 'previous text');
      tester.testTextInput.hide();
      await tester.pump();
      await tester.tap(_key('paste'));
      await tester.pumpAndSettle();
      expect(_field(tester, 'address').controller!.text, _recipient);
      expect(_field(tester, 'amount').controller!.text, '1.234567');
      expect(_submit(tester).onPressed, isNull,
          reason: 'Scanning and pasting must not implicitly select TRON');
      expect(api.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    }
  });

  testWidgets('fresh minimum is checked before password setup or payment',
      (tester) async {
    final api = _FormApi();
    final settings = WalletOperationTestSettings();
    await _mount(tester, api, settings: settings);
    await _fill(tester);
    final previousReads = api.depositAddressCalls;
    api.rule = WalletCurrencyRule(
        currency: FundCurrency.usdt,
        minWithdrawAmount: '50',
        withdrawFee: '0.25',
        withdrawFeeCurrency: FundCurrency.usdt);
    await _pressSubmit(tester);
    expect(api.depositAddressCalls, previousReads + 1);
    expect(settings.statusCalls, 0);
    expect(api.writes, isEmpty);
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(_submit(tester).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('missing rules never permit a new payment or invented zero fee',
      (tester) async {
    final api = _FormApi()..rule = null;
    final settings = WalletOperationTestSettings();
    await _mount(tester, api, settings: settings);
    await _fill(tester);
    expect(_submit(tester).onPressed, isNull);
    expect(settings.statusCalls, 0);
    expect(api.writes, isEmpty);
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'fresh balance must cover principal plus the separately added fee',
      (tester) async {
    final api = _FormApi();
    final settings = WalletOperationTestSettings();
    await _mount(tester, api, settings: settings);
    await _fill(tester);
    final previousReads = api.balanceCalls;
    api.available = '12.345678';
    await _pressSubmit(tester);
    expect(api.balanceCalls, previousReads + 1);
    expect(settings.statusCalls, 0);
    expect(api.writes, isEmpty);
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(_submit(tester).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('repeated submit opens one PIN and posts exact principal once',
      (tester) async {
    final api = _FormApi()
      ..rule = WalletCurrencyRule(
          currency: FundCurrency.usdt,
          minWithdrawAmount: '0.1',
          withdrawFee: '1',
          withdrawFeeCurrency: FundCurrency.usdt);
    final settings = WalletOperationTestSettings();
    final operation = await _mount(tester, api, settings: settings);
    await _fill(tester, amount: '10');
    final callback = _submit(tester).onPressed!;
    callback();
    callback();
    await tester.pumpAndSettle();
    expect(find.byType(PayPasswordPrompt), findsOneWidget);
    final prompt =
        tester.widget<PayPasswordPrompt>(find.byType(PayPasswordPrompt));
    expect(prompt.amountText, '11.00');
    expect(prompt.amountCoin, 'USDT');
    expect(settings.statusCalls, 1);
    expect(api.writes, isEmpty);
    await enterWalletOperationPin(tester);
    expect(api.writes, hasLength(1));
    expect(api.writes.single['amount'], '10');
    expect(api.writes.single['toAddress'], _recipient);
    expect(api.writes.single['currency'], 'USDT');
    expect(operation.receipt, isNull);
    expect(operation.draft, isNull);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(_field(tester, 'amount').controller!.text, isEmpty);
    expect(_field(tester, 'address').controller!.text, isEmpty);
    _expectNoResultCard();
    expect(_submit(tester).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'an uncertain write keeps its original draft and blocks more POSTs',
      (tester) async {
    final api = _FormApi()
      ..onWithdraw = (_) => Future.error(
          const FundApiException(-1, 'fixture timeout', isUncertain: true));
    final operation = await _mount(tester, api);
    await _fill(tester, amount: '1.123456');
    await _pressSubmit(tester);
    await enterWalletOperationPin(tester);
    expect(api.writes, hasLength(1));
    expect(operation.unresolved, isTrue);
    final originalID = operation.draft!.clientOrderID;
    await enterWalletOperationPin(tester);
    expect(api.writes, hasLength(1));
    expect(operation.draft!.clientOrderID, originalID);
    await tester.tap(find.descendant(
        of: find.byType(PayPasswordPrompt),
        matching: find.byIcon(Icons.close_rounded)));
    await tester.pumpAndSettle();
    expect(_submit(tester).onPressed, isNull);
    _expectNoResultCard();
    expect(_field(tester, 'amount').enabled, isFalse);
    expect(_field(tester, 'amount').controller!.text, '1.123456');
    expect(
        (await operation.store.read(WalletOperationKind.withdraw))!
            .clientOrderID,
        originalID);
    expect(api.queriedIDs, isEmpty);
    final query = find.byKey(const ValueKey('wallet-operation-query'));
    expect(query, findsOneWidget);
    api.lastOrder = WalletFundOrder(
        orderID: 'recovered-chain-order',
        clientOrderID: originalID,
        biz: 'withdraw',
        currency: FundCurrency.usdt,
        amount: '1.123456',
        status: 'withdraw_pending',
        toAddress: _recipient,
        fee: '0.25');
    await tester.ensureVisible(query);
    await tester.tap(query);
    await tester.pumpAndSettle();
    expect(api.queriedClientIDs, [originalID]);
    expect(api.writes, hasLength(1));
    expect(find.text('提现申请成功'), findsOneWidget);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(operation.draft, isNull);
    expect(_field(tester, 'amount').controller!.text, isEmpty);
    _expectNoResultCard();
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final brightness in Brightness.values) {
    testWidgets('PIN cancellation preserves editable inputs in $brightness',
        (tester) async {
      final api = _FormApi();
      final operation = await _mount(tester, api, brightness: brightness);
      await _fill(tester, amount: '1.123456');
      await _pressSubmit(tester);
      expect(find.byType(PayPasswordPrompt), findsOneWidget);
      await tester.tap(find.descendant(
          of: find.byType(PayPasswordPrompt),
          matching: find.byIcon(Icons.close_rounded)));
      await tester.pumpAndSettle();
      expect(operation.draft, isNull);
      expect(await operation.store.read(WalletOperationKind.withdraw), isNull);
      expect(api.writes, isEmpty);
      expect(_field(tester, 'address').controller!.text, _recipient);
      expect(_field(tester, 'amount').controller!.text, '1.123456');
      expect(_field(tester, 'address').enabled, isTrue);
      expect(_field(tester, 'amount').enabled, isTrue);
      expect(_submit(tester).onPressed, isNotNull);
      _expectNoResultCard();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'accepted pending withdrawal clears amount for another action in $brightness',
        (tester) async {
      final api = _FormApi();
      api.onWithdraw = (request) async {
        final order = WalletFundOrder(
            orderID: 'pending-${api.writes.length}',
            clientOrderID: request['clientOrderID'] as String,
            biz: 'withdraw',
            currency: FundCurrency.usdt,
            amount: request['amount'] as String,
            status: 'withdraw_pending',
            toAddress: _recipient,
            fee: '0.25');
        api.lastOrder = order;
        return WalletWithdrawResult(order: order, fee: '0.25');
      };
      final operation = await _mount(tester, api, brightness: brightness);
      await _fill(tester, amount: '1.123456');
      await _pressSubmit(tester);
      await enterWalletOperationPin(tester);
      final firstID = api.writes.single['clientOrderID'];
      expect(find.text('提现申请成功'), findsOneWidget);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(operation.draft, isNull);
      expect(operation.receipt, isNull);
      expect(await operation.store.read(WalletOperationKind.withdraw), isNull);
      if (find.text('完成').evaluate().isNotEmpty) {
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();
      }
      expect(_field(tester, 'amount').controller!.text, isEmpty);
      expect(_field(tester, 'address').controller!.text, isEmpty);
      expect(_field(tester, 'amount').enabled, isTrue);
      expect(_submit(tester).onPressed, isNull);
      _expectNoResultCard();
      await tester.enterText(_key('address'), _recipient);
      await tester.enterText(_key('amount'), '2.5');
      tester.testTextInput.hide();
      await tester.pump();
      expect(_submit(tester).onPressed, isNotNull,
          reason: 'The selected network and address are retained');
      await _pressSubmit(tester);
      await enterWalletOperationPin(tester);
      expect(api.writes, hasLength(2));
      expect(api.writes.last['clientOrderID'], isNot(firstID));
      expect(api.writes.last['amount'], '2.5');
      expect(api.writes.last['toAddress'], _recipient);
      if (find.text('完成').evaluate().isNotEmpty) {
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();
      }
      expect(_field(tester, 'amount').controller!.text, isEmpty);
      _expectNoResultCard();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'closing a rejected SMS payment restores editable original inputs',
      (tester) async {
    final api = _FormApi()
      ..onWithdraw =
          (_) => Future.error(const FundApiException(20078, '验证码已失效'));
    final operation = await _mount(tester, api);
    await _fill(tester, amount: '1.123456');
    await _pressSubmit(tester);
    await enterWalletOperationPin(tester);
    final refusedID = api.writes.single['clientOrderID'];
    expect(operation.draft!.submitted, isFalse);
    await tester.tap(find.descendant(
        of: find.byType(PayPasswordPrompt),
        matching: find.byIcon(Icons.close_rounded)));
    await tester.pumpAndSettle();
    expect(operation.draft, isNull);
    expect(_field(tester, 'amount').controller!.text, '1.123456');
    expect(_field(tester, 'address').controller!.text, _recipient);
    expect(_field(tester, 'amount').enabled, isTrue);
    _expectNoResultCard();
    await tester.enterText(_key('amount'), '2.5');
    tester.testTextInput.hide();
    await tester.pump();
    api.onWithdraw = null;
    await _pressSubmit(tester);
    await enterWalletOperationPin(tester);
    expect(api.writes, hasLength(2));
    expect(api.writes.last['clientOrderID'], isNot(refusedID));
    expect(api.writes.last['amount'], '2.5');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'failed confirmed cleanup retains a safe queryable frozen request',
      (tester) async {
    final api = _FormApi();
    final operation = WalletOperationCoordinator(
        kind: WalletOperationKind.withdraw,
        api: api,
        store: _FailedInteractionClearStore(),
        accountID: 'chain-cleanup-test',
        serverURL: 'https://wallet.test',
        isAccountCurrent: () => true);
    await _mount(tester, api, operation: operation);
    await _fill(tester, amount: '1.123456');
    await _pressSubmit(tester);
    await enterWalletOperationPin(tester);
    expect(api.writes, hasLength(1));
    expect(operation.receipt, isNotNull);
    expect(operation.draft!.clientOrderID, api.writes.single['clientOrderID']);
    expect(operation.draft!.orderID, api.lastOrder!.orderID);
    expect(_field(tester, 'amount').enabled, isFalse);
    expect(_submit(tester).onPressed, isNull);
    expect(
        find.byKey(const ValueKey('wallet-operation-query')), findsOneWidget);
    _expectNoResultCard();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a restored submitted order remains queryable without new policy',
      (tester) async {
    final api = _FormApi()..rule = null;
    final operation = testWalletOperation(WalletOperationKind.withdraw, api,
        accountID: 'restored-chain-form');
    final original = WalletOperationDraft(
        kind: WalletOperationKind.withdraw,
        clientOrderID: 'original-chain-client-order',
        amount: FundAmount.parse('3.25', FundCurrency.usdt),
        toAddress: _recipient,
        submitted: true,
        orderID: 'original-server-order');
    await operation.store.save(original);
    api.lastOrder = WalletFundOrder(
        orderID: original.orderID,
        clientOrderID: original.clientOrderID,
        biz: 'withdraw',
        currency: FundCurrency.usdt,
        amount: '3.25',
        status: 'withdraw_done',
        toAddress: _recipient,
        fee: '0.25');
    await _mount(tester, api,
        operation: operation, initialAddress: walletOperationTestAddress);
    expect(_submit(tester).onPressed, isNull);
    expect(operation.draft!.amount, original.amount);
    expect(operation.draft!.toAddress, _recipient);
    final query = find.byKey(const ValueKey('wallet-operation-query'));
    await tester.ensureVisible(query);
    await tester.tap(query);
    await tester.pumpAndSettle();
    expect(find.text('提现申请成功'), findsOneWidget);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(api.queriedIDs, [original.orderID]);
    expect(operation.draft, isNull);
    expect(operation.receipt, isNull);
    expect(_field(tester, 'amount').controller!.text, isEmpty);
    expect(_field(tester, 'address').controller!.text, isEmpty);
    _expectNoResultCard();
    expect(api.writes, isEmpty);
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('account change discards a late prepayment rule response',
      (tester) async {
    var owner = 'original-owner';
    final api = _FormApi();
    final settings = WalletOperationTestSettings();
    await _mount(tester, api,
        settings: settings,
        accountProvider: () => owner,
        isCurrent: () => owner == 'original-owner');
    await _fill(tester);
    final pending = Completer<WalletDepositAddress>();
    api.onDepositAddress = () => pending.future;
    await _pressSubmit(tester, settle: false);
    owner = 'different-owner';
    pending.complete(api.response());
    await tester.pumpAndSettle();
    expect(settings.statusCalls, 0);
    expect(api.writes, isEmpty);
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(_submit(tester).onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('late password status cannot open PIN above another page',
      (tester) async {
    final api = _FormApi();
    final settings = _PendingPasswordSettings();
    await _mount(tester, api, settings: settings);
    await _fill(tester);
    await _pressSubmit(tester);
    expect(settings.statusCalls, 1);
    expect(find.byType(PayPasswordPrompt), findsNothing);
    final navigator = Navigator.of(
        tester.element(find.byType(WalletChainWithdrawalScreen)),
        rootNavigator: true);
    unawaited(navigator.push<void>(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(
            key: ValueKey('ordinary-covered-page'),
            body: Center(child: Text('普通页面'))))));
    await tester.pumpAndSettle();
    settings.response.complete(true);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ordinary-covered-page')), findsOneWidget);
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(api.writes, isEmpty);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.byType(PayPasswordPrompt), findsNothing,
        reason: 'Returning must not resume a cancelled authorization');
    expect(api.writes, isEmpty);
    expect(_submit(tester).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('real password setup returns through fresh rules to one payment',
      (tester) async {
    final api = _FormApi();
    final settings = _SetupPasswordSettings(onCreated: () {
      api.available = '20';
      api.rule = WalletCurrencyRule(
          currency: FundCurrency.usdt,
          minWithdrawAmount: '0.1',
          withdrawFee: '1.000001',
          withdrawFeeCurrency: FundCurrency.usdt);
    });
    await _mount(tester, api, settings: settings);
    await _fill(tester);
    await _pressSubmit(tester);
    expect(find.byType(TradePasswordPage), findsOneWidget);
    expect(find.byType(PayPasswordPrompt), findsNothing);
    final readsBeforeSetup = api.depositAddressCalls;
    for (var confirmation = 0; confirmation < 2; confirmation++) {
      for (final digit in '123456'.split('')) {
        await tester.tap(find.descendant(
            of: find.byType(TradePasswordPage),
            matching: find.byKey(ValueKey('trade-password-key-$digit'))));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }
    expect(settings.createdPins, ['123456']);
    expect(settings.statusCalls, 2);
    expect(find.byType(TradePasswordPage), findsNothing);
    expect(api.depositAddressCalls, greaterThan(readsBeforeSetup));
    expect(find.byType(PayPasswordPrompt), findsOneWidget);
    final prompt =
        tester.widget<PayPasswordPrompt>(find.byType(PayPasswordPrompt));
    expect(prompt.walletSubtitle, contains('20.00'));
    expect(prompt.walletSubtitle, contains('13.345679'),
        reason: 'PIN must show the fee and balance read after password setup');
    expect(prompt.amountText, '13.345679',
        reason: 'The header uses the freshly fetched total debit too');
    expect(api.writes, isEmpty);
    await enterWalletOperationPin(tester);
    expect(api.writes, hasLength(1));
    expect(api.writes.single['amount'], '12.345678');
    expect(api.writes.single['toAddress'], _recipient);
    expect(api.writes.single['payPassword'], '123456');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
