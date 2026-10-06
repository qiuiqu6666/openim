import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/search/contact_search_source.dart';
import 'package:openim/pages/fund/fund_send_page.dart';
import 'package:openim/pages/fund/internal_transfer/data/fund_transfer_recipient_source.dart';
import 'package:openim/pages/fund/internal_transfer/presentation/fund_internal_transfer_form.dart';
import 'package:openim/pages/fund/payment/fund_payment_preferences.dart';
import 'package:openim/pages/mine/settings/pages/country_code_page.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';
import 'package:openim/services/fund_api.dart';
import 'package:openim/services/fund_pending_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Settings extends StubSettingsService {
  @override
  bool get isBackendAvailable => true;
  @override
  Future<bool> hasTradePassword() async => true;
}

class _Api extends FundApi {
  final sends =
      <({String id, String recipient, String password, FundAmount amount})>[];
  final available = <FundCurrency, String>{
    FundCurrency.usdt: '12.345678',
    FundCurrency.trx: '8.010001',
    FundCurrency.bi99: '9.12',
  };
  bool uncertain = false;
  int balanceReads = 0;
  final securityChecks = <Map<String, dynamic>>[];
  final transferRequests = <Map<String, dynamic>>[];
  final recipientResolutions = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> requestData(String path,
      {String method = 'POST',
      Map<String, dynamic>? data,
      Map<String, dynamic>? queryParameters,
      bool mutation = false}) async {
    if (path == '/chat/fund/recipients/resolve') {
      recipientResolutions.add(Map<String, dynamic>.from(data!));
      return {
        'user': {
          'userID': 'im_server_receiver',
          'nickname': '真实收款人',
          'faceURL': '',
          'account': '@abcdefgh12',
        }
      };
    }
    if (path != '/chat/fund/withdrawal-security/check') {
      throw StateError('Unexpected request: $path');
    }
    final transfer = Map<String, dynamic>.from(data!['transfer'] as Map);
    securityChecks.add(transfer);
    return {
      'smsRequired': false,
      'reasons': <String>[],
      'blockedUntil': 0,
      'phoneMasked': '',
      'currency': transfer['currency'],
      'smsThreshold': '5',
      'cooldownHours': 24,
    };
  }

  @override
  Future<FundOrder> getOrderByClient(String clientOrderID) async =>
      throw const FundApiException(20032, 'Order not found');

  @override
  Future<List<FundBalance>> fetchBalances() async {
    balanceReads++;
    return [
      for (final currency in FundCurrency.values)
        FundBalance(
            currency: currency,
            available: FundAmount.parse(available[currency]!, currency),
            frozen: FundAmount.parse('5', currency))
    ];
  }

