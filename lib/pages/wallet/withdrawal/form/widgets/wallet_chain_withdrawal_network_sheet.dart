import 'package:flutter/material.dart';

import '../../../host/wallet_i18n.dart';
import '../../../widgets/wallet_99chat_tokens.dart';
import '../../../widgets/wallet_page_colors.dart';
import '../wallet_chain_withdrawal_labels.dart';
import '../wallet_chain_withdrawal_tokens.dart';

/// The only network offered is the network returned by the authenticated API.
Future<bool?> showWalletChainWithdrawalNetwork(
  BuildContext context, {
  required String network,
  required bool selected,
}) =>
    showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: WalletPageColors.of(context).card,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppTokens.rXl))),
      builder: (context) {
        final colors = WalletPageColors.of(context);
        final labels = WalletChainWithdrawalLabels(AppI18n.of(context));
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: WalletChainWithdrawalTokens.maxWidth,
                maxHeight: MediaQuery.sizeOf(context).height * .8),
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.all(WalletChainWithdrawalTokens.pagePadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(labels.networkChoice,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: colors.text, fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppTokens.s5),
                  ListTile(
                    key: const ValueKey('wallet-chain-network-tron'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(network, style: TextStyle(color: colors.text)),
                    subtitle: Text(labels.networkNote,
                        style: TextStyle(color: colors.subText)),
                    trailing: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: selected ? colors.blue : colors.subText),
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
