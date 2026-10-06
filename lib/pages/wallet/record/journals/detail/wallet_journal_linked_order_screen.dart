import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart' show DataSp;

import '../../../data/wallet_fund_api.dart';
import '../../../host/wallet_i18n.dart';
import '../../../host/wallet_chain_explorer.dart';
import '../../../host/wallet_navigation.dart';
import '../../../order/wallet_order_events.dart';
import '../../../wallet_time.dart';
import '../../../widgets/wallet_99chat_tokens.dart';
import '../../../widgets/wallet_page_colors.dart';
import '../../wallet_record_tokens.dart';
import '../wallet_journal_entry.dart';
import '../wallet_journal_filter_options.dart';
import '../wallet_journal_presentation.dart';
import 'wallet_journal_detail_field.dart';

/// Loads the actual associated order; journal operation amounts are not orders.
class WalletJournalLinkedOrderScreen extends StatefulWidget {
  const WalletJournalLinkedOrderScreen({
    super.key,
    required this.entry,
    this.api,
    this.isCurrentAccount,
  });

  final WalletJournalEntry entry;
  final WalletFundApi? api;
  final bool Function()? isCurrentAccount;

  @override
  State<WalletJournalLinkedOrderScreen> createState() =>
      _WalletJournalLinkedOrderScreenState();
}

