import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/fund/fund_card_state_cache.dart';
import 'package:openim/services/fund_models.dart';
import 'package:openim/pages/chat/fund/fund_card_recipient.dart';

void main() {
  FundCardOrderIdentity identity(String id, {String amount = '1'}) => (
        orderID: id,
        biz: 'packet_normal',
        currency: FundCurrency.usdt,
        amount: FundAmount.parse(amount, FundCurrency.usdt),
        remark: '',
      );
  test('display cache stays bounded and clearing advances session epoch', () {
    final cache = FundCardStateCache(maxEntries: 2);
    for (final id in ['one', 'two', 'three']) {
      cache.remember(id,
          identity: identity(id),
          status: 'done',
          claimedByMe: true,
          confirmedAt: DateTime(2026));
    }
    expect(cache.read('one'), isNull);
    expect(cache.read('two')?.status, 'done');
    expect(cache.read('three')?.claimedByMe, isTrue);
    final epoch = cache.epoch;
    cache.clear();
    expect(cache.epoch, epoch + 1);
    expect(cache.read('three'), isNull);
  });
  test('later incomplete observations cannot unclaim a completed order', () {
    final cache = FundCardStateCache();
    cache.remember('key',
        identity: identity('id'),
        status: 'done',
        claimedByMe: true,
        confirmedAt: DateTime(2026));
    final revision = cache.read('key')!.revision;
    cache.remember('key',
        identity: identity('id'),
        status: 'open',
        claimedByMe: false,
        confirmedAt: DateTime(2026, 1, 2));
    expect(cache.read('key')!.status, 'done');
    expect(cache.read('key')!.claimedByMe, isTrue);
    expect(cache.read('key')!.revision, greaterThan(revision));
    cache.remember('key',
        identity: identity('id'),
        status: 'refunded',
        claimedByMe: false,
        confirmedAt: DateTime(2026, 1, 3));
    expect(cache.read('key')!.status, 'refunded');
  });
  test('different financial identity cannot inherit a cached claim', () {
    final cache = FundCardStateCache();
    cache.remember('key',
        identity: identity('id'),
        status: 'done',
        claimedByMe: true,
        confirmedAt: DateTime(2026));
    cache.remember('key',
        identity: identity('id', amount: '2'),
        status: 'open',
        claimedByMe: false,
        confirmedAt: DateTime(2026));
    expect(cache.read('key')!.claimedByMe, isFalse);
    expect(cache.read('key')!.status, 'open');
  });
  test('packet count survives incomplete reads and recipient enrichment', () {
    final cache = FundCardStateCache();
    cache.remember('key',
        identity: identity('id'),
        status: 'open',
        claimedByMe: false,
        packetCount: 5,
        recipientID: 'friend',
        confirmedAt: DateTime(2026));
    cache.enrichRecipient(
        'key', const FundCardRecipient(userID: 'friend', name: '小林'));
    expect(cache.read('key')!.packetCount, 5);
    cache.remember('key',
        identity: identity('id'),
        status: 'open',
        claimedByMe: false,
        recipientID: 'friend',
        confirmedAt: DateTime(2026));
    expect(cache.read('key')!.packetCount, 5);
    cache.remember('key',
        identity: identity('id', amount: '2'),
        status: 'open',
        claimedByMe: false,
        confirmedAt: DateTime(2026));
    expect(cache.read('key')!.packetCount, isNull);
  });
}
