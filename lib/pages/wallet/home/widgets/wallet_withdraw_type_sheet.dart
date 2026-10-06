import 'package:flutter/material.dart';

import '../../host/wallet_i18n.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../../withdraw_transfer_target_validator.dart';
import '../wallet_home_tokens.dart';

Future<WithdrawTransferTargetKind?> showWalletWithdrawTypeSheet(
        BuildContext context) =>
    showModalBottomSheet<WithdrawTransferTargetKind>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: WalletPageColors.of(context).card,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppTokens.rXl))),
      clipBehavior: Clip.antiAlias,
      builder: (_) => const WalletWithdrawTypeSheet(),
    );

/// Choose an existing withdrawal flow before selecting the currency.
class WalletWithdrawTypeSheet extends StatefulWidget {
  const WalletWithdrawTypeSheet({super.key});

  @override
  State<WalletWithdrawTypeSheet> createState() =>
      _WalletWithdrawTypeSheetState();
}

class _WalletWithdrawTypeSheetState extends State<WalletWithdrawTypeSheet> {
  bool _selected = false;

  void _choose(WithdrawTransferTargetKind kind) {
    if (_selected) return;
    _selected = true;
    Navigator.of(context).pop(kind);
  }

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .9,
            maxWidth: WalletHomeTokens.maxWidth),
        child: SingleChildScrollView(
          key: const ValueKey('wallet-withdraw-type-sheet'),
          padding: const EdgeInsets.fromLTRB(
              AppTokens.s5, AppTokens.s4, AppTokens.s5, AppTokens.s7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                  child: Container(
                width: AppTokens.s10,
                height: AppTokens.s2,
                decoration: BoxDecoration(
                    color: colors.line,
                    borderRadius: BorderRadius.circular(AppTokens.rPill)),
              )),
              const SizedBox(height: AppTokens.s7),
              Text(
                  i18n.t(
                      zhHans: '选择提现类型',
                      zhHant: '選擇提現類型',
                      en: 'Select withdrawal type',
                      ja: '出金方法を選択',
                      ko: '출금 유형 선택'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: WalletHomeTokens.withdrawSheetTitle,
                      color: colors.text,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: AppTokens.s7),
              _WithdrawalChoice(
                key: const ValueKey('wallet-withdraw-type-chain'),
                icon: Icons.account_balance_wallet_outlined,
                title: i18n.t(
                    zhHans: '链上提现',
                    zhHant: '鏈上提現',
                    en: 'On-chain withdrawal',
                    ja: 'オンチェーン出金',
                    ko: '온체인 출금'),
                description: i18n.t(
                    zhHans: '通过区块链网络向其他钱包或交易所转出数字货币',
                    zhHant: '透過區塊鏈網路向其他錢包或交易所轉出數位貨幣',
                    en: 'Send cryptocurrency to another wallet or exchange over the blockchain.',
                    ja: 'ブロックチェーンで他のウォレットや取引所へ送金します。',
                    ko: '블록체인을 통해 다른 지갑이나 거래소로 암호화폐를 보냅니다.'),
                onTap: () => _choose(WithdrawTransferTargetKind.chain),
              ),
              const SizedBox(height: AppTokens.s4),
              _WithdrawalChoice(
                key: const ValueKey('wallet-withdraw-type-friend'),
                icon: Icons.swap_vert_rounded,
                title: i18n.t(
                    zhHans: '内部转账',
                    zhHant: '內部轉帳',
                    en: 'Internal transfer',
                    ja: '内部送金',
                    ko: '내부 송금'),
                description: i18n.t(
                    zhHans: '选择联系人，或通过用户 ID、昵称向其他用户转账',
                    zhHant: '選擇聯絡人，或透過使用者 ID、暱稱向其他使用者轉帳',
                    en: 'Send to a contact or find a user by user ID or nickname.',
                    ja: '連絡先を選ぶか、ユーザーID・ニックネームで送金します。',
                    ko: '연락처를 선택하거나 사용자 ID 또는 닉네임으로 송금합니다.'),
                badge: i18n.t(
                    zhHans: '0手续费',
                    zhHant: '0手續費',
                    en: 'Zero fees',
                    ja: '手数料なし',
                    ko: '수수료 없음'),
                onTap: () => _choose(WithdrawTransferTargetKind.friend),
              ),
              const SizedBox(height: AppTokens.s4),
              _WithdrawalChoice(
                key: const ValueKey('wallet-withdraw-type-p2p'),
                icon: Icons.people_alt_outlined,
                title: i18n.t(
                    zhHans: 'P2P交易',
                    zhHant: 'P2P交易',
                    en: 'P2P trading',
                    ja: 'P2P取引',
                    ko: 'P2P 거래'),
                description: i18n.t(
                    zhHans: '暂未开放',
                    zhHant: '暫未開放',
                    en: 'Not available yet',
                    ja: '現在利用できません',
                    ko: '아직 이용할 수 없습니다'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WithdrawalChoice extends StatelessWidget {
  const _WithdrawalChoice({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.badge,
    this.onTap,
  });

  final IconData icon;
  final String title, description;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: Material(
        color: colors.bg,
        borderRadius: BorderRadius.circular(AppTokens.rCard),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.s5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                    child: Icon(icon,
                        size: AppTokens.s7,
                        color: onTap == null ? colors.subText : colors.text)),
                const SizedBox(width: AppTokens.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppTokens.s3,
                        runSpacing: AppTokens.s2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                      color: onTap == null
                                          ? colors.subText
                                          : colors.text,
                                      fontWeight: FontWeight.w600)),
                          if (badge != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppTokens.s3,
                                  vertical: AppTokens.s2),
                              decoration: BoxDecoration(
                                  color:
                                      AppTokens.success.withValues(alpha: .12),
                                  borderRadius:
                                      BorderRadius.circular(AppTokens.rSm)),
                              child: Text(badge!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                          color: colors.dark
                                              ? Color.lerp(AppTokens.success,
                                                  colors.text, .5)
                                              : AppTokens.success)),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.s4),
                      Text(description,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: colors.subText)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
