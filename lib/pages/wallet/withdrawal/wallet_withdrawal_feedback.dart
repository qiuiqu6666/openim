import '../../../services/fund_api.dart';
import '../data/wallet_operation_coordinator.dart';

/// Brief feedback for the shared toast; order details stay in history.
String walletWithdrawalResultMessage(WalletOperationReceipt receipt) {
  if (receipt.accepted) return '提现申请成功';
  if (receipt.order.status == 'withdraw_failed') return '提现失败：已退回';
  return '结果待确认，请查询订单';
}

String walletWithdrawalErrorMessage(Object failure, {bool unresolved = false}) {
  if (unresolved || failure is FundApiException && failure.isUncertain) {
    return '结果待确认，请查询订单';
  }
  if (failure is FundApiException) {
    final reason = switch (failure.code) {
      20078 => '验证码已失效或不匹配，请重新获取',
      20076 => '修改手机号或密码后需等待24小时',
      20079 => '设备验证失败，请重新登录',
      1001 => '提交参数无效',
      _ => walletOperationError(failure),
    };
    return '操作失败：$reason';
  }
  // Never expose diagnostic payloads, account data or order identifiers.
  return '操作失败：请稍后重试';
}
