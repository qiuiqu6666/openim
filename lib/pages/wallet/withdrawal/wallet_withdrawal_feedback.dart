import 'package:openim_common/localization.dart';
import '../../../services/fund_api.dart';
import '../data/wallet_operation_coordinator.dart';

/// Brief feedback for the shared toast; order details stay in history.
String walletWithdrawalResultMessage(WalletOperationReceipt receipt) {
  if (receipt.accepted) return AppCopy.text('提现申请成功');
  if (receipt.order.status == 'withdraw_failed')
    return AppCopy.text('提现失败：已退回');
  return AppCopy.text('结果待确认，请查询订单');
}

String walletWithdrawalErrorMessage(Object failure, {bool unresolved = false}) {
  if (unresolved || failure is FundApiException && failure.isUncertain) {
    return AppCopy.text('结果待确认，请查询订单');
  }
  if (failure is FundApiException) {
    final reason = switch (failure.code) {
      20078 => AppCopy.text('验证码已失效或不匹配，请重新获取'),
      20076 => AppCopy.text('修改手机号或密码后需等待2小时'),
      20079 => AppCopy.text('设备验证失败，请重新登录'),
      1001 => AppCopy.text('提交参数无效'),
      _ => walletOperationError(failure),
    };
    return AppCopy.format('操作失败：{#0}', [reason]);
  }
  // Never expose diagnostic payloads, account data or order identifiers.
  return AppCopy.text('操作失败：请稍后重试');
}
