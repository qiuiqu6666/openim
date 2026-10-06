import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../wallet_exchange_tokens.dart';

/// Decimal quantity entry is separate from the six-digit payment PIN keypad.
class WalletExchangeKeypad extends StatelessWidget {
  const WalletExchangeKeypad(
      {super.key,
      required this.enabled,
      required this.onInput,
      required this.onDelete});
  final bool enabled;
  final ValueChanged<String> onInput;
  final VoidCallback onDelete;
  static const _keys = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '.',
    '0',
    'del'
  ];

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final textScale = MediaQuery.textScalerOf(context)
            .scale(WalletExchangeTokens.keypadFont) /
        WalletExchangeTokens.keypadFont;
    final height = WalletExchangeTokens.keyHeight * textScale.clamp(1.0, 2.0);
    return Column(children: [
      for (var row = 0; row < 4; row++)
        Row(children: [
          for (var column = 0; column < 3; column++)
            Expanded(child: _key(colors, _keys[row * 3 + column], height)),
        ]),
    ]);
  }

  Widget _key(WalletPageColors colors, String value, double height) {
    final name = value == '.'
        ? 'decimal'
        : value == 'del'
            ? 'delete'
            : value;
    final label = value == '.'
        ? '小数点'
        : value == 'del'
            ? '删除一位'
            : value;
    void activate() {
      HapticFeedback.selectionClick();
      value == 'del' ? onDelete() : onInput(value);
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('wallet-swap-key-$name'),
          onTap: enabled ? activate : null,
          borderRadius: BorderRadius.circular(AppTokens.rSm),
          child: SizedBox(
            height: height,
            child: Center(
                child: value == 'del'
                    ? Icon(Icons.backspace_outlined,
                        size: AppTokens.s7,
                        color: enabled ? colors.text : colors.subText)
                    : Text(value,
                        style: TextStyle(
                            fontSize: WalletExchangeTokens.keypadFont,
                            fontWeight: FontWeight.w500,
                            color: enabled ? colors.text : colors.subText))),
          ),
        ),
      ),
    );
  }
}
