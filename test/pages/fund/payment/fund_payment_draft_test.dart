import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/fund/payment/fund_payment_draft.dart';
import 'package:openim/services/fund_api.dart';

void main() {
  final request = {
    'clientOrderID': 'reviewed-order',
    'scene': 'group',
    'currency': 'USDT',
    'biz': 'packet_normal',
    'shareAmount': '0.29',
    'shareCount': 3,
    'groupID': 'group-1',
    'remark': '原备注',
  };

  test('currency changes preserve business fields and exact group total', () {
    final draft = FundPaymentDraft(request);
    final changed = draft.withCurrency(FundCurrency.bi99);
    expect(changed.total.decimal, '0.87');
    expect(changed.total.currency, FundCurrency.bi99);
    expect(changed.request, {
      ...request,
      'currency': 'BI99',
      'clientOrderID': changed.request['clientOrderID'],
    });
    expect(changed.request['clientOrderID'],
        isNot(draft.request['clientOrderID']));
    expect(draft.request, request);
    expect(draft.withCurrency(FundCurrency.usdt), same(draft));
    expect(() => changed.request['currency'] = 'TRX', throwsUnsupportedError);
  });

  test('lower precision and insufficient lucky units reject without rounding',
      () {
    final precise = FundPaymentDraft({...request, 'shareAmount': '0.291'});
    expect(
        () => precise.withCurrency(FundCurrency.bi99), throwsFormatException);
    final lucky = FundPaymentDraft({
      for (final entry in request.entries)
        if (entry.key != 'shareAmount') entry.key: entry.value,
      'biz': 'packet_lucky',
      'amount': '0.02',
    });
    expect(() => lucky.withCurrency(FundCurrency.bi99), throwsFormatException);
    expect(lucky.withCurrency(FundCurrency.trx).total.decimal, '0.02');
  });

  test('changing accounting units still enforces the server integer range', () {
    final draft = FundPaymentDraft({
      'clientOrderID': 'reviewed-order',
      'scene': 'single',
      'currency': 'BI99',
      'biz': 'transfer',
      'amount': '10000000000000',
      'recvID': 'other',
    });
    expect(() => draft.withCurrency(FundCurrency.usdt), throwsFormatException);
    expect(draft.currency, FundCurrency.bi99);
  });
}
