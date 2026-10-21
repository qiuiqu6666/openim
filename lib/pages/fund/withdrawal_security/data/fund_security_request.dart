import '../../../../services/fund_models.dart';

/// Immutable business parameters shared by the check, SMS and final write.
/// Payment passwords and verification codes never belong in these requests.
class FundSecurityRequest {
  FundSecurityRequest.transfer(Map<String, dynamic> request)
      : kind = 'transfer',
        fields = _copy(request, _transferKeys);

  FundSecurityRequest.withdrawal(Map<String, dynamic> request)
      : kind = 'withdrawal',
        fields = _copy(request, _withdrawalKeys);

  FundSecurityRequest.packet(Map<String, dynamic> request)
      : kind = 'packet',
        fields = _packet(request);

  FundSecurityRequest.swap(Map<String, dynamic> request)
      : kind = 'swap',
        fields = _swap(request);

  FundSecurityRequest.tip(Map<String, dynamic> request)
      : kind = 'tip',
        fields = _tip(request);

  final String kind;
  final Map<String, dynamic> fields;
  String get currency =>
      (fields['currency'] ?? fields['fromCurrency']) as String;

  static Map<String, dynamic> _packet(Map<String, dynamic> request) {
    final groupNormal =
        request['scene'] == 'group' && request['biz'] == 'packet_normal';
    final count = request['shareCount'];
    if (count != null && (count is! int || count < 1 || count > 10000)) {
      throw const FormatException('红包份数无效');
    }
    final data = Map<String, dynamic>.from(request);
    if (groupNormal) {
      if (count is! int) throw const FormatException('红包份数无效');
      data['amount'] = FundAmount.parse(data['shareAmount'] as String,
              FundCurrency.parse(data['currency'] as String))
          .multipliedBy(count)
          .decimal;
    }
    return Map.unmodifiable({
      ..._copy(data, {..._transferKeys, 'biz', 'shareAmount'}),
      if (count != null) 'shareCount': count
    });
  }

  static Map<String, dynamic> _swap(Map<String, dynamic> request) {
    final data = _copy({...request, 'currency': request['fromCurrency']},
        {'clientOrderID', 'currency', 'amount', 'toCurrency', 'quoteID'});
    if (data['toCurrency'] == data['currency'] || data['toCurrency'] == null) {
      throw const FormatException('请选择不同的兑换币种');
    }
    FundCurrency.parse(data['toCurrency']!);
    return Map.unmodifiable(
        {...data, 'fromCurrency': data['currency']}..remove('currency'));
  }

  static Map<String, dynamic> _tip(Map<String, dynamic> request) {
    final id = request['clientOrderID'];
    final session = request['liveSessionId'];
    final amount = request['amount'];
    if (id is! String ||
        id.isEmpty ||
        session is! String ||
        session.isEmpty ||
        amount is! int ||
        amount <= 0 ||
        amount > 9007199254740991) {
      throw const FormatException('打赏参数无效');
    }
    final currency = FundCurrency.parse(request['currency'] as String);
    return Map.unmodifiable({
      'clientOrderId': id,
      'sessionID': session,
      'currency': currency.code,
      'amount': amount,
      'memo': request['memo'] ?? ''
    });
  }

  static const _sharedKeys = {
    'clientOrderID',
    'currency',
    'amount',
    'remark',
    'recipientType',
    'recipient',
    'areaCode',
  };
  static const _transferKeys = {
    ..._sharedKeys,
    'scene',
    'recvID',
    'groupID',
  };
  static const _withdrawalKeys = {
    ..._sharedKeys,
    'mode',
    'network',
    'toAddress',
  };

  static Map<String, String> _copy(
      Map<String, dynamic> request, Set<String> keys) {
    final result = <String, String>{};
    for (final key in keys) {
      if (!request.containsKey(key)) continue;
      final value = request[key];
      if (value is! String) {
        throw const FormatException('交易参数不完整，请重新确认');
      }
      result[key] = value;
    }
    final id = result['clientOrderID'];
    final currency = result['currency'];
    final amount = result['amount'];
    if (id == null || id.trim().isEmpty || currency == null || amount == null) {
      throw const FormatException('交易参数不完整，请重新确认');
    }
    if (!FundAmount.parse(amount, FundCurrency.parse(currency)).isPositive) {
      throw const FormatException('请输入有效的转出数量');
    }
    return Map.unmodifiable(result);
  }

  Map<String, dynamic> toJson() => {kind: Map<String, dynamic>.from(fields)};
}
