import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/wallet_coin_logo.dart';
import '../host/wallet_i18n.dart';
import '../host/wallet_navigation.dart';
import '../host/wallet_chain_explorer.dart';
import '../wallet_repository.dart' show CoinType;
import '../widgets/wallet_99chat_scale.dart';
import '../widgets/wallet_page_colors.dart';
import 'journals/widgets/wallet_journal_detail_body.dart';
import 'journals/detail/wallet_journal_linked_order_screen.dart';
import 'journals/detail/wallet_journal_detail_tokens.dart';
import 'wallet_record_models.dart';
import 'wallet_record_amount.dart';
import 'widgets/wallet_record_amount_text.dart';

class WalletRecordDetailScreen extends StatelessWidget {
  final WalletRecordDto item;

  const WalletRecordDetailScreen({super.key, required this.item});

  String _short(String value) {
    final v = value.trim();
    if (v.isEmpty) return '--';
    if (v.length <= 18) return v;
    return '${v.substring(0, 8)}...${v.substring(v.length - 8)}';
  }

  String get _statusText {
    switch (item.status) {
      case WalletRecordStatus.success:
        return item.income
            ? AppI18n.current.t(
                zhHans: '已收到',
                zhHant: '已收到',
                en: 'Received',
                ja: '受取済み',
                ko: '수령 완료')
            : AppI18n.current.t(
                zhHans: '已发出',
                zhHant: '已發出',
                en: 'Sent',
                ja: '送信済み',
                ko: '전송 완료');
      case WalletRecordStatus.pending:
        return item.income
            ? AppI18n.current.t(
                zhHans: '确认中',
                zhHant: '確認中',
                en: 'Confirming',
                ja: '確認中',
                ko: '확인 중')
            : AppI18n.current.t(
                zhHans: '处理中',
                zhHant: '處理中',
                en: 'Processing',
                ja: '処理中',
                ko: '처리 중');
      case WalletRecordStatus.failed:
        return AppI18n.current
            .t(zhHans: '失败', zhHant: '失敗', en: 'Failed', ja: '失敗', ko: '실패');
    }
  }

  String get _networkTitle {
    final raw = item.network.trim();
    if (raw.toUpperCase().contains('TRC20') ||
        raw.toUpperCase().contains('TRON') ||
        item.coin.toUpperCase() == 'TRX') {
      return 'Tron';
    }
    return raw.isEmpty ? '--' : raw;
  }

  bool get _showTronNetworkIcon => _networkTitle == 'Tron';

  String get _incomingLabel => item.isChainDeposit
      ? AppI18n.current.t(
          zhHans: '收款地址',
          zhHant: '收款地址',
          en: 'Receiving Address',
          ja: '受取アドレス',
          ko: '수령 주소')
      : AppI18n.current.t(
          zhHans: '转入地址',
          zhHant: '轉入地址',
          en: 'Incoming Address',
          ja: '入金先アドレス',
          ko: '입금 주소');

  String get _incomingValue {
    final isWithdraw = item.title == '提现';
    final isDeposit = item.title == '链上充值';
    final isTransfer = item.title == '收到转账' || item.title == '发起转账';
    final candidates = isWithdraw
        ? <String>[item.addr, item.payee]
        : isDeposit
            ? <String>[item.addr, item.payee]
            : isTransfer
                ? <String>[item.payee, item.addr]
                : <String>[item.addr, item.payee, item.payer];
    return candidates.map((e) => e.trim()).firstWhere(
          (e) => e.isNotEmpty && e != '--' && e != '外部地址' && e != '我的钱包',
          orElse: () => '--',
        );
  }

  String get _outgoingValue {
    final isWithdraw = item.title == '提现';
    final isDeposit = item.title == '链上充值';
    final isTransfer = item.title == '收到转账' || item.title == '发起转账';
    final candidates = isWithdraw
        ? <String>[item.payer, '我的钱包']
        : isDeposit
            ? <String>[item.payer]
            : isTransfer
                ? <String>[item.payer, item.payee]
                : <String>[item.payer, item.addr, item.payee];
    return candidates.map((e) => e.trim()).firstWhere(
          (e) => e.isNotEmpty && e != '--' && e != '外部地址',
          orElse: () => '--',
        );
  }

  bool get _platformTransfer {
    if (item.isChainDeposit || item.isChainWithdraw) return false;
    final title = item.title.trim().toLowerCase();
    return title.contains('转账') || title.contains('transfer');
  }