class _WalletJournalLinkedOrderScreenState
    extends State<WalletJournalLinkedOrderScreen> with WidgetsBindingObserver {
  late final WalletFundApi _api;
  late final String _owner;
  late final String? _token;
  WalletFundOrder? _order;
  bool _loading = false;
  bool _failed = false;
  int _version = 0;

  bool get _sameAccount =>
      widget.isCurrentAccount?.call() ??
      (_owner.isNotEmpty &&
          !_owner.endsWith(':') &&
          _token?.isNotEmpty == true &&
          _owner == WalletOrderEvents.currentAccountKey &&
          _token == DataSp.chatToken);

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? WalletFundApi();
    _owner = WalletOrderEvents.currentAccountKey;
    _token = DataSp.chatToken;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant WalletJournalLinkedOrderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.orderID != widget.entry.orderID) {
      _version++;
      _order = null;
      _loading = false;
      unawaited(_load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_sameAccount && mounted) {
      _version++;
      setState(() {
        _order = null;
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  void dispose() {
    _version++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading || !_sameAccount || widget.entry.orderID.isEmpty) return;
    final version = ++_version;
    final orderID = widget.entry.orderID;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final order = await Future.sync(() => _api.getOrder(orderID))
          .timeout(const Duration(seconds: 6));
      if (!mounted || version != _version) return;
      if (!_sameAccount) {
        setState(() {
          _order = null;
          _loading = false;
          _failed = true;
        });
        return;
      }
      if (order.orderID != orderID) {
        throw const FormatException('Mismatched linked order');
      }
      setState(() {
        _order = order;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || version != _version) return;
      setState(() {
        _order = null;
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    String label(String zh, String hant, String en, String ja, String ko) =>
        i18n.t(zhHans: zh, zhHant: hant, en: en, ja: ja, ko: ko);
    final order = _sameAccount ? _order : null;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        leading: const AppBackButton(),
        centerTitle: true,
        backgroundColor: colors.bg,
        foregroundColor: colors.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: walletPageOverlayStyle(context),
        title: Text(label('账单详情', '帳單詳情', 'Order Details', '注文詳細', '주문 상세')),
      ),
      body: SafeArea(
        top: false,
        child: _loading && _sameAccount
            ? const Center(
                child: CircularProgressIndicator(
                    key: ValueKey('wallet-journal-order-loading')))
            : order == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppTokens.s5),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            !_sameAccount
                                ? label(
                                    '登录状态已变化，请返回后重试',
                                    '登入狀態已變更，請返回後重試',
                                    'Session changed. Go back and try again.',
                                    'ログイン状態が変更されました。戻って再試行してください。',
                                    '로그인 상태가 변경되었습니다. 돌아가서 다시 시도하세요.')
                                : label(
                                    '暂时无法加载账单，请重试',
                                    '暫時無法載入帳單，請重試',
                                    'Unable to load the order. Please try again.',
                                    '注文を読み込めません。再試行してください。',
                                    '주문을 불러올 수 없습니다. 다시 시도하세요.'),
                            key: const ValueKey('wallet-journal-order-error'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.subText),
                          ),
                          if (_sameAccount && _failed)
                            TextButton(
                              key: const ValueKey('wallet-journal-order-retry'),
                              onPressed: _load,
                              child: Text(
                                  label('重试', '重試', 'Retry', '再試行', '다시 시도')),
                            ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    key: const ValueKey('wallet-journal-order-scroll'),
                    padding: const EdgeInsets.all(AppTokens.s4),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                              maxWidth: WalletRecordTokens.maxWidth),
                          child: Container(
                            padding: const EdgeInsets.all(AppTokens.s5),
                            decoration: BoxDecoration(
                              color: colors.card,
                              borderRadius:
                                  BorderRadius.circular(AppTokens.rCard),
                            ),
                            child: Column(
                              children: [
                                WalletJournalDetailField(
                                  id: 'linked-order-id',
                                  label: label('订单号', '訂單號', 'Order ID', '注文番号',
                                      '주문 번호'),
                                  value: order.orderID,
                                  copy: true,
                                ),
                                WalletJournalDetailField(
                                  id: 'linked-order-biz',
                                  label:
                                      label('业务类型', '業務類型', 'Type', '種類', '유형'),
                                  value:
                                      walletJournalFilterLabel(order.biz, i18n),
                                ),
                                WalletJournalDetailField(
                                  id: 'linked-order-amount',
                                  amount: true,
                                  label: label('订单金额', '訂單金額', 'Order amount',
                                      '注文金額', '주문 금액'),
                                  value: walletJournalAmount(
                                      order.amount, order.currency.code),
                                ),
                                WalletJournalDetailField(
                                  id: 'linked-order-status',
                                  label: label('订单当前状态', '訂單目前狀態',
                                      'Current status', '現在の状態', '현재 상태'),
                                  value: _status(order.status, i18n),
                                ),
                                WalletJournalDetailField(
                                  id: 'linked-order-time',
                                  label: label('创建时间', '建立時間', 'Created at',
                                      '作成日時', '생성 시간'),
                                  value: order.createdAt == null
                                      ? '--'
                                      : formatWalletApiDateTime(
                                          order.createdAt!),
                                ),
                                if (order.toAddress.isNotEmpty)
                                  WalletJournalDetailField(
                                    id: 'linked-order-address',
                                    label: label('提现地址', '提現地址',
                                        'Withdrawal address', '出金先', '출금 주소'),
                                    value: order.toAddress,
                                    copy: true,
                                  ),
                                if (order.chainTxID.isNotEmpty)
                                  WalletJournalDetailField(
                                    id: 'linked-order-hash',
                                    label: label('交易哈希', '交易雜湊',
                                        'Transaction hash', '取引ハッシュ', '거래 해시'),
                                    value: order.chainTxID,
                                    copy: true,
                                    valueColor: colors.blue,
                                    onTap: () => openWalletTronTransaction(
                                        context, order.chainTxID),
                                  ),
                                if (order.fromAddress.isNotEmpty)
                                  WalletJournalDetailField(
                                    id: 'linked-order-from-address',
                                    label: label('转出地址', '轉出地址',
                                        'Sending address', '送信元', '출금 주소'),
                                    value: order.fromAddress,
                                    copy: true,
                                  ),
                                if (order.reviewReason.isNotEmpty)
                                  WalletJournalDetailField(
                                    id: 'linked-order-review-reason',
                                    label: label('审核说明', '審核說明', 'Review note',
                                        '審査メモ', '심사 메모'),
                                    value: order.reviewReason,
                                  ),
                                if (order.completionReason.isNotEmpty)
                                  WalletJournalDetailField(
                                    id: 'linked-order-completion-reason',
                                    label: label('出款说明', '出款說明', 'Payment note',
                                        '送金メモ', '지급 메모'),
                                    value: order.completionReason,
                                  ),
                                if (order.fee != null)
                                  WalletJournalDetailField(
                                    id: 'linked-order-fee-amount',
                                    amount: true,
                                    label: label(
                                        '手续费', '手續費', 'Fee', '手数料', '수수료'),
                                    value: walletJournalAmount(
                                        order.fee, order.currency.code),
                                  ),
                                if (order.targetCurrency != null &&
                                    order.targetAmount != null)
                                  WalletJournalDetailField(
                                    id: 'linked-order-target-amount',
                                    amount: true,
                                    label: label('转入金额', '轉入金額',
                                        'Received amount', '受取金額', '받은 금액'),
                                    value: walletJournalAmount(
                                        order.targetAmount,
                                        order.targetCurrency!.code),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

String _status(String status, AppI18n i18n) {
  final (zh, hant, en) = switch (status) {
    'done' => ('已完成', '已完成', 'Completed'),
    'open' => ('待领取', '待領取', 'Awaiting claim'),
    'refunded' => ('已退回', '已退回', 'Refunded'),
    'withdraw_pending' => ('等待审核', '等待審核', 'Awaiting review'),
    'withdraw_approved' => ('等待出款', '等待出款', 'Awaiting payment'),
    'withdraw_done' => ('已登记出款', '已登記出款', 'Payment recorded'),
    'withdraw_failed' => ('已退回', '已退回', 'Returned'),
    _ => ('--', '--', '--'),
  };
  return i18n.t(zhHans: zh, zhHant: hant, en: en, ja: en, ko: en);
}
