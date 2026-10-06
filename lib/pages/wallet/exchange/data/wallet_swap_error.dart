import '../../data/wallet_fund_api.dart';
import '../../../../services/fund_api.dart';

bool walletSwapRequiresNewQuote(Object failure) =>
    failure is FundApiException &&
    !failure.isUncertain &&
    const {20072, 20074, 20075}.contains(failure.code);

/// Swap-specific refusals do not change messages in other fund flows.
String walletSwapErrorMessage(Object failure) {
  if (failure is FundApiException && !failure.isUncertain) {
    switch (failure.code) {
      case 20030:
        return '行情暂时不可用，请稍后重新获取报价';
      case 20072:
        return '报价已过期，请重新预览并确认';
      case 20073:
        return '报价已使用，请查询原交易';
      case 20074:
        return '报价无效，请重新预览并确认';
      case 20075:
        return '该兑换方向暂未开放，请选择其他币种';
    }
  }
  return walletFundErrorMessage(failure);
}