  String get _referenceValue {
    if (item.isSwap) {
      final order = item.orderNo.trim();
      return order.isEmpty ? '--' : order;
    }
    final hash = item.hash.trim();
    return hash.isEmpty ? '--' : hash;
  }

  bool get _showReferenceRow => item.isSwap
      ? _referenceValue != '--'
      : (_referenceValue != '--' && !_platformTransfer);

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final appBar = WalletAppBarColors.of(context);
    final i18n = AppI18n.of(context);
    return wrapWalletPage(
      context,
      Scaffold(
        backgroundColor: cs.bg,
        appBar: AppBar(
          leading: const AppBackButton(),
          centerTitle: true,
          backgroundColor: appBar.background,
          foregroundColor: appBar.title,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: walletPageOverlayStyle(context),
          title: Text(
            i18n.t(
              zhHans: item.journal != null ? '余额明细详情' : '交易详情',
              zhHant: item.journal != null ? '餘額明細詳情' : '交易詳情',
              en: item.journal != null
                  ? 'Balance Details'
                  : 'Transaction Details',
              ja: item.journal != null ? '残高明細詳細' : '取引詳細',
              ko: item.journal != null ? '잔액 내역 상세' : '거래 상세',
            ),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: appBar.title,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: item.journal != null
              ? WalletJournalDetailBody(
                  entry: item.journal!,
                  counterpartyNickname: item.counterpartyNickname,
                  counterpartyAvatarUrl: item.counterpartyAvatarUrl,
                  coinLogo: _DetailCoinLogo(
                      coin: item.coin, size: WalletJournalDetailTokens.avatar),
                  onOpenOrder: item.journal!.orderID.isEmpty
                      ? null
                      : () => openWalletPage<void>(
                            context,
                            WalletJournalLinkedOrderScreen(
                                entry: item.journal!),
                          ),
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(22.w99, 24.h99, 22.w99, 24.h99),
                  children: [
                    Center(
                      child: _DetailCoinLogo(
                        coin: item.coin,
                        size: 111.w99,
                      ),
                    ),
                    SizedBox(height: 27.h99),
                    _DetailAmountHeader(item: item),
                    SizedBox(height: 15.h99),
                    Text(
                      '--',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24.sp99,
                        fontWeight: FontWeight.w400,
                        color: cs.subText,
                      ),
                    ),
                    SizedBox(height: 51.h99),
                    Container(
                      decoration: BoxDecoration(
                        color: cs.dark ? cs.inputFill : cs.surfaceAlt,
                        borderRadius: BorderRadius.circular(30.r99),
                      ),
                      padding: EdgeInsets.symmetric(
                          horizontal: 27.w99, vertical: 15.h99),
                      child: Column(
                        children: [
                          if (!item.isSwap) ...[
                            _DetailRow(
                              label: _incomingLabel,
                              value: _short(_incomingValue),
                              copyValue: _incomingValue == '--'
                                  ? null
                                  : _incomingValue,
                            ),
                            _DetailRow(
                              label: i18n.t(
                                  zhHans: '转出地址',
                                  zhHant: '轉出地址',
                                  en: 'Outgoing Address',
                                  ja: '送信元アドレス',
                                  ko: '출금 주소'),
                              value: _short(_outgoingValue),
                              copyValue: _outgoingValue == '--'
                                  ? null
                                  : _outgoingValue,
                            ),
                          ],
                          _DetailRow(
                            label: i18n.t(
                                zhHans: '网络',
                                zhHant: '網路',
                                en: 'Network',
                                ja: 'ネットワーク',
                                ko: '네트워크'),
                            value: _networkTitle,
                            valueWidget: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                if (_showTronNetworkIcon) ...[
                                  _DetailCoinLogo(coin: 'TRX', size: 33.w99),
                                  SizedBox(width: 12.w99),
                                ],
                                Text(
                                  _networkTitle,
                                  style: TextStyle(
                                    fontSize: 22.5.sp99,
                                    fontWeight: FontWeight.w500,
                                    color: cs.text,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _DetailRow(
                            label: i18n.t(
                                zhHans: '交易状态',
                                zhHant: '交易狀態',
                                en: 'Status',
                                ja: 'ステータス',
                                ko: '상태'),
                            value: _statusText,
                          ),
                          if (_showReferenceRow)
                            _DetailRow(
                              label: i18n.t(
                                zhHans: item.isSwap ? '订单号' : '交易哈希',
                                zhHant: item.isSwap ? '訂單號' : '交易雜湊',
                                en: item.isSwap
                                    ? 'Order No.'
                                    : 'Transaction Hash',
                                ja: item.isSwap ? '注文番号' : 'トランザクションハッシュ',
                                ko: item.isSwap ? '주문 번호' : '거래 해시',
                              ),
                              value: _short(_referenceValue),
                              valueWidget: !item.isSwap &&
                                      (item.isChainDeposit ||
                                          item.isChainWithdraw)
                                  ? Semantics(
                                      link: true,
                                      child: InkWell(
                                        key: const ValueKey(
                                            'wallet-record-open-chain-tx-id'),
                                        onTap: () => openWalletTronTransaction(
                                            context, _referenceValue),
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                              minHeight: 48),
                                          child: Align(
                                            alignment: Alignment.centerRight,
                                            child: Text(_short(_referenceValue),
                                                semanticsLabel: _referenceValue,
                                                style: TextStyle(
                                                    color: cs.blue,
                                                    fontSize: 24.sp99,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                          ),
                                        ),
                                      ),
                                    )
                                  : null,
                              copyValue: _referenceValue == '--'
                                  ? null
                                  : _referenceValue,
                            ),
                          _DetailRow(
                            label: i18n.t(
                                zhHans: '交易时间',
                                zhHant: '交易時間',
                                en: 'Time',
                                ja: '取引時間',
                                ko: '거래 시간'),
                            value: item.time.trim().isEmpty ? '--' : item.time,
                            showDivider: false,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _DetailAmountHeader extends StatelessWidget {
  const _DetailAmountHeader({required this.item});

  final WalletRecordDto item;

  bool get _platformCoin {
    final raw = item.coin.trim();
    return raw.toUpperCase() == '99' || raw == '元';
  }

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    if (!_platformCoin) {
      return WalletRecordAmountText(
        textKey: const ValueKey('wallet-record-detail-amount'),
        value: '${walletRecordAmountTwoDecimals(item.amount)} ${item.coin}',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 51.sp99,
          fontWeight: FontWeight.w700,
          color: cs.text,
          height: 1.05,
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
            child: WalletRecordAmountText(
          textKey: const ValueKey('wallet-record-detail-amount'),
          value: walletRecordAmountTwoDecimals(item.amount),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 51.sp99,
            fontWeight: FontWeight.w700,
            color: cs.text,
            height: 1.05,
          ),
        )),
        SizedBox(width: 12.w99),
        ClipOval(
          child: Image.asset(
            'assets/img/platform_99.webp',
            width: 42.w99,
            height: 42.w99,
            fit: BoxFit.cover,
          ),
        ),
      ],
    );
  }
}

class _DetailCoinLogo extends StatelessWidget {
  const _DetailCoinLogo({required this.coin, required this.size});

  final String coin;
  final double size;

  @override
  Widget build(BuildContext context) {
    final raw = coin.trim();
    final upper = raw.toUpperCase();
    if (upper == '99' || raw == '元') {
      return ClipOval(
        child: Image.asset(
          'assets/img/platform_99.webp',
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    if (upper == 'USDT' || upper == 'TRX') {
      return WalletCoinLogo(
        type: upper == 'TRX' ? CoinType.trx : CoinType.usdt,
        size: size,
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFF5B8CFF),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        upper.isEmpty ? '?' : upper.substring(0, 1),
        style: TextStyle(
          fontSize: size * .46,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    this.value,
    this.valueWidget,
    this.copyValue,
    this.showDivider = true,
  });

  final String label;
  final String? value;
  final Widget? valueWidget;
  final String? copyValue;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    return Container(
      padding: EdgeInsets.symmetric(vertical: 19.5.h99),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 129.w99,
            child: Text(
              label,
              style: TextStyle(
                color: cs.subText,
                fontSize: 24.sp99,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          SizedBox(width: 18.w99),
          Expanded(
            child: valueWidget ??
                Text(
                  value ?? '--',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: cs.text,
                    fontSize: 24.sp99,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
          ),
          if ((copyValue ?? '').isNotEmpty) ...[
            SizedBox(width: 15.w99),
            InkWell(
              onTap: () => Clipboard.setData(ClipboardData(text: copyValue!)),
              child: Icon(Icons.copy_rounded, size: 27.sp99, color: cs.blue),
            ),
          ],
        ],
      ),
    );
  }
}
