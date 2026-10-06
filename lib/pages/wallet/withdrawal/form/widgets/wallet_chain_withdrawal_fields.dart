import 'package:flutter/material.dart';

import '../../../data/wallet_fund_api.dart';
import '../../../host/wallet_i18n.dart';
import '../../../widgets/wallet_99chat_tokens.dart';
import '../wallet_chain_withdrawal_labels.dart';
import '../wallet_chain_withdrawal_tokens.dart';

/// Address, network, and raw amount inputs. Validation belongs to the caller.
class WalletChainWithdrawalFields extends StatelessWidget {
  const WalletChainWithdrawalFields({
    super.key,
    required this.currency,
    required this.addressController,
    required this.amountController,
    required this.enabled,
    required this.networkSelected,
    required this.onAddressChanged,
    required this.onAmountChanged,
    this.network,
    this.minimum,
    this.balanceText,
    this.addressError,
    this.amountError,
    this.onPaste,
    this.onScan,
    this.onNetwork,
    this.onAll,
    this.onAddressInfo,
    this.onNetworkInfo,
    this.onAmountInfo,
  });

  final FundCurrency currency;
  final TextEditingController addressController;
  final TextEditingController amountController;
  final bool enabled;
  final bool networkSelected;
  final String? network;
  final String? minimum;

  /// Available decimal amount, without a currency suffix.
  final String? balanceText;
  final String? addressError;
  final String? amountError;
  final ValueChanged<String> onAddressChanged;
  final ValueChanged<String> onAmountChanged;
  final VoidCallback? onPaste;
  final VoidCallback? onScan;
  final VoidCallback? onNetwork;
  final VoidCallback? onAll;
  final VoidCallback? onAddressInfo;
  final VoidCallback? onNetworkInfo;
  final VoidCallback? onAmountInfo;

