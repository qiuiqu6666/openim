import 'package:flutter/material.dart';

import '../../../host/wallet_i18n.dart';
import '../../../host/wallet_image_cache.dart';
import '../../../host/wallet_network_image.dart';
import '../../../widgets/wallet_99chat_tokens.dart';
import '../../../widgets/wallet_page_colors.dart';
import '../../wallet_record_tokens.dart';
import '../../widgets/wallet_record_amount_text.dart';
import '../wallet_journal_entry.dart';
import '../wallet_journal_presentation.dart';
import 'wallet_journal_detail_tokens.dart';

class WalletJournalDetailHeader extends StatelessWidget {
  const WalletJournalDetailHeader({
    super.key,
    required this.entry,
    required this.coinLogo,
    required this.counterpartyNickname,
    required this.counterpartyAvatarUrl,
  });

  final WalletJournalEntry entry;
  final Widget coinLogo;
  final String counterpartyNickname;
  final String counterpartyAvatarUrl;

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    final isTransfer =
        (entry.bizType == 'transfer' || entry.bizType == 'group_transfer') &&
            entry.counterpartyID.trim().isNotEmpty;
    final hasBalanceMovement =
        (entry.direction == 'freeze' || entry.direction == 'unfreeze') &&
            !walletJournalHasBusinessBalanceMovement(entry);
    Widget fallback() {
      final nickname = counterpartyNickname.trim();
      return CircleAvatar(
        radius: WalletJournalDetailTokens.avatar / 2,
        backgroundColor: colors.avatarPlaceholder,
        child: Text(nickname.isEmpty ? '?' : nickname.characters.first,
            style: TextStyle(
                color: colors.text, fontSize: WalletRecordTokens.title)),
      );
    }

    final url = counterpartyAvatarUrl.trim();
    final cacheSize = ImageMemCacheSize.forLogicalSize(
        WalletJournalDetailTokens.avatar, context);
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: WalletJournalDetailTokens.headerPadding),
      child: Column(
        children: [
          ExcludeSemantics(
            child: SizedBox.square(
              key: isTransfer
                  ? const ValueKey('wallet-journal-counterparty-avatar')
                  : const ValueKey('wallet-journal-detail-coin'),
              dimension: WalletJournalDetailTokens.avatar,
              child: isTransfer
                  ? url.isEmpty
                      ? fallback()
                      : ClipOval(
                          child: AppNetworkImage(
                            url: url,
                            width: WalletJournalDetailTokens.avatar,
                            height: WalletJournalDetailTokens.avatar,
                            memCacheWidth: cacheSize,
                            memCacheHeight: cacheSize,
                            errorWidget: (_, __, ___) => fallback(),
                          ),
                        )
                  : FittedBox(fit: BoxFit.contain, child: coinLogo),
            ),
          ),
          const SizedBox(height: AppTokens.s4),
          Text(
            walletJournalTitle(entry, i18n,
                counterpartyNickname: counterpartyNickname),
            key: const ValueKey('wallet-journal-detail-title'),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: colors.text, fontSize: WalletJournalDetailTokens.title),
          ),
          const SizedBox(height: AppTokens.s4),
          WalletRecordAmountText(
            textKey: const ValueKey('wallet-record-detail-amount'),
            value: walletJournalPrimaryAmount(entry),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: WalletJournalDetailTokens.amount,
              fontWeight: FontWeight.w600,
              color: colors.text,
            ),
          ),
          if (hasBalanceMovement) ...[
            const SizedBox(height: AppTokens.s4),
            Text(
              walletJournalDirectionExplanation(entry, i18n),
              key: const ValueKey('wallet-journal-direction-explanation'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: WalletRecordTokens.muted(context),
                  fontSize: WalletJournalDetailTokens.caption),
            ),
          ],
        ],
      ),
    );
  }
}
