import 'package:flutter/material.dart';

import '../../../host/wallet_i18n.dart';
import '../../../widgets/wallet_99chat_tokens.dart';
import '../../../widgets/wallet_page_colors.dart';
import '../wallet_chain_withdrawal_labels.dart';
import '../wallet_chain_withdrawal_tokens.dart';

/// A short wallet explanation with content-sized height and a reachable action.
Future<void> showWalletChainWithdrawalInfo(
  BuildContext context, {
  required String title,
  required String message,
}) =>
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (context) {
        final colors = WalletPageColors.of(context);
        final labels = WalletChainWithdrawalLabels(AppI18n.of(context));
        final textStyle =
            (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                .copyWith(
                    fontFamily: AppTokens.fontFamilyOf(context),
                    color: colors.text);
        return Dialog(
          key: const ValueKey('wallet-chain-info-dialog'),
          backgroundColor: colors.card,
          surfaceTintColor: colors.card,
          insetPadding:
              const EdgeInsets.all(WalletChainWithdrawalTokens.infoInset),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                  WalletChainWithdrawalTokens.infoRadius)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: WalletChainWithdrawalTokens.infoMaxWidth,
                maxHeight: MediaQuery.sizeOf(context).height *
                    WalletChainWithdrawalTokens.infoMaxHeightFraction),
            child: Padding(
              padding:
                  const EdgeInsets.all(WalletChainWithdrawalTokens.infoPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    fit: FlexFit.loose,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Semantics(
                              namesRoute: true,
                              header: true,
                              child: Text(title,
                                  key:
                                      const ValueKey('wallet-chain-info-title'),
                                  style: textStyle.copyWith(
                                      fontSize: WalletChainWithdrawalTokens
                                          .infoTitleSize,
                                      fontWeight: FontWeight.w600))),
                          const SizedBox(height: AppTokens.s4),
                          Text(message,
                              key: const ValueKey('wallet-chain-info-body'),
                              style: textStyle.copyWith(
                                  fontSize:
                                      WalletChainWithdrawalTokens.bodySize,
                                  height: WalletChainWithdrawalTokens
                                      .infoBodyLineHeight)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTokens.s7),
                  FilledButton(
                    key: const ValueKey('wallet-chain-info-close'),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(
                            WalletChainWithdrawalTokens.tapSize),
                        backgroundColor: colors.blue,
                        foregroundColor:
                            WalletChainWithdrawalTokens.buttonForeground,
                        textStyle: textStyle.copyWith(
                            fontSize: WalletChainWithdrawalTokens.inputSize),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                WalletChainWithdrawalTokens.buttonRadius))),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(labels.acknowledge),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
