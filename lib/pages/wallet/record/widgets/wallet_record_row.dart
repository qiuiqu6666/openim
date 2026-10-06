import 'package:flutter/material.dart';

import '../../host/wallet_i18n.dart';
import '../../host/wallet_image_cache.dart';
import '../../host/wallet_network_image.dart';
import '../../widgets/wallet_coin_logo.dart';
import '../../wallet_repository.dart' show CoinType;
import '../../wallet_time.dart';
import '../../widgets/platform_coin_icon.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../filters/wallet_record_filters.dart';
import '../journals/wallet_journal_presentation.dart';
import '../wallet_record_models.dart';
import '../wallet_record_amount.dart';
import '../wallet_record_tokens.dart';
import 'wallet_record_amount_text.dart';

class WalletRecordRow extends StatelessWidget {
  const WalletRecordRow({super.key, required this.item, required this.onTap});
  final WalletRecordDto item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final muted = WalletRecordTokens.muted(context);
    final journal = item.journal;
    final title = journal != null
        ? walletJournalTitle(journal, AppI18n.of(context),
            counterpartyNickname: item.counterpartyNickname)
        : item.title.trim().isEmpty
            ? item.type.txt
            : item.title.trim();
    final time = formatWalletApiDateTime(
        journal == null
            ? item.time
            : DateTime.fromMillisecondsSinceEpoch(journal.createdAt,
                isUtc: true),
        pattern: 'yyyy-MM-dd HH:mm:ss');
    final amountStyle = TextStyle(
      color: journal == null && item.status == WalletRecordStatus.failed
          ? WalletRecordTokens.failure(context)
          : (journal == null ? item.income : journal.direction == 'income')
              ? WalletRecordTokens.income(context)
              : colors.text,
      fontSize: WalletRecordTokens.amount,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final captionStyle =
        TextStyle(fontSize: WalletRecordTokens.caption, color: muted);
    final amount = _amount(item);
    final balance = journal == null
        ? '--'
        : walletJournalAmount(journal.afterAvailable, journal.currency);
    final balanceLabel = AppI18n.of(context).t(
        zhHans: '${journal == null ? '余额' : '可用余额'} $balance',
        zhHant: '${journal == null ? '餘額' : '可用餘額'} $balance',
        en: '${journal == null ? 'Balance' : 'Available'} $balance',
        ja: '${journal == null ? '残高' : '利用可能残高'} $balance',
        ko: '${journal == null ? '잔액' : '사용 가능 잔액'} $balance');
    final identity =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style:
              TextStyle(color: colors.text, fontSize: WalletRecordTokens.body)),
      const SizedBox(height: AppTokens.s3),
      Text(time,
          key: ValueKey('wallet-record-time-${item.id}'), style: captionStyle),
      if (journal == null && item.status != WalletRecordStatus.success) ...[
        const SizedBox(height: AppTokens.s2),
        Text(item.status.txt,
            key: ValueKey('wallet-record-status-${item.id}'),
            style: captionStyle.copyWith(
                color: item.status == WalletRecordStatus.failed
                    ? WalletRecordTokens.failure(context)
                    : muted,
                fontWeight: FontWeight.w600)),
      ],
    ]);
    final value = Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      WalletRecordAmountText(
          value: amount,
          textKey: ValueKey('wallet-record-amount-${item.id}'),
          style: amountStyle),
      const SizedBox(height: AppTokens.s3),
      // A historical balance cannot be inferred from this transfer's amount.
      WalletRecordAmountText(
          value: balanceLabel,
          textKey: ValueKey('wallet-record-balance-${item.id}'),
          style: captionStyle),
    ]);
    return Semantics(
      button: true,
      child: InkWell(
        key: ValueKey('wallet-record-${item.id}'),
        onTap: onTap,
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(minHeight: WalletRecordTokens.rowHeight),
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.s4),
            child: LayoutBuilder(builder: (context, constraints) {
              final amountWidth = _textWidth(context, amount, amountStyle);
              final balanceWidth =
                  _textWidth(context, balanceLabel, captionStyle);
              final valueWidth =
                  amountWidth > balanceWidth ? amountWidth : balanceWidth;
              // Give each side enough room for its complete values at large text sizes.
              final titleWidth = _textWidth(
                  context,
                  title,
                  TextStyle(
                      color: colors.text, fontSize: WalletRecordTokens.body));
              final timeWidth = _textWidth(context, time, captionStyle);
              final identityWidth =
                  titleWidth > timeWidth ? titleWidth : timeWidth;
              const chrome =
                  WalletRecordTokens.avatar + AppTokens.s4 + AppTokens.s4;
              if (valueWidth + identityWidth + chrome > constraints.maxWidth) {
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        _RecordAvatar(item: item),
                        const SizedBox(width: AppTokens.s4),
                        Expanded(child: identity),
                      ]),
                      const SizedBox(height: AppTokens.s4),
                      value,
                    ]);
              }
              return Row(children: [
                _RecordAvatar(item: item),
                const SizedBox(width: AppTokens.s4),
                Expanded(child: identity),
                const SizedBox(width: AppTokens.s4),
                SizedBox(width: valueWidth, child: value),
              ]);
            }),
          ),
        ),
      ),
    );
  }

  static String _amount(WalletRecordDto item) {
    if (item.journal case final journal?) {
      return walletJournalPrimaryAmount(journal);
    }
    var raw = walletRecordAmountTwoDecimals(item.amount);
    final coin = walletRecordNormalizeCoin(item.coin);
    final unit = coin.isEmpty || coin == '99' ? '' : ' $coin';
    if (raw.isEmpty || raw == '--') return '--$unit';
    raw = raw.replaceFirst(RegExp(r'^[+-]\s*'), '');
    return '${item.income ? '+' : '-'}$raw$unit';
  }

  static double _textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(
          text: text, style: DefaultTextStyle.of(context).style.merge(style)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width.ceilToDouble();
    painter.dispose();
    return width;
  }
}

