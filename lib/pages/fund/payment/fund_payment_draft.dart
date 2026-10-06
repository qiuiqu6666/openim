import '../../../services/fund_api.dart';

/// The details reviewed in a payment sheet. Currency changes preserve the
/// numeric amount, recipient and remark; they never perform an exchange.
/// Once submitted, the owner locks this snapshot until the result is confirmed.
class FundPaymentDraft {
  FundPaymentDraft(Map<String, dynamic> request)
      : request = Map<String, dynamic>.unmodifiable(request);

  final Map<String, dynamic> request;
  FundCurrency get currency => FundCurrency.parse(request['currency']);

  FundAmount get total {
    final shareAmount = request['shareAmount'];
    final amount = FundAmount.parse(
        (shareAmount ?? request['amount']) as String, currency);
    return shareAmount == null
        ? amount
        : amount.multipliedBy(request['shareCount'] as int);
  }

  FundPaymentDraft withCurrency(FundCurrency selected) {
    if (selected == currency) return this;
    final field = request.containsKey('shareAmount') ? 'shareAmount' : 'amount';
    final amount = FundAmount.parse(request[field] as String, selected);
    final next = FundPaymentDraft({
      ...request,
      'currency': selected.code,
      field: amount.decimal,
      'clientOrderID': FundApi.createClientOrderID(),
    });
    if (!amount.isPositive) throw const FormatException('金额必须大于 0');
    if (next.total.units > BigInt.parse('9223372036854775807')) {
      throw const FormatException('金额超出可处理范围');
    }
    if (request['biz'] == FundPacketBiz.lucky.code &&
        amount.units < BigInt.from(request['shareCount'] as int)) {
      throw const FormatException('总金额不足以分配这些红包');
    }
    return next;
  }
}