  @override
  Future<FundOrder> sendTransfer({
    required String clientOrderID,
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
    required String payPassword,
  }) async {
    sends.add((
      id: clientOrderID,
      recipient: recvID,
      password: payPassword,
      amount: amount
    ));
    transferRequests.add({
      'clientOrderID': clientOrderID,
      'scene': scene.name,
      'currency': amount.currency.code,
      'amount': amount.decimal,
      'recvID': recvID,
      if (remark != null) 'remark': remark,
      if (recipientType != null) 'recipientType': recipientType,
      if (recipient != null) 'recipient': recipient,
      if (areaCode != null) 'areaCode': areaCode,
      if (verifyChallengeID != null) 'verifyChallengeID': verifyChallengeID,
      if (verifyCode != null) 'verifyCode': verifyCode,
    });
    if (uncertain) {
      throw const FundApiException(-1, 'timeout', isUncertain: true);
    }
    return FundOrder(
        orderID: 'transfer-order',
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
}

class _Search extends ContactSearchSource {
  final queries = <({String keyword, int? way})>[];
  final uidQueries = <String>[];
  final usersToReturn = <UserFullInfo>[
    UserFullInfo(
        userID: 'im_alice_real',
        email: 'alice@example.com',
        account: '@abcdefgh12',
        nickname: 'Alice'),
    UserFullInfo(
        userID: 'im_bob_real',
        email: 'bob@example.com',
        account: '@otheruser1',
        nickname: 'Bob'),
  ];
  Completer<List<UserFullInfo>?>? gate;

  Future<List<UserFullInfo>?> loadUID(String userID) async {
    uidQueries.add(userID);
    return usersToReturn;
  }

  @override
  Future<List<UserFullInfo>?> users(String keyword, int page,
      {int? way}) async {
    queries.add((keyword: keyword, way: way));
    return gate == null ? usersToReturn : await gate!.future;
  }
}

class _Session {
  String owner = 'me', token = 'test-chat-token';
  String server = Config.appAuthUrl;
  FundTransferRecipientSource source(_Search search, {FundApi? api}) =>
      FundTransferRecipientSource(
          api: api,
          source: api == null ? search : null,
          uidLoader: search.loadUID,
          owner: () => owner,
          tokenProvider: () => token,
          serverProvider: () => server);
}

Finder _key(String name) => find.byKey(ValueKey(name));
Finder get _recipient => _key('internal-transfer-recipient');
Finder get _amount => _key('fund-amount');
Finder get _submit => _key('internal-transfer-submit');
Finder get _payment => _key('fund-payment-sheet');

Future<void> _open(
    WidgetTester tester, _Api api, _Search search, _Session session,
    {FundCurrency currency = FundCurrency.usdt,
    FundPendingStore? store,
    bool dark = false,
    bool useFundResolver = false,
    FundTransferRecipient? pickedFriend,
    Future<String?> Function(BuildContext, String)? areaCodePicker,
    ValueChanged<FundOrder?>? onReturned}) async {
  await tester.pumpWidget(MaterialApp(
      key: UniqueKey(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      builder: EasyLoading.init(builder: (context, child) {
        ScreenUtil.init(context,
            designSize: const Size(390, 844), minTextAdapt: true);
        return child!;
      }),
      home: Builder(
          builder: (context) => Scaffold(
                  body: TextButton(
                child: const Text('open'),
                onPressed: () async {
                  final order = await Navigator.of(context).push<FundOrder>(
                      MaterialPageRoute(
                          builder: (_) => FundSendPage(
                              isRedPacket: false,
                              internalWithdrawal: true,
                              initialCurrency: currency,
                              currentUserID: 'me',
                              api: api,
                              settingsService: _Settings(),
                              pendingStore: store ??
                                  FundPendingStore(accountKey: 'test:me'),
                              transferRecipientSource: session.source(search,
                                  api: useFundResolver ? api : null),
                              transferAreaCodePicker: areaCodePicker,
                              transferFriendPicker: (_) async =>
                                  pickedFriend)));
                  onReturned?.call(order);
                },
              )))));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(_key('internal-transfer-form'), findsOneWidget);
}

Future<void> _selectType(
    WidgetTester tester, FundTransferAccountType type) async {
  if (tester
          .widget<FundInternalTransferForm>(
              find.byType(FundInternalTransferForm))
          .accountType ==
      type) {
    return;
  }
  await tester.ensureVisible(_key('internal-transfer-account-type'));
  await tester.tap(_key('internal-transfer-account-type'));
  await tester.pumpAndSettle();
  await tester.tap(_key('internal-transfer-type-${type.name}'));
  await tester.pumpAndSettle();
}

Future<void> _edit(WidgetTester tester,
    {String recipient = 'alice@example.com',
    String amount = '1',
    FundTransferAccountType type = FundTransferAccountType.email}) async {
  await _selectType(tester, type);
  await tester.ensureVisible(_recipient);
  await tester.enterText(_recipient, recipient);
  await tester.ensureVisible(_amount);
  await tester.enterText(_amount, amount);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> _requestPin(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(_submit);
  await tester.pump();
  await tester.tap(_submit);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _enterPin(WidgetTester tester) async {
  expect(_payment, findsOneWidget);
  await tester.enterText(_key('fund-pay-password'), '123456');
  await tester.pump();
}

Future<void> _finishSuccess(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1000));
  await tester.pumpAndSettle();
  await EasyLoading.dismiss(animation: false);
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => EasyLoading.dismiss(animation: false));

  testWidgets('fund phone resolver descriptor binds internal check and payment',
      (tester) async {
    final api = _Api();
    final search = _Search();
    await _open(tester, api, search, _Session(),
        useFundResolver: true, areaCodePicker: (_, __) async => '+1');
    await _selectType(tester, FundTransferAccountType.phone);
    await tester.tap(_key('internal-transfer-area-code'));
    await tester.pumpAndSettle();
    await _edit(tester,
        recipient: '+1 (202) 555-0100',
        amount: '1.23',
        type: FundTransferAccountType.phone);
    await _requestPin(tester);
    expect(api.recipientResolutions.single, {
      'recipientType': 'phone',
      'recipient': '2025550100',
      'areaCode': '+1',
    });
    expect(find.text('收款人：真实收款人'), findsOneWidget);
    expect(search.queries, isEmpty);
    expect(api.securityChecks.single['scene'], 'internal');
    expect(api.securityChecks.single['recipient'], '2025550100');
    expect(api.securityChecks.single['recipientType'], 'phone');
    expect(api.securityChecks.single['areaCode'], '+1');
    expect(api.securityChecks.single['recvID'], 'im_server_receiver');
    expect(api.sends, isEmpty);
    await _enterPin(tester);
    expect(api.transferRequests.single, api.securityChecks.single);
    expect(api.sends.single.recipient, 'im_server_receiver');
    expect(api.sends.single.amount.decimal, '1.23');
    await _finishSuccess(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('99Chat ID is the default and pays the resolved IM recipient',
      (tester) async {
    final api = _Api();
    final search = _Search();
    await _open(tester, api, search, _Session(), useFundResolver: true);
    final form = tester.widget<FundInternalTransferForm>(
        find.byType(FundInternalTransferForm));
    expect(form.accountType, FundTransferAccountType.account);
    expect(find.text('请填写收款人99号'), findsOneWidget);
    expect(_key('internal-transfer-area-code'), findsNothing);

    await tester.tap(_key('internal-transfer-account-type'));
    await tester.pumpAndSettle();
    final sheet =
        tester.widget<CupertinoActionSheet>(find.byType(CupertinoActionSheet));
    expect(sheet.actions, hasLength(3));
    expect(find.text('选择账号类型'), findsOneWidget);
    expect(tester.getTopLeft(_key('internal-transfer-type-account')).dy,
        lessThan(tester.getTopLeft(_key('internal-transfer-type-email')).dy));
    expect(tester.getTopLeft(_key('internal-transfer-type-email')).dy,
        lessThan(tester.getTopLeft(_key('internal-transfer-type-phone')).dy));
    expect(_key('internal-transfer-type-uid'), findsNothing);
    expect(
        tester
            .widget<Semantics>(_key('internal-transfer-type-account'))
            .properties
            .selected,
        isTrue);
    expect(find.text('当前选择'), findsOneWidget);
    await tester.tap(_key('internal-transfer-type-account'));
    await tester.pumpAndSettle();

    await tester.tap(_key('internal-transfer-help'));
    await tester.pumpAndSettle();
    final help = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect((help.content! as Text).data, contains('99号'));
    expect((help.content! as Text).data, isNot(contains('UID')));
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    await _edit(tester,
        recipient: 'abcdefgh12', type: FundTransferAccountType.account);
    await _requestPin(tester);
    expect(api.recipientResolutions.single,
        {'recipientType': 'account', 'recipient': '@abcdefgh12'});
    expect(find.text('收款人：真实收款人'), findsOneWidget);
    expect(api.securityChecks.single['recipientType'], 'account');
    expect(api.securityChecks.single['recipient'], '@abcdefgh12');
    expect(api.securityChecks.single['recvID'], 'im_server_receiver');
    expect(search.uidQueries, isEmpty);
    expect(search.queries, isEmpty);
    expect(api.sends, isEmpty);
    await _enterPin(tester);
    expect(api.transferRequests.single, api.securityChecks.single);
    expect(api.sends.single.recipient, 'im_server_receiver');
    await _finishSuccess(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone defaults to +86 and chosen prefix resolves that recipient',
      (tester) async {
    final api = _Api();
    final search = _Search()
      ..usersToReturn.clear()
      ..usersToReturn.addAll([
        UserFullInfo(
            userID: 'im_alice_real',
            phoneNumber: '13800138000',
            areaCode: '+86',
            nickname: 'Alice'),
        UserFullInfo(
            userID: 'im_bob_real',
            phoneNumber: '13800138000',
            areaCode: '+1',
            nickname: 'Bob'),
      ]);
    final pickerCodes = <String>[];
    await _open(tester, api, search, _Session(),
        areaCodePicker: (_, selected) async {
      pickerCodes.add(selected);
      return '+1';
    });
    await _selectType(tester, FundTransferAccountType.phone);
    expect(find.text('+86'), findsOneWidget);
    await tester.enterText(_recipient, '13800138000');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(find.text('收款人：Alice'), findsOneWidget);
    await tester.enterText(_amount, '1.23');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(_key('internal-transfer-area-code'));
    await tester.pumpAndSettle();
    expect(pickerCodes, ['+86']);
    expect(find.text('+1'), findsOneWidget);
    expect(find.text('收款人：Alice'), findsNothing);
    expect(tester.widget<TextFormField>(_recipient).controller!.text,
        '13800138000');
    expect(tester.widget<TextFormField>(_amount).controller!.text, '1.23');
    await _requestPin(tester);
    expect(search.queries,
        [(keyword: '13800138000', way: 2), (keyword: '13800138000', way: 2)]);
    expect(search.uidQueries, isEmpty);
    await _enterPin(tester);
    expect(api.sends.single.recipient, 'im_bob_real');
    expect(api.sends.single.amount.decimal, '1.23');
    await _finishSuccess(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismissing the area picker keeps phone and amount drafts',
      (tester) async {
    final api = _Api();
    final search = _Search();
    final pickerCodes = <String>[];
    await _open(tester, api, search, _Session(),
        areaCodePicker: (_, selected) async {
      pickerCodes.add(selected);
      return null;
    });
    await _edit(tester,
        recipient: '13800138000',
        amount: '1.23',
        type: FundTransferAccountType.phone);
    await tester.tap(_key('internal-transfer-area-code'));
    await tester.pumpAndSettle();
    expect(pickerCodes, ['+86']);
    expect(find.text('+86'), findsOneWidget);
    expect(tester.widget<TextFormField>(_recipient).controller!.text,
        '13800138000');
    expect(tester.widget<TextFormField>(_amount).controller!.text, '1.23');
    expect(search.queries, isEmpty);
    expect(search.uidQueries, isEmpty);
    expect(api.sends, isEmpty);
  });

  testWidgets(
      'phone prefix opens the existing country selector and applies code',
      (tester) async {
    final api = _Api();
    final search = _Search();
    await _open(tester, api, search, _Session());
    await _edit(tester,
        recipient: '13800138000',
        amount: '1.23',
        type: FundTransferAccountType.phone);
    final prefix = _key('internal-transfer-area-code');
    await tester.tap(prefix);
    await tester.pumpAndSettle();
    expect(find.byType(CountryCodePage), findsOneWidget);
    expect(
        tester
            .widget<CountryCodePage>(find.byType(CountryCodePage))
            .selectedCode,
        '+86');
    Navigator.of(tester.element(find.byType(CountryCodePage))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(CountryCodePage), findsNothing);
    expect(find.text('+86'), findsOneWidget);
    await tester.tap(prefix);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(CountryCodePage), matching: find.byType(TextField)),
        'United States');
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == 'United States'));
    await tester.pumpAndSettle();
    expect(find.byType(CountryCodePage), findsNothing);
    expect(find.text('+1'), findsOneWidget);
    expect(tester.widget<TextFormField>(_recipient).controller!.text,
        '13800138000');
    expect(tester.widget<TextFormField>(_amount).controller!.text, '1.23');
    expect(search.queries, isEmpty);
    expect(search.uidQueries, isEmpty);
    expect(api.sends, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final currency in FundCurrency.values) {
    testWidgets(
        '${currency.code} keeps the selected currency and exact all amount',
        (tester) async {
      final api = _Api();
      final search = _Search();
      final session = _Session();
      final display = currency == FundCurrency.bi99 ? '99币' : currency.code;
      await FundPaymentPreferences(
              accountID: 'me', serverURL: Config.appAuthUrl)
          .save(currency == FundCurrency.trx
              ? FundCurrency.usdt
              : FundCurrency.trx);
      FundOrder? returned;
      await _open(tester, api, search, session,
          currency: currency, onReturned: (order) => returned = order);
      expect(find.text('提现 $display'), findsOneWidget);
      await _selectType(tester, FundTransferAccountType.email);
      await tester.enterText(_recipient, 'alice@example.com');
      await tester.ensureVisible(_key('internal-transfer-all'));
      await tester.tap(_key('internal-transfer-all'));
      await tester.pump();
      expect(tester.widget<TextFormField>(_amount).controller!.text,
          api.available[currency]);
      final available = FundAmount.parse(api.available[currency]!, currency);
      expect(
          find.text('可用：${available.displayDecimal} $display'), findsOneWidget);
      expect(find.text('0.00 $display'), findsOneWidget);
      await _requestPin(tester);
      expect(search.queries.single, (keyword: 'alice@example.com', way: 3));
      await _enterPin(tester);
      expect(api.sends.single.amount, available);
      expect(api.sends.single.recipient, 'im_alice_real');
      expect(api.sends.single.password, '123456');
      expect(find.text('支付成功'), findsOneWidget);
      expect(_key('fund-payment-keypad'), findsNothing);
      await _finishSuccess(tester);
      expect(returned?.recvID, 'im_alice_real');
      expect(returned?.amount, available);
      expect(_payment, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'repeated account-type callbacks open one sheet and apply the choice',
      (tester) async {
    final api = _Api();
    final search = _Search();
    await _open(tester, api, search, _Session());
    await tester.enterText(_recipient, 'abcdefgh12');
    await tester.enterText(_amount, '1.23');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final onTap =
        tester.widget<InkWell>(_key('internal-transfer-account-type')).onTap!;
    onTap();
    onTap();
    await tester.pumpAndSettle();
    expect(
        find.byType(CupertinoActionSheet, skipOffstage: false), findsOneWidget);
    expect(
        find.byKey(const ValueKey('internal-transfer-type-phone'),
            skipOffstage: false),
        findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(
        find.byType(CupertinoActionSheet, skipOffstage: false), findsNothing);
    expect(tester.widget<TextFormField>(_recipient).controller!.text,
        'abcdefgh12');
    expect(tester.widget<TextFormField>(_amount).controller!.text, '1.23');
    expect(
        tester
            .widget<FundInternalTransferForm>(
                find.byType(FundInternalTransferForm))
            .accountType,
        FundTransferAccountType.account);
    onTap();
    await tester.pumpAndSettle();
    await tester.tap(_key('internal-transfer-type-phone'));
    await tester.pumpAndSettle();
    expect(
        find.byType(CupertinoActionSheet, skipOffstage: false), findsNothing);
    final recipientInput = tester.widget<TextFormField>(_recipient);
    expect(recipientInput.controller!.text, isEmpty);
    expect(tester.widget<TextFormField>(_amount).controller!.text, '1.23');
    final field = tester.widget<TextField>(
        find.descendant(of: _recipient, matching: find.byType(TextField)));
    expect(field.keyboardType, TextInputType.phone);
    expect(find.text('请填写收款人手机号'), findsOneWidget);
    expect(search.queries, isEmpty);
    expect(api.sends, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'friend without public account keeps input empty and pays its real IM ID',
      (tester) async {
    for (final nickname in ['Alice', '']) {
      final api = _Api();
      final search = _Search();
      await _open(tester, api, search, _Session(),
          pickedFriend: FundTransferRecipient(
              userID: 'im_friend_without_account', nickname: nickname));
      await tester.tap(_key('internal-transfer-contacts'));
      await tester.pumpAndSettle();
      expect(
          tester.widget<TextFormField>(_recipient).controller!.text, isEmpty);
      expect(find.text('im_friend_without_account'), findsNothing);
      expect(find.text('收款人：${nickname.isEmpty ? '收款人' : nickname}'),
          findsOneWidget);
      await tester.ensureVisible(_amount);
      await tester.enterText(_amount, '1.23');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(_submit).onPressed, isNotNull);
      await _requestPin(tester);
      await _enterPin(tester);
      expect(api.sends.single.recipient, 'im_friend_without_account');
      expect(api.sends.single.amount.decimal, '1.23');
      expect(search.queries, isEmpty);
      await _finishSuccess(tester);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('an edited selected friend is cleared and email is resolved anew',
      (tester) async {
    final api = _Api();
    final search = _Search();
    await _open(tester, api, search, _Session(),
        pickedFriend: const FundTransferRecipient(
            userID: 'im_alice_real',
            nickname: 'Alice',
            account: '@abcdefgh12'));
    await tester.tap(_key('internal-transfer-contacts'));
    await tester.pumpAndSettle();
    expect(find.text('收款人：Alice'), findsOneWidget);
    await tester.enterText(_recipient, '@otheruser1');
    await tester.pump();
    expect(find.text('收款人：Alice'), findsNothing);
    await tester.tap(_key('internal-transfer-account-type'));
    await tester.pumpAndSettle();
    await tester.tap(_key('internal-transfer-type-email'));
    await tester.pumpAndSettle();
    await _edit(tester, recipient: 'bob@example.com', amount: '1.23');
    await _requestPin(tester);
    await _enterPin(tester);
    expect(search.queries.single, (keyword: 'bob@example.com', way: 3));
    expect(api.sends.single.recipient, 'im_bob_real');
    expect(api.sends.single.amount.decimal, '1.23');
    await _finishSuccess(tester);
  });

  for (final entry in [
    (currency: FundCurrency.usdt, amount: '12.345679'),
    (currency: FundCurrency.usdt, amount: '0.0000001'),
    (currency: FundCurrency.trx, amount: '1.1234567'),
    (currency: FundCurrency.bi99, amount: '9.13'),
    (currency: FundCurrency.bi99, amount: '0.001'),
    (currency: FundCurrency.usdt, amount: '0'),
  ]) {
    testWidgets(
        '${entry.currency.code} invalid or overbalance ${entry.amount} blocks payment',
        (tester) async {
      final api = _Api();
      final search = _Search();
      await _open(tester, api, search, _Session(), currency: entry.currency);
      await _edit(tester, amount: entry.amount);
      expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
      expect(search.queries, isEmpty);
      expect(api.sends, isEmpty);
      expect(_payment, findsNothing);
    });
  }

  for (final field in ['owner', 'token']) {
    testWidgets(
        'late recipient resolution after $field changes never opens PIN or sends',
        (tester) async {
      final api = _Api();
      final search = _Search()..gate = Completer<List<UserFullInfo>?>();
      final session = _Session();
      await _open(tester, api, search, session);
      await _edit(tester);
      await _requestPin(tester);
      expect(search.queries.length, 1);
      if (field == 'owner') {
        session.owner = 'another-sender';
      } else {
        session.token = 'renewed-chat-token';
      }
      search.gate!.complete(search.usersToReturn);
      await tester.pumpAndSettle();
      expect(_payment, findsNothing);
      expect(api.sends, isEmpty);
      expect(find.textContaining('登录状态已变更'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'recipient Next restores a pending payment even when available is zero',
      (tester) async {
    final api = _Api()..available[FundCurrency.usdt] = '0';
    final search = _Search();
    final store = FundPendingStore(accountKey: 'test:me');
    final originalID = FundApi.createClientOrderID();
    await store.save('transfer:single:im_alice_real', {
      'clientOrderID': originalID,
      'scene': 'single',
      'currency': 'USDT',
      'amount': '1.23',
      'recvID': 'im_alice_real',
      'recipientName': 'Alice',
      'remark': '',
    });
    await _open(tester, api, search, _Session(), store: store);
    expect(tester.widget<TextFormField>(_amount).controller!.text, isEmpty);
    expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
    await _selectType(tester, FundTransferAccountType.email);
    await tester.enterText(_recipient, 'alice@example.com');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(search.queries.single, (keyword: 'alice@example.com', way: 3));
    expect(tester.widget<TextFormField>(_amount).controller!.text, '1.23');
    expect(find.text('可用：0.00 USDT'), findsOneWidget);
    expect(find.textContaining('已恢复待确认转账'), findsOneWidget);
    expect(find.text('继续支付'), findsOneWidget);
    expect(tester.widget<FilledButton>(_submit).onPressed, isNotNull);
    expect(_payment, findsNothing);
    expect(api.sends, isEmpty);
    await _requestPin(tester);
    await _enterPin(tester);
    expect(api.sends.single.id, originalID);
    expect(api.sends.single.recipient, 'im_alice_real');
    expect(api.sends.single.amount.decimal, '1.23');
    expect(api.sends.single.amount.currency, FundCurrency.usdt);
    await _finishSuccess(tester);
    expect(await store.read('transfer:single:im_alice_real'), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'uncertain payment restores recipient amount currency and original order ID',
      (tester) async {
    final api = _Api()..uncertain = true;
    final search = _Search();
    final session = _Session();
    final store = FundPendingStore(accountKey: 'test:me');
    await _open(tester, api, search, session, store: store);
    await _edit(tester, amount: '1.234567');
    await _requestPin(tester);
    await _enterPin(tester);
    await tester.pumpAndSettle();
    expect(api.sends.length, 1);
    final firstID = api.sends.single.id;
    final pending = await store.read('transfer:single:im_alice_real');
    expect(pending?['clientOrderID'], firstID);
    expect(pending?['recvID'], 'im_alice_real');
    expect(pending?['currency'], 'USDT');
    expect(pending?['amount'], '1.234567');
    expect(pending?.containsKey('payPassword'), isFalse);
    await tester.tap(_key('fund-cancel-pay'));
    await tester.pumpAndSettle();
    await tester.tap(_key('fund-close'));
    await tester.pumpAndSettle();
    api.uncertain = false;
    await _open(tester, api, search, session,
        currency: FundCurrency.trx, store: store);
    await _edit(tester, amount: '7');
    await _requestPin(tester);
    expect(_payment, findsNothing);
    expect(find.textContaining('已恢复待确认转账'), findsOneWidget);
    expect(tester.widget<TextFormField>(_amount).controller!.text, '1.234567');
    expect(find.text('提现 USDT'), findsOneWidget);
    expect(find.text('收款人：Alice'), findsOneWidget);
    expect(tester.widget<TextFormField>(_recipient).enabled, isFalse);
    expect(api.sends.length, 1);
    await _requestPin(tester);
    await _enterPin(tester);
    expect(api.sends.length, 2);
    expect(api.sends.last.id, firstID);
    expect(api.sends.last.recipient, 'im_alice_real');
    expect(api.sends.last.amount.currency, FundCurrency.usdt);
    expect(api.sends.last.amount.decimal, '1.234567');
    await _finishSuccess(tester);
    expect(await store.read('transfer:single:im_alice_real'), isNull);
  });
}
