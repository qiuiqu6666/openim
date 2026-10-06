import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/fund/payment/fund_payment_preferences.dart';
import 'package:openim/services/fund_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

FundPaymentPreferences _store(
        {String account = 'me', String server = 'server'}) =>
    FundPaymentPreferences(accountID: account, serverURL: server);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('confirmed choice survives a new store and only currency is stored',
      () async {
    expect(await _store().read(), isNull);
    await _store().save(FundCurrency.trx);
    expect(await _store().read(), FundCurrency.trx);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getKeys(), hasLength(1));
    expect(preferences.get(preferences.getKeys().single), 'TRX');
    for (final currency in FundCurrency.values) {
      await _store().save(currency);
      expect(await _store().read(), currency);
    }
  });

  test('account and server scopes do not collide or leak choices', () async {
    await _store().save(FundCurrency.trx);
    expect(await _store(account: 'other').read(), isNull);
    expect(await _store(server: 'other-server').read(), isNull);
    await _store(account: 'other').save(FundCurrency.bi99);
    expect(await _store().read(), FundCurrency.trx);
    expect(await _store(account: 'other').read(), FundCurrency.bi99);
    await _store(server: 'server:a', account: 'b').save(FundCurrency.bi99);
    expect(await _store(server: 'server', account: 'a:b').read(), isNull);
  });

  test('unknown or corrupt stored values are ignored', () async {
    await _store().save(FundCurrency.trx);
    final preferences = await SharedPreferences.getInstance();
    final key = preferences.getKeys().single;
    await preferences.setString(key, 'BTC');
    expect(await _store().read(), isNull);
    await preferences.setInt(key, 7);
    expect(await _store().read(), isNull);
    await _store().save(FundCurrency.usdt);
    expect(await _store().read(), FundCurrency.usdt);
  });

  test('concurrent confirmations retain the last confirmed choice', () async {
    final first = _store().save(FundCurrency.trx);
    final second = _store().save(FundCurrency.bi99);
    await Future.wait([first, second]);
    expect(await _store().read(), FundCurrency.bi99);
  });

  test('signed-out callers cannot create an anonymous preference', () {
    expect(() => _store(account: '').read(), throwsStateError);
    expect(() => _store(account: '').save(FundCurrency.trx), throwsStateError);
  });
}
