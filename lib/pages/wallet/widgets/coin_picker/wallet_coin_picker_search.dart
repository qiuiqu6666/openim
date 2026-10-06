import 'package:flutter/material.dart';

import '../../host/wallet_i18n.dart';
import '../wallet_99chat_tokens.dart';
import '../wallet_page_colors.dart';
import 'wallet_coin_picker_tokens.dart';

class WalletCoinPickerSearch extends StatelessWidget {
  const WalletCoinPickerSearch({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onCancel,
    required this.keyPrefix,
    this.hintText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onCancel;
  final String keyPrefix;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTokens.s5, AppTokens.s6, AppTokens.s3, AppTokens.s8),
      child: Row(children: [
        Expanded(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(minHeight: WalletCoinPickerTokens.minTap),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.inputFill,
                borderRadius: BorderRadius.circular(AppTokens.rSm),
              ),
              child: TextField(
                key: ValueKey('$keyPrefix-search'),
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                autocorrect: false,
                enableSuggestions: false,
                cursorColor: colors.inputCursor,
                style: TextStyle(
                    fontSize: WalletCoinPickerTokens.bodyFont,
                    color: colors.text),
                decoration: InputDecoration(
                  hintText: hintText ??
                      i18n.t(
                        zhHans: '输入币种或合约地址',
                        zhHant: '輸入幣種或合約地址',
                        en: 'Coin or contract address',
                        ja: '通貨またはコントラクトアドレス',
                        ko: '코인 또는 컨트랙트 주소 입력',
                      ),
                  hintStyle: TextStyle(
                    color: colors.inputHint,
                    fontSize: WalletCoinPickerTokens.bodyFont,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: AppTokens.s4, horizontal: AppTokens.s4),
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 22, color: colors.inputHint),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppTokens.s2),
        TextButton(
          key: ValueKey('$keyPrefix-cancel'),
          onPressed: onCancel,
          style: TextButton.styleFrom(
            foregroundColor: colors.text,
            minimumSize: const Size(
                WalletCoinPickerTokens.minTap, WalletCoinPickerTokens.minTap),
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.s3),
          ),
          child: Text(i18n.t(
              zhHans: '取消', zhHant: '取消', en: 'Cancel', ja: 'キャンセル', ko: '취소')),
        ),
      ]),
    );
  }
}
