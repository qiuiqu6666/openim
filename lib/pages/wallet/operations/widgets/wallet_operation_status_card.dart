import 'package:flutter/material.dart';

import '../../../customer_service/customer_service.dart';
import '../../data/wallet_operation_coordinator.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../wallet_payment_password_navigation.dart';

class WalletOperationStatusCard extends StatelessWidget {
  const WalletOperationStatusCard({
    super.key,
    required this.coordinator,
    required this.onQuery,
    required this.onNew,
  });

  final WalletOperationCoordinator coordinator;
  final VoidCallback onQuery;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    if (coordinator.draft == null && coordinator.error == null) {
      return const SizedBox.shrink();
    }
    final cs = WalletPageColors.of(context);
    final draft = coordinator.draft;
    return Container(
      key: const ValueKey('wallet-operation-status'),
      padding: const EdgeInsets.all(AppTokens.s5),
      decoration: BoxDecoration(
        color: cs.card,
        borderRadius: BorderRadius.circular(AppTokens.rCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              coordinator.error ??
                  coordinator.receipt?.description ??
                  (coordinator.unresolved
                      ? '交易状态待确认，请勿重复提交'
                      : draft?.terminal == true
                          ? '原交易已处理，请查询订单详情'
                          : '原交易尚未完成'),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.text)),
          if (draft != null) ...[
            const SizedBox(height: AppTokens.s3),
            SelectableText('业务单号：${draft.clientOrderID}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.subText)),
            if (draft.orderID.isNotEmpty)
              SelectableText('订单号：${draft.orderID}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.subText)),
          ],
          const SizedBox(height: AppTokens.s3),
          Wrap(
            spacing: AppTokens.s3,
            children: [
              if (coordinator.errorCode == 20034)
                TextButton(
                  key: const ValueKey('wallet-operation-set-password'),
                  onPressed: coordinator.busy || !coordinator.sameAccount
                      ? null
                      : () => openWalletPaymentPassword(context),
                  child: const Text('设置支付密码'),
                ),
              if (draft?.orderID.isNotEmpty == true || coordinator.unresolved)
                TextButton(
                  key: const ValueKey('wallet-operation-query'),
                  onPressed: coordinator.busy ? null : onQuery,
                  child: const Text('查询订单详情'),
                ),
              if (coordinator.unresolved)
                TextButton(
                  key: const ValueKey('wallet-operation-support'),
                  onPressed: () => showCustomerServiceSheet(context),
                  child: const Text('联系客服'),
                ),
              if (coordinator.canStartNew)
                TextButton(
                  key: const ValueKey('wallet-operation-new'),
                  onPressed: coordinator.busy ? null : onNew,
                  child: const Text('新交易'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
