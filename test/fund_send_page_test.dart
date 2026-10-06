import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/fund/fund_send_page.dart';
import 'package:openim/pages/fund/payment/fund_payment_preferences.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';
import 'package:openim/pages/fund/widgets/fund_send_tokens.dart';
import 'package:openim/pages/fund/widgets/fund_pay_sheet.dart';
import 'package:openim/pages/fund/widgets/fund_recipient_user_id.dart';
import 'package:openim/services/fund_api.dart';
import 'package:openim/services/fund_pending_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Settings extends StubSettingsService {
  bool passwordSet = true;
  int checks = 0;
  @override
  bool get isBackendAvailable => true;
  @override
  Future<bool> hasTradePassword() async {
    checks++;
    return passwordSet;
  }
}

class _Api extends FundApi {
  final ids = <String>[];
  final amounts = <String>[];
  final currencies = <FundCurrency>[];
  final remarks = <String?>[];
  final packets = <Map<String, dynamic>>[];
  final available = <FundCurrency, String>{};
  bool uncertain = false;
  bool uncertainRejection = false;
  int? errorCode;
  Completer<void>? transferGate;
  int balanceReads = 0;
  bool failBalanceRead = false;

  final securityChecks = <Map<String, dynamic>>[];
  final securityCodes = <Map<String, dynamic>>[];
  final transferRequests = <Map<String, dynamic>>[];
  final recoveries = <String>[];
  bool smsRequired = false;
  int blockedUntil = 0;
  FundOrder? recoveredOrder;

  @override
  Future<Map<String, dynamic>> requestData(String path,
      {String method = 'POST',
      Map<String, dynamic>? data,
      Map<String, dynamic>? queryParameters,
      bool mutation = false}) async {
    final transfer = Map<String, dynamic>.from(data!['transfer'] as Map);
    if (path == '/chat/fund/withdrawal-security/check') {
      securityChecks.add(transfer);
      return {
        'smsRequired': smsRequired,
        'reasons': smsRequired ? ['new_device'] : <String>[],
        'blockedUntil': blockedUntil,
        'phoneMasked': smsRequired ? '+86 138****8000' : '',
        'currency': transfer['currency'],
        'smsThreshold': '5',
        'cooldownHours': 24,
      };
    }
    if (path == '/chat/fund/withdrawal-security/code') {
      securityCodes.add(transfer);
      return {
        'challengeID': 'transfer-challenge',
        'expiresAt': DateTime.now().millisecondsSinceEpoch + 300000,
        'retryAfterSeconds': 60,
        'phoneMasked': '+86 138****8000',
      };
    }
    throw StateError('Unexpected request: $path');
  }

  @override
  Future<FundOrder> getOrderByClient(String clientOrderID) async {
    recoveries.add(clientOrderID);
    if (recoveredOrder != null) return recoveredOrder!;
    throw const FundApiException(20032, 'Order not found');
  }

  @override
  Future<List<FundBalance>> fetchBalances() async {
    balanceReads++;
    if (failBalanceRead) throw StateError('Refresh failed');
    return [
      for (final c in FundCurrency.values)
        FundBalance(
            currency: c,
            available: FundAmount.parse(available[c] ?? '100', c),
            frozen: FundAmount.zero(c)),
    ];
  }

  @override
  Future<FundOrder> sendTransfer(
      {required String clientOrderID,
      required FundScene scene,
      required FundAmount amount,
      required String recvID,
      String? groupID,
      String? remark,
      String? recipientType,
      String? recipient,
      String? areaCode,
      String? verifyChallengeID,
      String? verifyCode,
      required String payPassword}) async {
    ids.add(clientOrderID);
    amounts.add(amount.decimal);
    currencies.add(amount.currency);
    remarks.add(remark);
    transferRequests.add({
      'clientOrderID': clientOrderID,
      'scene': scene.name,
      'currency': amount.currency.code,
      'amount': amount.decimal,
      'recvID': recvID,
      if (groupID != null) 'groupID': groupID,
      if (remark != null) 'remark': remark,
      if (recipientType != null) 'recipientType': recipientType,
      if (recipient != null) 'recipient': recipient,
      if (areaCode != null) 'areaCode': areaCode,
      'payPassword': payPassword,
      if (verifyChallengeID != null) 'verifyChallengeID': verifyChallengeID,
      if (verifyCode != null) 'verifyCode': verifyCode,
    });
    if (transferGate != null) await transferGate!.future;
    if (errorCode != null) {
      throw FundApiException(errorCode!, 'FundError',
          isUncertain: uncertainRejection);
    }
    if (uncertain) {
      throw const FundApiException(-1, 'timeout', isUncertain: true);
    }
    return FundOrder(
        orderID: 'order-1',
        clientOrderID: clientOrderID,
        biz: 'transfer',
        scene: scene,
        currency: amount.currency,
        amount: amount,
        status: 'done',
        senderID: 'me',
        recvID: recvID,
        remark: remark ?? '');
  }

  @override
  Future<FundOrder> sendPacket({
    required String clientOrderID,
    required FundScene scene,
    required FundPacketBiz biz,
    required FundCurrency currency,
    FundAmount? amount,
    FundAmount? shareAmount,
    int? shareCount,
    String? recvID,
    String? groupID,
    String? remark,
    required String payPassword,
  }) async {
    ids.add(clientOrderID);
    remarks.add(remark);
    packets.add({
      'clientOrderID': clientOrderID,
      'scene': scene.name,
      'biz': biz.code,
      'currency': currency.code,
      'amount': amount?.decimal,
      'shareAmount': shareAmount?.decimal,
      'shareCount': shareCount,
      'recvID': recvID,
      'groupID': groupID,
      if (remark != null) 'remark': remark,
    });
    if (uncertain) {
      throw const FundApiException(-1, 'timeout', isUncertain: true);
    }
    final total = shareAmount?.multipliedBy(shareCount!) ?? amount!;
    return FundOrder(
      orderID: 'order-1',
      clientOrderID: clientOrderID,
      biz: biz.code,
      scene: scene,
      currency: currency,
      amount: total,
      status: scene == FundScene.group && biz != FundPacketBiz.exclusive
          ? 'open'
          : 'done',
      senderID: 'me',
      recvID: recvID ?? '',
      groupID: groupID ?? '',
      shareAmount: shareAmount,
      shareCount: shareCount ?? 0,
      remark: remark?.isNotEmpty == true ? remark! : FundRemark.defaultPacket,
    );
  }
}

class _FailingStore extends FundPendingStore {
  _FailingStore() : super(accountKey: 'test:me');
  @override
  Future<void> save(String scope, Map<String, dynamic> request) async {
    throw StateError('Storage unavailable');
  }
}

class _FailingClearStore extends FundPendingStore {
  _FailingClearStore() : super(accountKey: 'test:me');
  @override
  Future<void> clear(String scope, {String? clientOrderID}) async {
    throw StateError('Cleanup failed');
  }
}

class _GatedSaveStore extends FundPendingStore {
  _GatedSaveStore() : super(accountKey: 'test:me');
  final saved = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> save(String scope, Map<String, dynamic> request) async {
    await super.save(scope, request);
    saved.complete();
    await release.future;
  }
}

class _FailedCurrencyPreferences extends FundPaymentPreferences {
  _FailedCurrencyPreferences()
      : super(accountID: 'me', serverURL: Config.appAuthUrl);
  @override
  Future<void> save(FundCurrency currency) async =>
      throw StateError('Unavailable');
}

