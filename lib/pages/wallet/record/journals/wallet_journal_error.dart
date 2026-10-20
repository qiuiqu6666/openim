import 'package:openim_common/localization.dart';
import '../../../../services/fund_api.dart';
import '../../data/wallet_fund_api.dart';

/// Ledger queries use filter parameters, rather than a payment form.
String walletJournalErrorMessage(Object error) {
  if (error is FundApiException && error.code == 1001) {
    return AppCopy.text('资金明细查询参数无效，请检查筛选条件后重试');
  }
  return walletFundErrorMessage(error);
}