class _RecordAvatar extends StatelessWidget {
  const _RecordAvatar({required this.item});
  final WalletRecordDto item;

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final journal = item.journal;
    final transferCounterparty = journal != null &&
        const {'transfer', 'group_transfer'}.contains(journal.bizType) &&
        const {'transfer_sent', 'transfer_received'}.contains(journal.type) &&
        journal.counterpartyID.trim().isNotEmpty;
    if (transferCounterparty) {
      final nickname = item.counterpartyNickname.trim();
      final url = item.counterpartyAvatarUrl.trim();
      Widget fallback() => CircleAvatar(
            radius: WalletRecordTokens.avatar / 2,
            backgroundColor: colors.avatarPlaceholder,
            child: Text(nickname.isEmpty ? '?' : nickname.characters.first,
                style: TextStyle(
                    color: colors.text, fontSize: WalletRecordTokens.title)),
          );
      final cacheSize =
          ImageMemCacheSize.forLogicalSize(WalletRecordTokens.avatar, context);
      return ExcludeSemantics(
        child: SizedBox.square(
          key: ValueKey('wallet-record-counterparty-avatar-${item.id}'),
          dimension: WalletRecordTokens.avatar,
          child: url.isEmpty
              ? fallback()
              : ClipOval(
                  child: AppNetworkImage(
                    url: url,
                    width: WalletRecordTokens.avatar,
                    height: WalletRecordTokens.avatar,
                    memCacheWidth: cacheSize,
                    memCacheHeight: cacheSize,
                    errorWidget: (_, __, ___) => fallback(),
                  ),
                ),
        ),
      );
    }
    final refund = journal != null
        ? const {'packet_refund', 'withdraw_refund'}.contains(journal.type)
        : item.isRedPacketRefund ||
            item.title.contains('退款') ||
            item.title.contains('退回') ||
            item.title.toLowerCase().contains('refund');
    final redPacket = !item.isGroupTransfer &&
        (journal == null
            ? item.type == WalletRecordType.redPacket
            : journal.bizType.startsWith('packet_') ||
                journal.type.startsWith('packet_'));
    if (refund || redPacket) {
      return ExcludeSemantics(
        child: ClipOval(
          child: CircleAvatar(
            radius: WalletRecordTokens.avatar / 2,
            backgroundColor: colors.surfaceAlt,
            child: Image.asset(
              refund
                  ? 'lib/pages/wallet/record/assets/refund.png'
                  : 'lib/pages/wallet/record/assets/red_packet.png',
              width: WalletRecordTokens.avatar - AppTokens.s2,
              height: WalletRecordTokens.avatar - AppTokens.s2,
              fit: BoxFit.contain,
            ),
          ),
        ),
      );
    }
    final coinType = switch (walletRecordNormalizeCoin(item.coin)) {
      'USDT' => CoinType.usdt,
      'TRX' => CoinType.trx,
      '99' => CoinType.cny,
      _ => null,
    };
    final chainRecord = journal != null
        ? const {'deposit', 'deposit_reversal', 'withdraw'}
            .contains(journal.bizType)
        : item.isChainDeposit || item.isChainWithdraw;
    if (chainRecord && coinType != null) {
      return WalletCoinLogo(type: coinType, size: WalletRecordTokens.avatar);
    }
    final group = item.isGroupTransfer || item.isGroupRedPacket;
    final url = (group
            ? item.groupAvatar
            : item.income
                ? item.senderAvatar
                : item.receiverAvatar)
        .trim();
    Widget fallback() => walletRecordNormalizeCoin(item.coin) == '99'
        ? const PlatformCoinIcon(size: WalletRecordTokens.avatar)
        : CircleAvatar(
            radius: WalletRecordTokens.avatar / 2,
            backgroundColor: colors.surfaceAlt,
            child: Icon(
                item.journal?.direction == 'freeze'
                    ? Icons.lock_outline_rounded
                    : item.journal?.direction == 'unfreeze'
                        ? Icons.lock_open_rounded
                        : item.journal?.direction == 'neutral'
                            ? Icons.horizontal_rule_rounded
                            : item.type == WalletRecordType.swap
                                ? Icons.swap_horiz_rounded
                                : item.income
                                    ? Icons.south_west_rounded
                                    : Icons.north_east_rounded,
                color: colors.text,
                size: AppTokens.s6));
    final cacheSize =
        ImageMemCacheSize.forLogicalSize(WalletRecordTokens.avatar, context);
    return ExcludeSemantics(
        child: SizedBox.square(
      dimension: WalletRecordTokens.avatar,
      child: url.isEmpty
          ? fallback()
          : ClipOval(
              child: AppNetworkImage(
              url: url,
              width: WalletRecordTokens.avatar,
              height: WalletRecordTokens.avatar,
              memCacheWidth: cacheSize,
              memCacheHeight: cacheSize,
              errorWidget: (_, __, ___) => fallback(),
            )),
    ));
  }
}