  @override
  Widget build(BuildContext context) {
    final labels = WalletChainWithdrawalLabels(AppI18n.of(context));
    final dark = Theme.of(context).brightness == Brightness.dark;
    final style = _textStyle(context, dark);
    final networkValue = networkSelected && network?.isNotEmpty == true
        ? network!
        : labels.selectNetwork;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(context, labels.address, onAddressInfo),
        const SizedBox(height: WalletChainWithdrawalTokens.labelGap),
        TextFormField(
          key: const ValueKey('wallet-chain-address'),
          controller: addressController,
          enabled: enabled,
          onChanged: onAddressChanged,
          style: style,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          enableSuggestions: false,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          decoration: _decoration(
            context,
            dark,
            hint: labels.addressHint,
            error: addressError,
            suffix: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _toolButton(
                  key: const ValueKey('wallet-chain-paste'),
                  label: labels.paste,
                  icon: Icons.content_paste_outlined,
                  onPressed: enabled ? onPaste : null,
                  dark: dark,
                ),
                _toolButton(
                  key: const ValueKey('wallet-chain-scan'),
                  label: labels.scan,
                  icon: Icons.qr_code_scanner_outlined,
                  onPressed: enabled ? onScan : null,
                  dark: dark,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: WalletChainWithdrawalTokens.sectionGap),
        _label(context, labels.networkLabel, onNetworkInfo),
        const SizedBox(height: WalletChainWithdrawalTokens.labelGap),
        Material(
          color: AppTokens.appSurfaceAlt(dark),
          borderRadius:
              BorderRadius.circular(WalletChainWithdrawalTokens.inputRadius),
          child: InkWell(
            key: const ValueKey('wallet-chain-network'),
            borderRadius:
                BorderRadius.circular(WalletChainWithdrawalTokens.inputRadius),
            onTap: enabled ? onNetwork : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                  minHeight: WalletChainWithdrawalTokens.inputHeight),
              child: Padding(
                padding: const EdgeInsets.all(
                    WalletChainWithdrawalTokens.inputPadding),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        networkValue,
                        style: style.copyWith(
                          color: networkSelected
                              ? AppTokens.appTextPrimary(dark)
                              : AppTokens.appTextSecondary(dark),
                        ),
                      ),
                    ),
                    const SizedBox(width: WalletChainWithdrawalTokens.rowGap),
                    Icon(Icons.keyboard_arrow_down,
                        color: AppTokens.appTextSecondary(dark)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: WalletChainWithdrawalTokens.sectionGap),
        _label(context, labels.quantity, onAmountInfo),
        const SizedBox(height: WalletChainWithdrawalTokens.labelGap),
        LayoutBuilder(builder: (context, constraints) {
          final stackActions = MediaQuery.textScalerOf(context)
                  .scale(WalletChainWithdrawalTokens.inputSize) >=
              WalletChainWithdrawalTokens.stackedTextSize;
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(currency.displayName, style: style),
              const SizedBox(width: WalletChainWithdrawalTokens.rowGap),
              TextButton(
                key: const ValueKey('wallet-chain-all'),
                onPressed: enabled ? onAll : null,
                style: TextButton.styleFrom(
                  foregroundColor: AppTokens.success,
                  disabledForegroundColor: AppTokens.appTextSecondary(dark),
                  minimumSize: const Size(
                    WalletChainWithdrawalTokens.tapSize,
                    WalletChainWithdrawalTokens.tapSize,
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: WalletChainWithdrawalTokens.inputPadding),
                  textStyle: style.copyWith(fontWeight: FontWeight.w500),
                ),
                child: Text(labels.all),
              ),
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const ValueKey('wallet-chain-amount'),
                controller: amountController,
                enabled: enabled,
                onChanged: onAmountChanged,
                style: style,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                // Keep invalid characters intact for exact amount validation.
                decoration: _decoration(
                  context,
                  dark,
                  hint: labels.minimumHint(minimum),
                  error: amountError,
                  suffix: stackActions ? null : actions,
                ),
              ),
              if (stackActions)
                Align(
                    alignment: AlignmentDirectional.centerEnd, child: actions),
            ],
          );
        }),
        const SizedBox(height: WalletChainWithdrawalTokens.rowGap),
        Text(
          labels.balance(balanceText, currency),
          key: const ValueKey('wallet-chain-balance'),
          style: style.copyWith(
            fontSize: WalletChainWithdrawalTokens.bodySize,
            color: AppTokens.appTextSecondary(dark),
          ),
        ),
      ],
    );
  }

  Widget _label(BuildContext context, String label, VoidCallback? onInfo) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Flexible(
          child: Text(label,
              style: _textStyle(context, dark).copyWith(
                  fontSize: WalletChainWithdrawalTokens.labelSize,
                  fontWeight: FontWeight.w600)),
        ),
        if (onInfo != null)
          _toolButton(
            label: WalletChainWithdrawalLabels(AppI18n.of(context)).info,
            icon: Icons.info_outline,
            onPressed: enabled ? onInfo : null,
            dark: dark,
          ),
      ],
    );
  }

  static TextStyle _textStyle(BuildContext context, bool dark) =>
      (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
        fontFamily: AppTokens.fontFamilyOf(context),
        fontSize: WalletChainWithdrawalTokens.inputSize,
        color: AppTokens.appTextPrimary(dark),
      );

  static InputDecoration _decoration(
    BuildContext context,
    bool dark, {
    required String hint,
    String? error,
    Widget? suffix,
  }) {
    final border = OutlineInputBorder(
      borderRadius:
          BorderRadius.circular(WalletChainWithdrawalTokens.inputRadius),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: _textStyle(context, dark)
          .copyWith(color: AppTokens.appTextSecondary(dark)),
      errorText: error,
      errorMaxLines: 5,
      errorStyle: _textStyle(context, dark).copyWith(
          fontSize: WalletChainWithdrawalTokens.bodySize,
          color: AppTokens.danger),
      filled: true,
      fillColor: AppTokens.appSurfaceAlt(dark),
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: AppTokens.accent)),
      errorBorder: border.copyWith(
          borderSide: const BorderSide(color: AppTokens.danger)),
      focusedErrorBorder: border.copyWith(
          borderSide: const BorderSide(color: AppTokens.danger)),
      contentPadding:
          const EdgeInsets.all(WalletChainWithdrawalTokens.inputPadding),
      constraints: const BoxConstraints(
          minHeight: WalletChainWithdrawalTokens.inputHeight),
      suffixIcon: suffix,
      suffixIconConstraints:
          const BoxConstraints(minHeight: WalletChainWithdrawalTokens.tapSize),
    );
  }

  static Widget _toolButton({
    Key? key,
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    required bool dark,
  }) =>
      IconButton(
        key: key,
        tooltip: label,
        onPressed: onPressed,
        color: AppTokens.appTextSecondary(dark),
        disabledColor: AppTokens.appTextSecondary(dark),
        constraints: const BoxConstraints.tightFor(
          width: WalletChainWithdrawalTokens.tapSize,
          height: WalletChainWithdrawalTokens.tapSize,
        ),
        iconSize: WalletChainWithdrawalTokens.iconSize,
        icon: Icon(icon),
      );
}
