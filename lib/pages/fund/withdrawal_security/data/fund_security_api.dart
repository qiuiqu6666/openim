import '../../../../services/fund_api.dart';
import 'fund_security_models.dart';
import 'fund_security_request.dart';

/// Uses Chat authentication; these endpoints never deduct or freeze funds.
class FundWithdrawalSecurityApi {
  const FundWithdrawalSecurityApi(this.api);
  final FundApi api;

  Future<FundSecurityCheck> check(FundSecurityRequest request) async {
    final data = await api.requestData('/chat/fund/withdrawal-security/check',
        data: request.toJson());
    final result = FundSecurityCheck.fromJson(data);
    if (result.currency != request.fields['currency']) {
      throw const FormatException('安全验证币种不一致');
    }
    return result;
  }

  Future<FundSecurityChallenge> send(FundSecurityRequest request) async =>
      FundSecurityChallenge.fromJson(await api.requestData(
          '/chat/fund/withdrawal-security/code',
          data: request.toJson()));
}