class _GatedCurrencyPreferences extends FundPaymentPreferences {
  _GatedCurrencyPreferences()
      : super(accountID: 'me', serverURL: Config.appAuthUrl);
  final release = Completer<void>();
  @override
  Future<void> save(FundCurrency currency) async {
    await release.future;
    await super.save(currency);
  }
}

FundPaymentPreferences _preferences({String account = 'me'}) =>
    FundPaymentPreferences(accountID: account, serverURL: Config.appAuthUrl);

Widget _host(_Api api,
        {bool dark = false,
        double scale = 1,
        bool packet = false,
        String? groupID,
        String? currentUserID = 'me',
        _Settings? settings,
        FundPendingStore? store,
        FundPaymentPreferences? preferences,
        ValueChanged<FundOrder?>? onReturned}) =>
    MaterialApp(
      key: UniqueKey(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      builder: EasyLoading.init(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!)),
      home: Builder(
          builder: (context) => Scaffold(
                  body: TextButton(
                onPressed: () async {
                  final order = await Navigator.of(context).push<FundOrder>(
                      MaterialPageRoute(
                          builder: (_) => FundSendPage(
                              isRedPacket: packet,
                              userID: 'other',
                              groupID: groupID,
                              recipientName: '小明',
                              currentUserID: currentUserID,
                              api: api,
                              settingsService: settings ?? _Settings(),
                              paymentPreferences: preferences,
                              pendingStore: store ??
                                  FundPendingStore(accountKey: 'test:me'))));
                  onReturned?.call(order);
                },
                child: const Text('open'),
              ))),
    );

Future<void> _open(WidgetTester tester, _Api api,
    {bool dark = false,
    double scale = 1,
    bool packet = false,
    String? groupID,
    String? currentUserID = 'me',
    _Settings? settings,
    FundPendingStore? store,
    FundPaymentPreferences? preferences,
    ValueChanged<FundOrder?>? onReturned}) async {
  await tester.pumpWidget(_host(api,
      dark: dark,
      scale: scale,
      packet: packet,
      groupID: groupID,
      currentUserID: currentUserID,
      settings: settings,
      store: store,
      preferences: preferences,
      onReturned: onReturned));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _requestPin(WidgetTester tester) async {
  if (find.byKey(const ValueKey('fund-payment-sheet')).evaluate().isNotEmpty) {
    return;
  }
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const ValueKey('fund-submit')));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('fund-submit')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _pay(WidgetTester tester,
    {bool retry = false, bool packet = false}) async {
  await _requestPin(tester);
  await tester.enterText(
      find.byKey(const ValueKey('fund-pay-password')), '123456');
  await _finishAttempt(tester);
}

Future<void> _finishAttempt(WidgetTester tester) async {
  // Allow the authoritative response to switch the existing panel state,
  // then its success display timer to return the order to the caller.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1000));
  await tester.pumpAndSettle();
  // Keep transient app-level notifications out of subsequent form assertions.
  await EasyLoading.dismiss(animation: false);
  await tester.pump();
}

