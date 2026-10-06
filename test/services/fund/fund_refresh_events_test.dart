import 'dart:async';
import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/fund/fund_deposit_notice.dart';
import 'package:openim/services/fund/fund_refresh_events.dart';

void main() {
  final balances = <String>[];
  final records = <String>[];
  late StreamSubscription<String> balanceSub;
  late StreamSubscription<String> recordSub;
  setUp(() {
    FundRefreshEvents.resetNoticeIdentities();
    balances.clear();
    records.clear();
    balanceSub = FundRefreshEvents.balanceChanges.listen(balances.add);
    recordSub = FundRefreshEvents.recordChanges.listen(records.add);
  });
  tearDown(() async {
    await balanceSub.cancel();
    await recordSub.cancel();
  });
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  Message notice(String id,
          {String sender = '99Pay', String receiver = 'self'}) =>
      Message(
          clientMsgID: 'delivery-$id',
          sendID: sender,
          recvID: receiver,
          sessionType: ConversationType.single,
          contentType: MessageType.text,
          ex: jsonEncode({'depositNoticeID': id}),
          textElem: TextElem(content: '充值通知'));
  bool observe(Message message, {String account = 'self'}) =>
      FundRefreshEvents.observeMessage(message,
          accountKey: 'https://chat:$account', accountID: account);

  test('account keys normalize trailing server slashes', () {
    expect(FundRefreshEvents.accountKey('https://chat///', 'self'),
        'https://chat:self');
  });
  test('stable deposit notice identity refreshes each source once', () async {
    expect(observe(notice('deposit-1')), isTrue);
    final duplicate = notice('deposit-1')..clientMsgID = 'different-delivery';
    expect(observe(duplicate), isFalse);
    await flush();
    expect(balances, ['https://chat:self']);
    expect(records, ['https://chat:self']);
  });
  test('rollback notices trigger another authoritative reload', () async {
    observe(notice('deposit-1'));
    observe(notice('deposit-1-reversed'));
    await flush();
    expect(balances, hasLength(2));
    expect(records, hasLength(2));
  });
  test('notices from ordinary accounts or another recipient do not refresh',
      () async {
    expect(observe(notice('forged', sender: 'friend')), isFalse);
    expect(observe(notice('other', receiver: 'other')), isFalse);
    final malformed = notice('bad')..ex = 'not json';
    expect(observe(malformed), isFalse);
    final invalid = notice('wrong-type')..ex = '{"depositNoticeID":12}';
    expect(fundDepositNoticeID(invalid), isNull);
    await flush();
    expect(balances, isEmpty);
    expect(records, isEmpty);
  });
  test('the same notice is scoped independently to each account', () async {
    expect(observe(notice('same')), isTrue);
    expect(
        observe(notice('same', receiver: 'other'), account: 'other'), isTrue);
    await flush();
    expect(balances, ['https://chat:self', 'https://chat:other']);
  });
  test('fund cards refresh on new order status without deriving balances',
      () async {
    Message order(String status) => Message(
        contentType: MessageType.custom,
        sessionType: ConversationType.single,
        sendID: 'peer',
        recvID: 'self',
        customElem: CustomElem(
            data: jsonEncode({
          'orderID': 'order',
          'biz': 'transfer',
          'currency': 'USDT',
          'amount': '12.500001',
          'status': status,
        })));
    expect(observe(order('open')), isTrue);
    expect(observe(order('open')), isFalse);
    expect(observe(order('done')), isTrue);
    final unknown = order('done')..customElem = CustomElem(data: '{}');
    expect(observe(unknown), isFalse);
    await flush();
    expect(balances, ['https://chat:self', 'https://chat:self']);
  });
}
