import 'package:flutter/material.dart';

import '../data/wallet_operation_coordinator.dart';
import '../host/wallet_navigation.dart';
import '../host/wallet_chain_explorer.dart';
import '../wallet_time.dart';
import '../widgets/wallet_99chat_tokens.dart';
import '../widgets/wallet_page_colors.dart';

/// Receives a response just fetched from GET /chat/fund/orders/:orderID.
class WalletOperationDetailScreen extends StatelessWidget {
  const WalletOperationDetailScreen({super.key, required this.receipt});
  final WalletOperationReceipt receipt;

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final appBar = WalletAppBarColors.of(context);
    final order = receipt.order;
    final fee = receipt.fee ?? order.fee;
    final received = receipt.received ?? order.targetAmount;
    return wrapWalletPage(
        context,
        Scaffold(
          backgroundColor: cs.bg,
          appBar: AppBar(
            leading: const AppBackButton(),
            centerTitle: true,
            title: const Text('订单详情'),
            backgroundColor: appBar.background,
            foregroundColor: appBar.title,
            surfaceTintColor: appBar.background,
            systemOverlayStyle: walletPageOverlayStyle(context),
          ),
          body: SafeArea(
              child: ListView(
            padding: const EdgeInsets.all(AppTokens.s5),
            children: [
              Text(receipt.description,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: cs.text)),
              const SizedBox(height: AppTokens.s7),
              _line(context, '订单号', order.orderID),
              _line(context, '币种', order.currency.displayName),
              _line(context, '金额', order.amount),
              if (order.biz == 'withdraw') ...[
                _line(context, '网络',
                    order.network.isEmpty ? 'TRON' : order.network),
                _line(context, '收款地址', order.toAddress),
                _line(context, '手续费',
                    fee == null ? '--' : '$fee ${order.currency.displayName}'),
                if (order.chainTxID.isNotEmpty)
                  TextButton(
                      onPressed: () =>
                          openWalletTronTransaction(context, order.chainTxID),
                      child: Text('交易哈希：${order.chainTxID}')),
                if (order.fromAddress.isNotEmpty)
                  _line(context, '转出地址', order.fromAddress),
                if (order.reviewReason.isNotEmpty)
                  _line(context, '审核说明', order.reviewReason),
                if (order.completionReason.isNotEmpty)
                  _line(context, '出款说明', order.completionReason),
                const Text('提现提交后等待审核及人工出款，出款登记不代表链上自动确认。'),
              ],
              if (order.biz == 'swap') ...[
                _line(
                    context,
                    '目标币种',
                    (order.targetCurrency ?? receipt.receivedCurrency)
                            ?.displayName ??
                        '--'),
                _line(context, '实得数量', received ?? '--'),
              ],
              _line(context, '状态',
                  order.biz == 'withdraw' ? receipt.description : order.status),
              _line(
                  context,
                  '创建时间',
                  order.createdAt == null
                      ? '--'
                      : formatWalletApiDateTime(order.createdAt)),
            ],
          )),
        ));
  }

  Widget _line(BuildContext context, String label, String value) {
    final cs = WalletPageColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.subText)),
          const SizedBox(height: AppTokens.s2),
          SelectableText(value.isEmpty ? '--' : value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.text)),
        ],
      ),
    );
  }
}