Future<void> _changePaymentCurrency(
    WidgetTester tester, FundCurrency currency) async {
  await tester.tap(find.byKey(const ValueKey('fund-pay-change-currency')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('fund-pay-method-${currency.code}')));
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('fund-pay-method-confirm')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => EasyLoading.dismiss(animation: false));

  testWidgets('SMS binds the exact reviewed transfer and keeps codes ephemeral',
      (tester) async {
    final gate = Completer<void>();
    final api = _Api()
      ..smsRequired = true
      ..transferGate = gate;
    final store = FundPendingStore(accountKey: 'test:me');
    FundOrder? returned;
    await _open(tester, api,
        store: store, onReturned: (order) => returned = order);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '12.5');
    await tester.enterText(find.byKey(const ValueKey('fund-remark')), '测试转账');
    await _requestPin(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fund-security-sheet')), findsOneWidget);
    expect(api.securityChecks, hasLength(1));
    expect(api.securityCodes.single, api.securityChecks.single);
    expect(
        api.securityChecks.single.keys,
        unorderedEquals([
          'clientOrderID',
          'scene',
          'currency',
          'amount',
          'recvID',
          'remark'
        ]));
    expect(api.ids, isEmpty);
    expect(await store.read('transfer:single:other'), isNull);
    await tester.enterText(
        find.byKey(const ValueKey('fund-security-code')), '48291');
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('fund-security-confirm')))
            .onPressed,
        isNull);
    await tester.enterText(
        find.byKey(const ValueKey('fund-security-code')), '482917');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('fund-security-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fund-payment-sheet')), findsOneWidget);
    expect(api.ids, isEmpty);
    await tester.enterText(
        find.byKey(const ValueKey('fund-pay-password')), '123456');
    await tester.pump();
    expect(api.ids, [api.securityChecks.single['clientOrderID']]);
    final sent = Map<String, dynamic>.from(api.transferRequests.single);
    expect(sent.remove('payPassword'), '123456');
    expect(sent.remove('verifyChallengeID'), 'transfer-challenge');
    expect(sent.remove('verifyCode'), '482917');
    expect(sent, api.securityChecks.single);
    final pending = (await store.read('transfer:single:other'))!;
    expect(pending['clientOrderID'], api.ids.single);
    for (final secret in [
      'payPassword',
      'password',
      'verifyCode',
      'verifyChallengeID'
    ]) {
      expect(pending.containsKey(secret), isFalse);
    }
    gate.complete();
    await _finishAttempt(tester);
    expect(returned?.clientOrderID, api.ids.single);
    expect(await store.read('transfer:single:other'), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accepted pending transfer recovers before SMS or another POST',
      (tester) async {
    final store = FundPendingStore(accountKey: 'test:me');
    const id = 'original-transfer';
    await store.save('transfer:single:other', {
      'clientOrderID': id,
      'scene': 'single',
      'currency': 'USDT',
      'amount': '12.5',
      'recvID': 'other',
      'recipientName': '小明',
      'remark': '原转账',
    });
    final api = _Api()
      ..smsRequired = true
      ..recoveredOrder = FundOrder(
          orderID: 'accepted-order',
          clientOrderID: id,
          biz: 'transfer',
          scene: FundScene.single,
          currency: FundCurrency.usdt,
          amount: FundAmount.parse('12.5', FundCurrency.usdt),
          status: 'done',
          senderID: 'me',
          recvID: 'other',
          remark: '原转账');
    FundOrder? returned;
    await _open(tester, api,
        store: store, onReturned: (order) => returned = order);
    await _requestPin(tester);
    await _finishAttempt(tester);
    expect(api.recoveries, [id]);
    expect(api.securityChecks, isEmpty);
    expect(api.securityCodes, isEmpty);
    expect(api.ids, isEmpty);
    expect(returned?.orderID, 'accepted-order');
    expect(await store.read('transfer:single:other'), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('waiting period blocks SMS and any financial write',
      (tester) async {
    final api = _Api()
      ..smsRequired = true
      ..blockedUntil = DateTime.now().millisecondsSinceEpoch + 86400000;
    final store = FundPendingStore(accountKey: 'test:me');
    await _open(tester, api, store: store);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '1');
    await _requestPin(tester);
    await tester.pumpAndSettle();
    expect(find.text('暂时无法转出'), findsOneWidget);
    expect(find.textContaining('需等待24小时'), findsOneWidget);
    expect(api.securityChecks, hasLength(1));
    expect(api.securityCodes, isEmpty);
    expect(api.ids, isEmpty);
    expect(await store.read('transfer:single:other'), isNull);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fund-payment-sheet')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a first business conflict keeps its ID and locks the original request',
      (tester) async {
    final api = _Api()
      ..errorCode = 20062
      ..uncertainRejection = true;
    final store = FundPendingStore(accountKey: 'test:me');
    await _open(tester, api, store: store);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '12.5');
    await _pay(tester);
    final pending = (await store.read('transfer:single:other'))!;
    expect(pending['clientOrderID'], api.ids.single);
    expect(pending['amount'], '12.5');
    expect(pending['recvID'], 'other');
    expect(pending.containsKey('payPassword'), isFalse);
    expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('fund-amount')))
            .enabled,
        isFalse);
    expect(
        tester
            .widget<InkWell>(
                find.byKey(const ValueKey('fund-pay-change-currency')))
            .onTap,
        isNull);
    expect(api.ids, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final packet in [false, true]) {
    testWidgets('restored default reaches payment packet=$packet',
        (tester) async {
      await _preferences().save(FundCurrency.trx);
      final api = _Api();
      FundOrder? returned;
      await _open(tester, api,
          packet: packet, onReturned: (order) => returned = order);
      await tester.enterText(find.byKey(const ValueKey('fund-amount')), '1');
      await _requestPin(tester);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('fund-payment-sheet')),
              matching: find.text('100.00 TRX')),
          findsOneWidget);
      await _pay(tester, packet: packet);
      expect(returned?.currency, FundCurrency.trx);
      expect(api.ids, hasLength(1));
    });
  }

  testWidgets('form confirmation persists across packet and transfer reopen',
      (tester) async {
    final api = _Api();
    await _open(tester, api);
    await tester.tap(find.byKey(const ValueKey('fund-currency')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fund-pay-method-BI99')));
    await tester.tap(find.byKey(const ValueKey('fund-pay-method-confirm')));
    await tester.pumpAndSettle();
    expect(await _preferences().read(), FundCurrency.bi99);
    expect(api.ids, isEmpty);
    await _open(tester, api, packet: true);
    expect(find.text('100.00 99BI'), findsOneWidget);
    await _open(tester, api);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '1');
    await _pay(tester);
    expect(api.currencies, [FundCurrency.bi99]);
  });

  testWidgets('sheet confirmation persists even when payment is cancelled',
      (tester) async {
    final api = _Api();
    await _open(tester, api);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '1');
    await _requestPin(tester);
    await _changePaymentCurrency(tester, FundCurrency.trx);
    await tester.tap(find.byKey(const ValueKey('fund-cancel-pay')));
    await tester.pumpAndSettle();
    expect(await _preferences().read(), FundCurrency.trx);
    expect(api.ids, isEmpty);
    await _open(tester, api, packet: true, groupID: 'group-1');
    expect(find.text('100.00 TRX'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '1');
    await _pay(tester, packet: true);
    expect(api.packets.single['currency'], 'TRX');
  });

  for (final inPayment in [false, true]) {
    testWidgets('cancelled picker preserves default inPayment=$inPayment',
        (tester) async {
      await _preferences().save(FundCurrency.trx);
      final api = _Api();
      await _open(tester, api);
      await tester.enterText(find.byKey(const ValueKey('fund-amount')), '1');
      if (inPayment) await _requestPin(tester);
      await tester.tap(find.byKey(
          ValueKey(inPayment ? 'fund-pay-change-currency' : 'fund-currency')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fund-pay-method-BI99')));
      await tester.tap(find.byKey(const ValueKey('fund-pay-method-close')));
      await tester.pumpAndSettle();
      expect(await _preferences().read(), FundCurrency.trx);
      await _open(tester, api);
      await tester.enterText(find.byKey(const ValueKey('fund-amount')), '1');
      await _pay(tester);
      expect(api.currencies, [FundCurrency.trx]);
    });

    testWidgets(
        'failed preference write keeps old currency inPayment=$inPayment',
        (tester) async {
      final api = _Api();
      await _open(tester, api, preferences: _FailedCurrencyPreferences());
      await tester.enterText(find.byKey(const ValueKey('fund-amount')), '1');
      if (inPayment) await _requestPin(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(
          ValueKey(inPayment ? 'fund-pay-change-currency' : 'fund-currency')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fund-pay-method-TRX')));
      await tester.tap(find.byKey(const ValueKey('fund-pay-method-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('无法保存支付币种，请重试'), findsWidgets);
      expect(await _preferences().read(), isNull);
      expect(api.ids, isEmpty);
      await _pay(tester);
      expect(api.currencies, [FundCurrency.usdt]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('pending order overrides default without rewriting preference',
      (tester) async {
    await _preferences().save(FundCurrency.bi99);
    final store = FundPendingStore(accountKey: 'test:me');
    await store.save('transfer:single:other', {
      'clientOrderID': 'original-order',
      'scene': 'single',
      'currency': 'USDT',
      'amount': '1',
      'recvID': 'other',
    });
    final api = _Api();
    await _open(tester, api, store: store);
    await _pay(tester);
    expect(api.currencies, [FundCurrency.usdt]);
    expect(api.ids, ['original-order']);
    expect(await _preferences().read(), FundCurrency.bi99);
    await _open(tester, api, packet: true);
    expect(find.text('100.00 99BI'), findsOneWidget);
  });

  testWidgets('another account defaults independently', (tester) async {
    await _preferences().save(FundCurrency.trx);
    final api = _Api();
    await _open(tester, api, currentUserID: 'another-account');
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '1');
    await _pay(tester);
    expect(api.currencies, [FundCurrency.usdt]);
    expect(await _preferences(account: 'another-account').read(), isNull);
    expect(await _preferences().read(), FundCurrency.trx);
  });

  testWidgets('submission waits for confirmed currency persistence',
      (tester) async {
    final preferences = _GatedCurrencyPreferences();
    final api = _Api();
    await _open(tester, api, preferences: preferences);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '1');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fund-currency')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fund-pay-method-TRX')));
    await tester.tap(find.byKey(const ValueKey('fund-pay-method-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fund-submit')),
        warnIfMissed: false);
    await tester.pump();
    expect(find.byKey(const ValueKey('fund-payment-sheet')), findsNothing);
    expect(api.ids, isEmpty);
    preferences.release.complete();
    await tester.pumpAndSettle();
    await _pay(tester);
    expect(api.currencies, [FundCurrency.trx]);
    expect(await _preferences().read(), FundCurrency.trx);
  });

  for (final packet in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets('sheet switches reviewed currency packet=$packet dark=$dark',
          (tester) async {
        final api = _Api()..available[FundCurrency.trx] = '200';
        FundOrder? returned;
        await _open(tester, api,
            packet: packet,
            dark: dark,
            onReturned: (order) => returned = order);
        await tester.enterText(
            find.byKey(const ValueKey('fund-amount')), '1.25');
        await tester.enterText(
            find.byKey(const ValueKey('fund-remark')), '原备注');
        await _requestPin(tester);
        final element =
            tester.element(find.byKey(const ValueKey('fund-payment-sheet')));
        final geometry =
            tester.getRect(find.byKey(const ValueKey('fund-payment-sheet')));
        await tester.enterText(
            find.byKey(const ValueKey('fund-pay-password')), '123');
        await _changePaymentCurrency(tester, FundCurrency.trx);
        expect(tester.element(find.byKey(const ValueKey('fund-payment-sheet'))),
            same(element));
        expect(tester.getRect(find.byKey(const ValueKey('fund-payment-sheet'))),
            geometry);
        final paymentSheet = find.byKey(const ValueKey('fund-payment-sheet'));
        expect(
            find.descendant(
                of: paymentSheet, matching: find.text('200.00 TRX')),
            findsOneWidget);
        expect(find.descendant(of: paymentSheet, matching: find.text('1.25')),
            findsOneWidget);
        expect(find.descendant(of: paymentSheet, matching: find.text('TRX')),
            findsOneWidget);
        expect(
            tester
                .widget<TextField>(
                    find.byKey(const ValueKey('fund-pay-password')))
                .controller!
                .text,
            isEmpty);
        expect(api.ids, isEmpty);
        await _pay(tester, packet: packet);
        expect(api.ids, hasLength(1));
        expect(returned?.currency, FundCurrency.trx);
        expect(returned?.amount.decimal, '1.25');
        expect(api.remarks, ['原备注']);
        if (packet) {
          expect(api.packets.single['currency'], 'TRX');
        } else {
          expect(api.currencies, [FundCurrency.trx]);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('cancelled currency picker keeps the reviewed currency and PIN',
      (tester) async {
    final api = _Api();
    await _open(tester, api);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '1');
    await _requestPin(tester);
    await tester.enterText(
        find.byKey(const ValueKey('fund-pay-password')), '123');
    await tester.tap(find.byKey(const ValueKey('fund-pay-change-currency')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('fund-pay-password')))
            .enabled,
        isFalse);
    await tester.tap(find.byKey(const ValueKey('fund-pay-method-TRX')));
    await tester.tap(find.byKey(const ValueKey('fund-pay-method-close')));
    await tester.pumpAndSettle();
    expect(find.text('100.00 USDT'), findsOneWidget);
    final pin = tester
        .widget<TextField>(find.byKey(const ValueKey('fund-pay-password')));
    expect(pin.enabled, isTrue);
    expect(pin.controller!.text, '123');
    expect(api.ids, isEmpty);
    await _pay(tester);
    expect(api.currencies, [FundCurrency.usdt]);
  });

  for (final normal in [false, true]) {
    testWidgets(
        'group currency change preserves share accounting normal=$normal',
        (tester) async {
      final api = _Api();
      await _open(tester, api, packet: true, groupID: 'group-1');
      if (normal) {
        await tester.tap(find.byKey(const ValueKey('fund-packet-type')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('普通红包').last);
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byKey(const ValueKey('fund-amount')), '0.29');
      await tester.enterText(find.byKey(const ValueKey('fund-count')), '3');
      await _requestPin(tester);
      await _changePaymentCurrency(tester, FundCurrency.bi99);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('fund-payment-sheet')),
              matching: find.text(normal ? '0.87' : '0.29')),
          findsOneWidget);
      await _pay(tester, packet: true);
      expect(api.packets.single['currency'], 'BI99');
      expect(api.packets.single['shareCount'], 3);
      expect(api.packets.single[normal ? 'shareAmount' : 'amount'], '0.29');
      expect(api.packets.single['groupID'], 'group-1');
      expect(api.ids, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('currency switch rejects precision instead of rounding payment',
      (tester) async {
    final api = _Api();
    await _open(tester, api);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '1.123');
    await _requestPin(tester);
    await _changePaymentCurrency(tester, FundCurrency.bi99);
    expect(find.text('100.00 USDT'), findsOneWidget);
    expect(find.text('99BI 最多支持 2 位小数'), findsWidgets);
    expect(api.ids, isEmpty);
    await _pay(tester);
    expect(api.amounts, ['1.123']);
    expect(api.currencies, [FundCurrency.usdt]);
  });

  testWidgets('currency switch after definite rejection creates a fresh order',
      (tester) async {
    final api = _Api()..errorCode = 20026;
    await _open(tester, api);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '2');
    await _pay(tester);
    expect(api.currencies, [FundCurrency.usdt]);
    await _changePaymentCurrency(tester, FundCurrency.bi99);
    expect(find.text('100.00 99BI'), findsOneWidget);
    api.errorCode = null;
    await _pay(tester);
    expect(api.currencies, [FundCurrency.usdt, FundCurrency.bi99]);
    expect(api.ids.toSet(), hasLength(2));
    expect(api.amounts, ['2', '2']);
    expect(api.securityChecks, hasLength(2));
    for (var i = 0; i < api.ids.length; i++) {
      expect(api.securityChecks[i]['clientOrderID'], api.ids[i]);
      expect(api.securityChecks[i]['currency'], api.currencies[i].code);
      expect(api.securityChecks[i]['amount'], api.amounts[i]);
    }
  });

  testWidgets(
      'in-flight payment and uncertain retries lock the original currency',
      (tester) async {
    final gate = Completer<void>();
    final api = _Api()..transferGate = gate;
    await _open(tester, api);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '2');
    await _requestPin(tester);
    await _changePaymentCurrency(tester, FundCurrency.trx);
    final change = tester
        .widget<InkWell>(find.byKey(const ValueKey('fund-pay-change-currency')))
        .onTap!;
    await tester.enterText(
        find.byKey(const ValueKey('fund-pay-password')), '123456');
    await tester.pump();
    change();
    await tester.tap(find.byKey(const ValueKey('fund-pay-wallet-card')),
        warnIfMissed: false);
    await tester.pump();
    expect(find.byKey(const ValueKey('fund-pay-method-confirm')), findsNothing);
    expect(api.ids, hasLength(1));
    api.uncertain = true;
    gate.complete();
    await _finishAttempt(tester);
    expect(
        tester
            .widget<InkWell>(
                find.byKey(const ValueKey('fund-pay-change-currency')))
            .onTap,
        isNull);
    change();
    await tester.pump();
    expect(find.byKey(const ValueKey('fund-pay-method-confirm')), findsNothing);
    final saved = await FundPendingStore(accountKey: 'test:me')
        .read('transfer:single:other');
    expect(saved?['currency'], 'TRX');
    api.uncertain = false;
    api.transferGate = null;
    await _pay(tester);
    expect(api.currencies, [FundCurrency.trx, FundCurrency.trx]);
    expect(api.ids.toSet(), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final packet in [false, true]) {
    testWidgets(
        'trimmed remark reaches payment and returned order packet=$packet',
        (tester) async {
      final api = _Api();
      FundOrder? returned;
      await _open(tester, api,
          packet: packet, onReturned: (order) => returned = order);
      await tester.enterText(find.byKey(const ValueKey('fund-amount')), '1');
      await tester.enterText(
          find.byKey(const ValueKey('fund-remark')), '  生日快乐🎂  ');
      await _pay(tester, packet: packet);
      expect(api.remarks, ['生日快乐🎂']);
      expect(returned?.remark, '生日快乐🎂');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'remark rejects 13 code points before requesting a PIN packet=$packet',
        (tester) async {
      final api = _Api();
      await _open(tester, api, packet: packet);
      await tester.enterText(find.byKey(const ValueKey('fund-amount')), '1');
      // Six visually single emoji with skin tones are twelve Unicode points.
      await tester.enterText(find.byKey(const ValueKey('fund-remark')),
          '${List.filled(6, '👍🏽').join()}x');
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.ensureVisible(find.byKey(const ValueKey('fund-submit')));
      await tester.tap(find.byKey(const ValueKey('fund-submit')));
      await tester.pumpAndSettle();
      expect(find.text('最多输入12个字符'), findsOneWidget);
      expect(find.byKey(const ValueKey('fund-pay-password')), findsNothing);
      expect(api.ids, isEmpty);
      await tester.enterText(find.byKey(const ValueKey('fund-remark')),
          List.filled(12, '😀').join());
      await _pay(tester, packet: packet);
      expect(api.remarks.single?.runes.length, 12);
    });
  }

  testWidgets('uncertain payment freezes remark through retry and page reopen',
      (tester) async {
    final api = _Api()..uncertain = true;
    await _open(tester, api);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '1');
    await tester.enterText(find.byKey(const ValueKey('fund-remark')), ' 原备注 ');
    await _pay(tester);
    final stored = await FundPendingStore(accountKey: 'test:me')
        .read('transfer:single:other');
    expect(stored?['remark'], '原备注');
    expect(stored?.containsKey('payPassword'), isFalse);
    final form =
        tester.widget<TextFormField>(find.byKey(const ValueKey('fund-remark')));
    expect(form.enabled, isFalse);
    form.controller!.text = '后改的说明';
    await _pay(tester, retry: true);
    expect(api.remarks, ['原备注', '原备注']);
    expect(api.ids.toSet(), hasLength(1));
    await tester.tap(find.byKey(const ValueKey('fund-cancel-pay')));
    await tester.pumpAndSettle();
    await _open(tester, api);
    final restored =
        tester.widget<TextFormField>(find.byKey(const ValueKey('fund-remark')));
    expect(restored.controller!.text, '原备注');
    expect(restored.enabled, isFalse);
    api.uncertain = false;
    await _pay(tester, retry: true);
    expect(api.remarks, ['原备注', '原备注', '原备注']);
    expect(api.ids.toSet(), hasLength(1));
    expect(
        await FundPendingStore(accountKey: 'test:me')
            .read('transfer:single:other'),
        isNull);
  });

  test('pending payment cannot change its first remark', () async {
    final store = FundPendingStore(accountKey: 'test:me');
    const scope = 'transfer:single:other';
    final request = {
      'clientOrderID': 'frozen-order',
      'scene': 'single',
      'currency': 'USDT',
      'amount': '1',
      'recvID': 'other',
      'remark': '原备注',
    };
    await store.save(scope, request);
    await expectLater(store.save(scope, {...request, 'remark': '新备注'}),
        throwsA(isA<FundPendingConflict>()));
    expect((await store.read(scope))?['remark'], '原备注');
  });

  testWidgets('legacy pending payment retries without adding a remark',
      (tester) async {
    final store = FundPendingStore(accountKey: 'test:me');
    const scope = 'transfer:single:other';
    await store.save(scope, {
      'clientOrderID': 'legacy-order',
      'scene': 'single',
      'currency': 'USDT',
      'amount': '1',
      'recvID': 'other',
    });
    final api = _Api()..uncertain = true;
    await _open(tester, api, store: store);
    final form =
        tester.widget<TextFormField>(find.byKey(const ValueKey('fund-remark')));
    expect(form.controller!.text, isEmpty);
    expect(form.enabled, isFalse);
    form.controller!.text = '不能改写旧交易';
    await _pay(tester);
    expect(api.ids, ['legacy-order']);
    expect(api.remarks, [null]);
    expect((await store.read(scope))!.containsKey('remark'), isFalse);
    api.uncertain = false;
    await _pay(tester, retry: true);
    expect(api.ids, ['legacy-order', 'legacy-order']);
    expect(api.remarks, [null, null]);
    expect(await store.read(scope), isNull);
  });

  testWidgets(
      'single transfer sends exact amount once and clears pending request',
      (tester) async {
    final api = _Api();
    await _open(tester, api);
    await tester.enterText(
        find.byKey(const ValueKey('fund-amount')), '0.000001');
    await _pay(tester);
    expect(api.amounts, ['0.000001']);
    expect(api.ids, hasLength(1));
    expect(
        await FundPendingStore(accountKey: 'test:me')
            .read('transfer:single:other'),
        isNull);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets(
      'timeout restores locked request and retries original id after reopening',
      (tester) async {
    final api = _Api()..uncertain = true;
    await _open(tester, api);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '12.5');
    await _pay(tester);
    final pending = await FundPendingStore(accountKey: 'test:me')
        .read('transfer:single:other');
    expect(pending!['amount'], '12.5');
    expect(pending.containsKey('payPassword'), isFalse);
    expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('fund-amount')))
            .enabled,
        isFalse);
    await _open(tester, api);
    expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('fund-amount')))
            .controller!
            .text,
        '12.5');
    api.uncertain = false;
    await _pay(tester, retry: true);
    expect(api.ids, hasLength(2));
    expect(api.ids[0], api.ids[1]);
    expect(api.amounts, ['12.5', '12.5']);
  });

  testWidgets(
      'invalid precision does not request payment password or send funds',
      (tester) async {
    final api = _Api();
    await _open(tester, api);
    await tester.enterText(
        find.byKey(const ValueKey('fund-amount')), '1.1234567');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('fund-submit')));
    await tester.pumpAndSettle();
    expect(find.text('请输入有效金额，最多 6 位小数'), findsOneWidget);
    expect(find.byKey(const ValueKey('fund-pay-password')), findsNothing);
    expect(api.ids, isEmpty);
  });

  testWidgets('99chat packet uses reference rows, wallet card and red action',
      (tester) async {
    await _open(tester, _Api(), packet: true, groupID: 'group-1');
    expect(find.byKey(const ValueKey('fund-packet-total')), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('fund-total-amount')))
            .style!
            .fontSize,
        43);
    final row = tester.widget<Container>(
        find.byKey(const ValueKey('fund-packet-amount-row')));
    expect((row.decoration as BoxDecoration).color, AppTokens.surfaceLight);
    expect((row.decoration as BoxDecoration).borderRadius,
        BorderRadius.circular(FundWalletTokens.fieldRadius));
    expect(
        tester
            .getSize(find.byKey(const ValueKey('fund-packet-amount-row')))
            .height,
        FundWalletTokens.fieldHeight);
    expect(tester.getSize(find.byKey(const ValueKey('fund-currency'))).height,
        FundWalletTokens.payCardHeight);
    final button =
        tester.widget<Container>(find.byKey(const ValueKey('fund-submit')));
    expect((button.decoration as BoxDecoration).color, AppTokens.walletDanger);
    expect(tester.getSize(find.byKey(const ValueKey('fund-submit'))).height,
        FundWalletTokens.packetButtonHeight);
    expect(
        tester.getSize(find.byKey(const ValueKey('fund-submit'))).width,
        closeTo(
            (FundTokens.contentMaxWidth - FundWalletTokens.packetOuter * 2) *
                .52,
            .01));
    expect(find.text('恭喜发财，大吉大利'), findsOneWidget);
    expect(find.byKey(const ValueKey('fund-packet-type')), findsOneWidget);
    expect(
        tester
            .widgetList<Text>(find.byType(Text))
            .any((text) => (text.data ?? '').contains('¥')),
        false);
  });

  testWidgets(
      '99chat transfer shows recipient row, native amount and fixed red confirm',
      (tester) async {
    await _open(tester, _Api());
    expect(
        find.byKey(const ValueKey('fund-transfer-recipient')), findsOneWidget);
    expect(find.byType(AvatarView), findsOneWidget);
    expect(find.text('转账给 小明'), findsOneWidget);
    expect(find.text('99Chat ID号：other'), findsNothing);
    expect(
        tester
            .widget<FundRecipientUserID>(find.byType(FundRecipientUserID))
            .userID,
        'other');
    expect(tester.widget<AvatarView>(find.byType(AvatarView)).width,
        FundWalletTokens.transferAvatar);
    expect(
        tester
            .widget<TextField>(find.descendant(
                of: find.byKey(const ValueKey('fund-amount')),
                matching: find.byType(TextField)))
            .style!
            .fontSize,
        FundWalletTokens.transferInputFont);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '1');
    await tester.pump();
    final button =
        tester.widget<Container>(find.byKey(const ValueKey('fund-submit')));
    expect((button.decoration as BoxDecoration).color, AppTokens.walletDanger);
    expect(
        tester.getSize(find.byKey(const ValueKey('fund-submit'))),
        const Size(FundWalletTokens.transferButtonWidth,
            FundWalletTokens.transferButtonHeight));
    expect(find.text('确认'), findsOneWidget);
  });

  testWidgets('99chat payment panel authorizes a pasted six-digit PIN once',
      (tester) async {
    final api = _Api();
    await _open(tester, api);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '12.5');
    await _requestPin(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const ValueKey('fund-pay-wallet-card')), findsOneWidget);
    expect(find.text('100.00 USDT'), findsOneWidget);
    expect(find.text('12.50'), findsOneWidget);
    expect(find.text('ABC'), findsNothing);
    final pin = tester
        .widget<TextField>(find.byKey(const ValueKey('fund-pay-password')));
    expect(pin.keyboardType, TextInputType.none);
    expect(pin.obscureText, true);
    expect(pin.showCursor, false);
    expect(pin.style!.color!.a, 0);
    expect(pin.enableInteractiveSelection, true);
    expect(pin.enableIMEPersonalizedLearning, false);
    for (var index = 0; index < 6; index++) {
      final cell = tester.widget<AnimatedContainer>(
          find.byKey(ValueKey('trade-password-cell-$index')));
      expect((cell.decoration as BoxDecoration).border,
          Border.all(color: AppTokens.border(dark: false), width: .5));
      expect(tester.getSize(find.byKey(ValueKey('trade-password-cell-$index'))),
          const Size.square(FundWalletTokens.payCellSize));
      expect((cell.decoration as BoxDecoration).color,
          AppTokens.surfaceAlt(dark: false));
    }
    await tester.enterText(
        find.byKey(const ValueKey('fund-pay-password')), '12345');
    await tester.pump();
    expect(api.ids, isEmpty);
    await tester.enterText(
        find.byKey(const ValueKey('fund-pay-password')), '123456');
    // A selection update is another controller notification after the paste.
    pin.controller!.selection = const TextSelection.collapsed(offset: 6);
    await _finishAttempt(tester);
    expect(api.ids, hasLength(1));
    expect(api.amounts, ['12.5']);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('reference wallet selector uses real BI99 balance and precision',
      (tester) async {
    final api = _Api();
    await _open(tester, api);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '1.123');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fund-currency')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('fund-pay-method-close'))),
        const Size.square(28));
    expect(
        tester
            .getSize(find.byKey(const ValueKey('fund-pay-method-confirm')))
            .height,
        48);
    final confirm = tester.widget<Container>(
        find.byKey(const ValueKey('fund-pay-method-confirm')));
    expect((confirm.decoration as BoxDecoration).color, AppTokens.accent);
    expect(
        find.descendant(
            of: find.byType(BottomSheet), matching: find.text('100.00')),
        findsNWidgets(3));
    await tester.tap(find.byKey(const ValueKey('fund-pay-method-BI99')));
    await tester.pump();
    final mark = tester.widget<Container>(
        find.byKey(const ValueKey('fund-pay-method-mark-BI99')));
    expect((mark.decoration as BoxDecoration).color, AppTokens.accent);
    await tester.tap(find.byKey(const ValueKey('fund-pay-method-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fund-submit')));
    await tester.pumpAndSettle();
    expect(find.text('请输入有效金额，最多 2 位小数'), findsOneWidget);
    expect(find.byKey(const ValueKey('fund-pay-password')), findsNothing);
    expect(api.ids, isEmpty);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '1.12');
    await _pay(tester);
    expect(api.amounts, ['1.12']);
    expect(api.currencies, [FundCurrency.bi99]);
  });

  testWidgets('99chat keypad supports deletion and sixth digit completes once',
      (tester) async {
    final api = _Api();
    await _open(tester, api);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '3');
    await _requestPin(tester);
    for (final digit in ['1', '2', '3', '4', '5']) {
      await tester.tap(find.byKey(ValueKey('trade-password-key-$digit')));
      await tester.pump();
    }
    expect(api.ids, isEmpty);
    await tester.tap(find.byKey(const ValueKey('trade-password-key-del')));
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('fund-pay-password')))
            .controller!
            .text,
        '1234');
    await tester.tap(find.byKey(const ValueKey('trade-password-key-5')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('trade-password-key-6')));
    await _finishAttempt(tester);
    expect(api.ids, hasLength(1));
    expect(api.amounts, ['3']);
  });

  testWidgets('native transfer amount preserves decimal editing before PIN',
      (tester) async {
    final api = _Api();
    await _open(tester, api);
    await tester.tap(find.byKey(const ValueKey('fund-amount')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fund-amount-keypad')), findsNothing);
    final amountInput = tester.widget<TextField>(find.descendant(
        of: find.byKey(const ValueKey('fund-amount')),
        matching: find.byType(TextField)));
    expect(amountInput.keyboardType,
        const TextInputType.numberWithOptions(decimal: true));
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '12.39');
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '12.3');
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '12.34');
    await tester.pump();
    expect(amountInput.controller!.text, '12.34');
    expect(api.ids, isEmpty);
    await tester.tap(find.byKey(const ValueKey('fund-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const ValueKey('fund-pay-password')), findsOneWidget);
    expect(find.byKey(const ValueKey('fund-amount-keypad')), findsNothing);
    expect(api.ids, isEmpty);
    await tester.enterText(
        find.byKey(const ValueKey('fund-pay-password')), '123456');
    await _finishAttempt(tester);
    expect(api.amounts, ['12.34']);
    expect(api.ids, hasLength(1));
  });
  for (final dark in [false, true]) {
    testWidgets(
        'payment panel stays usable with keyboard and large ${dark ? 'dark' : 'light'} text',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final api = _Api();
      await _open(tester, api, dark: dark, scale: 2);
      await tester.enterText(find.byKey(const ValueKey('fund-amount')), '12.5');
      await _requestPin(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await tester.enterText(
          find.byKey(const ValueKey('fund-pay-password')), '12345');
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(api.ids, isEmpty);
      await tester.ensureVisible(find.byKey(const ValueKey('fund-cancel-pay')));
      await tester.tap(find.byKey(const ValueKey('fund-cancel-pay')));
      await tester.pumpAndSettle();
      expect(api.ids, isEmpty);
    });
  }

  for (final normal in [false, true]) {
    testWidgets(
        '${normal ? 'normal' : 'lucky'} group packet restores immutable payload after timeout',
        (tester) async {
      final api = _Api()..uncertain = true;
      await _open(tester, api, packet: true, groupID: 'group-1');
      if (normal) {
        await tester.tap(find.byKey(const ValueKey('fund-packet-type')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('普通红包').last);
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byKey(const ValueKey('fund-amount')), '0.29');
      await tester.ensureVisible(find.byKey(const ValueKey('fund-count')));
      await tester.enterText(find.byKey(const ValueKey('fund-count')), '3');
      await _pay(tester, packet: true);
      final saved = await FundPendingStore(accountKey: 'test:me')
          .read('packet:group:group-1');
      expect(saved!['biz'], normal ? 'packet_normal' : 'packet_lucky');
      expect(saved[normal ? 'shareAmount' : 'amount'], '0.29');
      expect(saved['shareCount'], 3);
      expect(saved.containsKey('recvID'), false);
      expect(saved.containsKey('payPassword'), false);
      await _open(tester, api, packet: true, groupID: 'group-1');
      api.uncertain = false;
      await _pay(tester, retry: true, packet: true);
      expect(api.packets, hasLength(2));
      expect(api.packets[0], api.packets[1]);
      expect(api.packets[0]['shareAmount'], normal ? '0.29' : null);
      expect(api.packets[0]['amount'], normal ? null : '0.29');
      expect(api.packets[0]['groupID'], 'group-1');
      expect(api.ids[0], api.ids[1]);
    });
  }

  testWidgets(
      'definitive rejection unlocks fields and clears the failed request',
      (tester) async {
    final api = _Api()..errorCode = 20026;
    await _open(tester, api);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '12.5');
    await _pay(tester);
    expect(
        await FundPendingStore(accountKey: 'test:me')
            .read('transfer:single:other'),
        isNull);
    expect(find.byKey(const ValueKey('pay-state-enteringPassword')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fund-cancel-pay')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('fund-amount')))
            .enabled,
        isTrue);
    expect(find.text('可用余额不足'), findsOneWidget);
  });

  for (final rejection in [20035, 20036]) {
    testWidgets(
        'timeout then password rejection $rejection preserves the original payment',
        (tester) async {
      final api = _Api()..uncertain = true;
      await _open(tester, api);
      await tester.enterText(find.byKey(const ValueKey('fund-amount')), '12.5');
      await _pay(tester);
      final original = await FundPendingStore(accountKey: 'test:me')
          .read('transfer:single:other');
      api.uncertain = false;
      api.errorCode = rejection;
      await _pay(tester, retry: true);
      expect(
          await FundPendingStore(accountKey: 'test:me')
              .read('transfer:single:other'),
          original);
      expect(
          tester
              .widget<TextFormField>(find.byKey(const ValueKey('fund-amount')))
              .enabled,
          isFalse);
      expect(find.text('重试原交易'), findsOneWidget);
      api.errorCode = null;
      await _pay(tester, retry: true);
      expect(api.ids, hasLength(3));
      expect(api.ids.toSet(), {original!['clientOrderID']});
      expect(api.amounts, ['12.5', '12.5', '12.5']);
      expect(
          await FundPendingStore(accountKey: 'test:me')
              .read('transfer:single:other'),
          isNull);
    });
  }

  testWidgets('storage failure prevents financial dispatch', (tester) async {
    final api = _Api();
    await _open(tester, api, store: _FailingStore());
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '12.5');
    await _pay(tester);
    expect(api.ids, isEmpty);
    expect(find.text('无法保存本次交易，请重试'), findsWidgets);
  });

  testWidgets(
      'pending request stays in the same panel and success returns once',
      (tester) async {
    final gate = Completer<void>();
    final api = _Api()..transferGate = gate;
    final returned = <FundOrder?>[];
    final store = _FailingClearStore();
    await _open(tester, api, store: store, onReturned: returned.add);
    await tester.enterText(
        find.byKey(const ValueKey('fund-amount')), '1.000001');
    await _requestPin(tester);
    final sheet = tester.widget<FundPaySheet>(find.byType(FundPaySheet));
    final sheetElement =
        tester.element(find.byKey(const ValueKey('fund-payment-sheet')));
    final keypadSize =
        tester.getSize(find.byKey(const ValueKey('payment-keypad-region')));
    await tester.enterText(
        find.byKey(const ValueKey('fund-pay-password')), '123456');
    await tester.pump();
    expect(api.ids, hasLength(1));
    expect(find.byKey(const ValueKey('pay-state-processing')), findsOneWidget);
    expect(tester.element(find.byKey(const ValueKey('fund-payment-sheet'))),
        same(sheetElement));
    expect(tester.getSize(find.byKey(const ValueKey('payment-keypad-region'))),
        keypadSize);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('fund-pay-password')))
            .enabled,
        false);
    final duplicate = sheet.onPay('654321');
    await tester.tap(find.byKey(const ValueKey('fund-cancel-pay')));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const ValueKey('pay-state-processing')), findsOneWidget);
    expect(api.ids, hasLength(1));
    api.failBalanceRead = true;
    gate.complete();
    await tester.pump();
    expect(find.byKey(const ValueKey('pay-state-success')), findsOneWidget);
    expect(returned, isEmpty);
    expect((await duplicate).orderID, 'order-1');
    // Cleanup/read failures are independent from a confirmed payment. Even a
    // repeated business callback returns its cached result without another POST.
    expect((await sheet.onPay('123456')).orderID, 'order-1');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _finishAttempt(tester);
    expect(api.ids, hasLength(1));
    expect(api.balanceReads, 1);
    expect(api.amounts, ['1.000001']);
    expect(returned.single!.amount.units, BigInt.from(1000001));
    expect(find.byKey(const ValueKey('fund-payment-sheet')), findsNothing);
    final saved = await store.read('transfer:single:other');
    expect(saved!['clientOrderID'], api.ids.single);
    expect(saved.containsKey('payPassword'), false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed payment clears PIN and retries inside the original panel',
      (tester) async {
    final gate = Completer<void>();
    final api = _Api()..transferGate = gate;
    await _open(tester, api);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '12.5');
    await _requestPin(tester);
    final sheetElement =
        tester.element(find.byKey(const ValueKey('fund-payment-sheet')));
    await tester.enterText(
        find.byKey(const ValueKey('fund-pay-password')), '123456');
    await tester.pump();
    expect(find.byKey(const ValueKey('pay-state-processing')), findsOneWidget);
    gate.completeError(const FundApiException(20035, 'Wrong password'));
    await _finishAttempt(tester);
    expect(tester.element(find.byKey(const ValueKey('fund-payment-sheet'))),
        same(sheetElement));
    expect(find.byKey(const ValueKey('pay-state-enteringPassword')),
        findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('fund-pay-password')))
            .controller!
            .text,
        isEmpty);
    expect(
        await FundPendingStore(accountKey: 'test:me')
            .read('transfer:single:other'),
        isNull);
    api.transferGate = null;
    await _pay(tester, retry: true);
    expect(api.ids, hasLength(2));
    expect(api.ids[0], api.ids[1]);
    expect(api.amounts, ['12.5', '12.5']);
    expect(find.text('open'), findsOneWidget);
  });

  for (final changeServer in [false, true]) {
    testWidgets(
        '${changeServer ? 'server' : 'account'} switch after saving blocks the POST',
        (tester) async {
      await SpUtil().init();
      await DataSp.putLoginCertificate(LoginCertificate.fromJson({
        'userID': 'me',
        'chatToken': 'first-token',
        'imToken': 'first-im',
      }));
      final originalServer = Config.appAuthUrl;
      final originalConfig = Map<String, String>.from(
          DataSp.getServerConfig() ?? const <String, String>{});
      addTearDown(() async => await DataSp.putServerConfig(originalConfig));
      final api = _Api();
      final store = _GatedSaveStore();
      await _open(tester, api, store: store, currentUserID: null);
      await tester.enterText(find.byKey(const ValueKey('fund-amount')), '12.5');
      await _requestPin(tester);
      await tester.enterText(
          find.byKey(const ValueKey('fund-pay-password')), '123456');
      await tester.pump();
      expect(store.saved.isCompleted, true);
      if (changeServer) {
        await DataSp.putServerConfig({
          ...originalConfig,
          'authUrl': '$originalServer/another-server',
        });
      } else {
        await DataSp.putLoginCertificate(LoginCertificate.fromJson({
          'userID': 'other-account',
          'chatToken': 'second-token',
          'imToken': 'second-im',
        }));
      }
      store.release.complete();
      await _finishAttempt(tester);
      expect(api.ids, isEmpty);
      expect(find.byKey(const ValueKey('pay-state-enteringPassword')),
          findsOneWidget);
      await _pay(tester, retry: true);
      expect(api.ids, isEmpty);
      final saved = await store.read('transfer:single:other');
      expect(saved!['amount'], '12.5');
      expect(saved.containsKey('payPassword'), false);
    });
  }

  for (final changeServer in [false, true]) {
    testWidgets(
        '${changeServer ? 'server' : 'account'} switch during HTTP hides the old success',
        (tester) async {
      await SpUtil().init();
      final originalCertificate = LoginCertificate.fromJson({
        'userID': 'me',
        'chatToken': 'first-token',
        'imToken': 'first-im',
      });
      await DataSp.putLoginCertificate(originalCertificate);
      final originalServer = Config.appAuthUrl;
      final originalConfig = Map<String, String>.from(
          DataSp.getServerConfig() ?? const <String, String>{});
      addTearDown(() async => await DataSp.putServerConfig(originalConfig));
      final gate = Completer<void>();
      final api = _Api()..transferGate = gate;
      final returned = <FundOrder?>[];
      await _open(tester, api, currentUserID: null, onReturned: returned.add);
      await tester.enterText(find.byKey(const ValueKey('fund-amount')), '12.5');
      await _requestPin(tester);
      await tester.enterText(
          find.byKey(const ValueKey('fund-pay-password')), '123456');
      await tester.pump();
      expect(api.ids, hasLength(1));
      if (changeServer) {
        await DataSp.putServerConfig({
          ...originalConfig,
          'authUrl': '$originalServer/another-server',
        });
      } else {
        await DataSp.putLoginCertificate(LoginCertificate.fromJson({
          'userID': 'other-account',
          'chatToken': 'second-token',
          'imToken': 'second-im',
        }));
      }
      gate.complete();
      await _finishAttempt(tester);
      expect(find.byKey(const ValueKey('pay-state-success')), findsNothing);
      expect(find.byKey(const ValueKey('pay-state-enteringPassword')),
          findsOneWidget);
      expect(returned, isEmpty);
      expect(
          await FundPendingStore(accountKey: 'test:me')
              .read('transfer:single:other'),
          isNull);
      await _pay(tester, retry: true);
      expect(api.ids, hasLength(1));
      expect(returned, isEmpty);
      // Returning to the original session can acknowledge its already verified
      // result, but must never dispatch that payment again.
      await DataSp.putServerConfig(originalConfig);
      await DataSp.putLoginCertificate(originalCertificate);
      await _pay(tester, retry: true);
      expect(returned.single!.orderID, 'order-1');
      expect(api.ids, hasLength(1));
    });
  }

  testWidgets('a covered sender route never pops the newer route after success',
      (tester) async {
    final gate = Completer<void>();
    final api = _Api()..transferGate = gate;
    final returned = <FundOrder?>[];
    await _open(tester, api, onReturned: returned.add);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '12.5');
    await _requestPin(tester);
    await tester.enterText(
        find.byKey(const ValueKey('fund-pay-password')), '123456');
    await tester.pump();
    final navigator =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    unawaited(navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('newer route')))));
    await tester.pump(const Duration(milliseconds: 350));
    gate.complete();
    await _finishAttempt(tester);
    expect(find.text('newer route'), findsOneWidget);
    expect(returned, isEmpty);
    expect(api.ids, hasLength(1));
    navigator.pop();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('fund-amount')))
            .enabled,
        false);
    await tester.tap(find.byKey(const ValueKey('fund-submit')));
    await tester.pumpAndSettle();
    expect(returned.single!.orderID, 'order-1');
    expect(api.ids, hasLength(1));
    await EasyLoading.dismiss(animation: false);
    await tester.pump();
  });

  testWidgets('account switch during PIN confirmation cannot send the old form',
      (tester) async {
    await SpUtil().init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'me',
      'chatToken': 'first-token',
      'imToken': 'first-im',
    }));
    final api = _Api();
    await _open(tester, api, currentUserID: null);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '12.5');
    await _requestPin(tester);
    await tester.enterText(
        find.byKey(const ValueKey('fund-pay-password')), '12345');
    await tester.pump();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'second-account',
      'chatToken': 'second-token',
      'imToken': 'second-im',
    }));
    await tester.enterText(
        find.byKey(const ValueKey('fund-pay-password')), '123456');
    await tester.pumpAndSettle();
    expect(api.ids, isEmpty);
    await EasyLoading.dismiss(animation: false);
    await tester.pump();
    expect(
        await FundPendingStore(accountKey: 'test:me')
            .read('transfer:single:other'),
        isNull);
  });

  testWidgets(
      'resuming refreshes password state without discarding entered money',
      (tester) async {
    final api = _Api();
    final settings = _Settings();
    await _open(tester, api, settings: settings);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '12.5');
    settings.passwordSet = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(settings.checks, 2);
    expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('fund-amount')))
            .controller!
            .text,
        '12.5');
    expect(find.text('设置六位支付密码'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    for (final size in [const Size(375, 812), const Size(812, 375)]) {
      testWidgets(
          'send page respects ${dark ? 'dark' : 'light'} theme at $size with large text',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await _open(tester, _Api(), dark: dark, scale: 2, packet: true);
        expect(tester.takeException(), isNull);
      });
    }
  }

  test('pending fund requests are account scoped and refuse passwords',
      () async {
    final first = FundPendingStore(accountKey: 'server:first');
    final second = FundPendingStore(accountKey: 'server:second');
    await first.save('same-chat', {'clientOrderID': 'original', 'amount': '1'});
    expect(await second.read('same-chat'), isNull);
    await expectLater(first.save('same-chat', {'payPassword': '123456'}),
        throwsArgumentError);
  });

  test('pending store rejects replacement and clear of another order',
      () async {
    final store = FundPendingStore(accountKey: 'test:me');
    final original = {
      'clientOrderID': 'first',
      'amount': '1',
      'scene': 'single'
    };
    await store.save('scope', original);
    await store.save('scope', {...original, 'recipientName': 'updated-name'});
    await expectLater(store.save('scope', {...original, 'amount': '2'}),
        throwsA(isA<FundPendingConflict>()));
    await expectLater(
        store.save('scope', {...original, 'clientOrderID': 'second'}),
        throwsA(isA<FundPendingConflict>()));
    await expectLater(store.clear('scope', clientOrderID: 'second'),
        throwsA(isA<FundPendingConflict>()));
    expect((await store.read('scope'))!['clientOrderID'], 'first');
    await store.clear('scope', clientOrderID: 'first');
    expect(await store.read('scope'), isNull);
  });

  test('simultaneous saves retain the first original order', () async {
    final store = FundPendingStore(accountKey: 'test:me');
    final first =
        store.save('scope', {'clientOrderID': 'first', 'amount': '1'});
    final second =
        store.save('scope', {'clientOrderID': 'second', 'amount': '2'});
    await first;
    await expectLater(second, throwsA(isA<FundPendingConflict>()));
    expect((await store.read('scope'))!['clientOrderID'], 'first');
  });
}
