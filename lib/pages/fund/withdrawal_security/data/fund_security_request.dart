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

  final String kind;
  final Map<String, String> fields;

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
