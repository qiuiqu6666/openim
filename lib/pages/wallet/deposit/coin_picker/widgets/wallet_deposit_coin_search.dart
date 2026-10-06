import 'package:flutter/material.dart';

import '../../../widgets/coin_picker/wallet_coin_picker_search.dart';

/// Keeps the deposit picker interface and identifiers stable.
class WalletDepositCoinSearch extends StatelessWidget {
  const WalletDepositCoinSearch({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onCancel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => WalletCoinPickerSearch(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        onCancel: onCancel,
        keyPrefix: 'wallet-deposit-coin',
      );
}
