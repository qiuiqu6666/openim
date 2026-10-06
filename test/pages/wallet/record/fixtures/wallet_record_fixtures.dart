import 'package:openim/pages/wallet/record/wallet_record_models.dart';

/// Deliberately unordered, test-only ledger data. Types do not determine
/// direction, and no fixture invents an account balance or merchant identity.
WalletRecordDto walletRecordFixture({
  String id = 'fixture',
  String time = '2026-10-06 11:22:33',
  bool income = true,
  WalletRecordType type = WalletRecordType.transfer,
  WalletRecordStatus status = WalletRecordStatus.success,
  String coin = '99',
  String amount = '28.5000',
  String title = '转账',
}) =>
    WalletRecordDto(
      id: id,
      type: type,
      status: status,
      title: title,
      subTitle: '',
      amount: amount,
      coin: coin,
      income: income,
      network: '',
      fee: '',
      payer: '',
      payee: '',
      addr: '',
      hash: '',
      block: '',
      time: time,
      orderNo: id,
      memo: '',
    );

final walletRecordFixtures = <WalletRecordDto>[
  walletRecordFixture(
    id: 'old-january',
    time: '2025-01-31 12:59:59',
    coin: '元',
    amount: '+50.00',
  ),
  walletRecordFixture(
    id: 'january-older',
    time: '2026-01-02 10:00:00',
    type: WalletRecordType.redPacket,
    status: WalletRecordStatus.pending,
    coin: 'USDT',
    amount: '-1.250000',
    title: '红包',
  ),
  walletRecordFixture(
    id: 'october-outgoing',
    time: '2026-10-05 07:05:03',
    income: false,
    type: WalletRecordType.receive,
    amount: '+8.00',
    title: '收款',
  ),
  walletRecordFixture(
    id: 'unknown-time',
    time: '',
    type: WalletRecordType.swap,
    coin: 'USDT',
    amount: '-9.0000',
    title: '兑换',
  ),
  walletRecordFixture(
    id: 'january-newer',
    time: '2026-01-19 16:18:06',
    income: false,
    type: WalletRecordType.swap,
    coin: 'USDT',
    amount: '-12.345678',
    title: '兑换',
  ),
  walletRecordFixture(
    id: 'october-incoming',
    amount: '-28.5000',
  ),
  walletRecordFixture(
    id: 'failed-outgoing',
    time: '2025-12-03 08:30:03',
    income: false,
    status: WalletRecordStatus.failed,
    coin: 'USDT',
    amount: '+8.010000',
  ),
];

final walletRecordLongFixture = walletRecordFixture(
  id: 'long-amount',
  amount: '-123,456,789,012,345,678.123456789000',
  coin: 'USDT',
  title: 'Very long international transfer description 超长转账说明',
);
