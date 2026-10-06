import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/fund/fund_send_page.dart';
import 'package:openim/pages/fund/widgets/fund_send_form.dart';
import 'package:openim/pages/mine/settings/settings_service.dart';
import 'package:openim/services/fund_api.dart';
import 'package:openim/services/fund_pending_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Settings extends StubSettingsService {
  @override
  Future<bool> hasTradePassword() async => true;
}

class _Api extends FundApi {
  final packets = <Map<String, Object?>>[];

  @override
  Future<List<FundBalance>> fetchBalances() async => [
        for (final currency in FundCurrency.values)
          FundBalance(
            currency: currency,
            available: FundAmount.parse('100', currency),
            frozen: FundAmount.zero(currency),
          ),
      ];

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
    packets.add({
      'clientOrderID': clientOrderID,
      'scene': scene,
      'biz': biz,
      'recvID': recvID,
      'groupID': groupID,
    });
    return FundOrder(
      orderID: 'confirmed',
      clientOrderID: clientOrderID,
      scene: scene,
      biz: biz.code,
      currency: currency,
      amount: amount!,
      status: 'done',
      recvID: recvID!,
      groupID: groupID!,
    );
  }
}

Future<void> _open(
  WidgetTester tester,
  _Api api, {
  bool dark = false,
  FundPacketBiz? initialPacketBiz = FundPacketBiz.exclusive,
  String recipient = 'target',
  FundPendingStore? store,
}) async {
  await tester.pumpWidget(MaterialApp(
    key: UniqueKey(),
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
    builder: EasyLoading.init(),
    home: Builder(
        builder: (context) => Scaffold(
                body: TextButton(
              child: const Text('open'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FundSendPage(
                  isRedPacket: true,
                  groupID: 'group',
                  userID: recipient,
                  recipientName: '指定成员',
                  initialPacketBiz: initialPacketBiz,
                  currentUserID: 'me',
                  settingsService: _Settings(),
                  api: api,
                  pendingStore:
                      store ?? FundPendingStore(accountKey: 'test:me'),
                ),
              )),
            ))),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

FundSendForm _form(WidgetTester tester) =>
    tester.widget<FundSendForm>(find.byType(FundSendForm));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => EasyLoading.dismiss(animation: false));

  for (final dark in [false, true]) {
    testWidgets('exclusive form preselects the member dark=$dark',
        (tester) async {
      final api = _Api();
      await _open(tester, api, dark: dark);
      final form = _form(tester);
      expect(form.biz, FundPacketBiz.exclusive);
      expect(form.isGroup, isTrue);
      expect(form.isMultiple, isFalse);
      expect(form.recipientID, 'target');
      expect(form.recipientName, '指定成员');
      expect(find.byKey(const ValueKey('fund-count')), findsNothing);
      expect(api.packets, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'selected group recipient is sent only after password confirmation',
      (tester) async {
    final api = _Api();
    await _open(tester, api);
    await tester.enterText(find.byKey(const ValueKey('fund-amount')), '1');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('fund-submit')));
    await tester.tap(find.byKey(const ValueKey('fund-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(api.packets, isEmpty);
    await tester.enterText(
        find.byKey(const ValueKey('fund-pay-password')), '123456');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    await EasyLoading.dismiss(animation: false);
    await tester.pump();
    expect(api.packets.single, containsPair('scene', FundScene.group));
    expect(api.packets.single, containsPair('biz', FundPacketBiz.exclusive));
    expect(api.packets.single, containsPair('recvID', 'target'));
    expect(api.packets.single, containsPair('groupID', 'group'));
    expect(find.byType(FundSendPage), findsNothing);
  });

  testWidgets(
      'ordinary group packet preserves its default and clears recipient',
      (tester) async {
    await _open(tester, _Api(), initialPacketBiz: null);
    final form = _form(tester);
    expect(form.biz, FundPacketBiz.lucky);
    expect(form.isMultiple, isTrue);
    expect(form.recipientID, isNull);
    expect(form.recipientName, isNull);
  });

  testWidgets('self cannot become the exclusive form recipient',
      (tester) async {
    await _open(tester, _Api(), recipient: 'me');
    expect(_form(tester).recipientID, isNull);
    expect(_form(tester).recipientName, isNull);
  });

  for (final pending in [
    {'biz': 'packet_exclusive', 'recvID': 'other-target'},
    {'biz': 'packet_lucky', 'shareCount': 1},
  ]) {
    testWidgets('pending $pending cannot replace the shortcut member or type',
        (tester) async {
      final store = FundPendingStore(accountKey: 'test:me');
      final request = <String, dynamic>{
        'clientOrderID': 'original-order',
        'scene': 'group',
        'groupID': 'group',
        'amount': '1',
        'currency': 'USDT',
        ...pending,
      };
      await store.save('packet:group:group', request);
      final api = _Api();
      await _open(tester, api, store: store);
      final form = _form(tester);
      expect(form.biz, FundPacketBiz.exclusive);
      expect(form.recipientID, 'target');
      expect(form.isLocked, isTrue);
      expect(form.error, '群内已有其他红包待确认，请返回原红包入口重试');
      form.onSubmit();
      await tester.pumpAndSettle();
      expect(api.packets, isEmpty);
      expect(await store.read('packet:group:group'), request);
    });
  }

  testWidgets('matching pending exclusive payment retains its original order',
      (tester) async {
    final store = FundPendingStore(accountKey: 'test:me');
    await store.save('packet:group:group', {
      'clientOrderID': 'original-order',
      'scene': 'group',
      'groupID': 'group',
      'biz': 'packet_exclusive',
      'recvID': 'target',
      'recipientName': '指定成员',
      'amount': '2',
      'currency': 'USDT',
    });
    final api = _Api();
    await _open(tester, api, store: store);
    final form = _form(tester);
    expect(form.hasPending, isTrue);
    expect(form.biz, FundPacketBiz.exclusive);
    expect(form.recipientID, 'target');
    expect(form.amount.text, '2');
    expect(form.error, isNull);
    expect(api.packets, isEmpty);
  });
}
