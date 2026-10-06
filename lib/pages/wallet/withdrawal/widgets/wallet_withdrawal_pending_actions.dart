import 'package:flutter/material.dart';

import '../../../customer_service/customer_service.dart';
import '../../data/wallet_operation_coordinator.dart';
import '../../host/wallet_i18n.dart';
import '../../widgets/wallet_99chat_tokens.dart';

/// Recovery actions for an existing write, without an inline result or IDs.
class WalletWithdrawalPendingActions extends StatelessWidget {
  const WalletWithdrawalPendingActions({
    super.key,
    required this.coordinator,
    required this.onQuery,
  });

  final WalletOperationCoordinator coordinator;
  final VoidCallback onQuery;

  @override
  Widget build(BuildContext context) {
    if (coordinator.draft?.submitted != true && coordinator.receipt == null) {
      return const SizedBox.shrink();
    }
    final i18n = AppI18n.of(context);
    return Wrap(spacing: AppTokens.s3, children: [
      TextButton(
        key: const ValueKey('wallet-operation-query'),
        onPressed: coordinator.busy || !coordinator.sameAccount ? null : onQuery,
        child: Text(i18n.t(
            zhHans: '查询订单状态',
            zhHant: '查詢訂單狀態',
            en: 'Check order status',
            ja: '注文状態を確認',
            ko: '주문 상태 확인')),
      ),
      if (coordinator.unresolved && coordinator.receipt == null)
        TextButton(
          key: const ValueKey('wallet-operation-support'),
          onPressed: coordinator.busy || !coordinator.sameAccount
              ? null
              : () => showCustomerServiceSheet(context),
          child: Text(i18n.t(
              zhHans: '联系客服',
              zhHant: '聯絡客服',
              en: 'Contact support',
              ja: 'サポートに連絡',
              ko: '고객센터 문의')),
        ),
    ]);
  }
}
