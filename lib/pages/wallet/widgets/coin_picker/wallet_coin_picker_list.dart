import 'package:flutter/material.dart';

import '../../host/wallet_i18n.dart';
import '../wallet_99chat_tokens.dart';
import '../wallet_page_colors.dart';
import 'wallet_coin_picker_tokens.dart';

/// Displays supplied currencies once while callers own rows and selection.
class WalletCoinPickerList<T> extends StatefulWidget {
  const WalletCoinPickerList({
    super.key,
    required this.items,
    required this.codeOf,
    required this.rowBuilder,
    required this.keyPrefix,
    this.searching = false,
    this.popularCodes = const ['USDT', 'TRX'],
  });

  final List<T> items;
  final String Function(T) codeOf;
  final Widget Function(T) rowBuilder;
  final String keyPrefix;
  final bool searching;
  final List<String> popularCodes;

  @override
  State<WalletCoinPickerList<T>> createState() =>
      _WalletCoinPickerListState<T>();
}

class _WalletCoinPickerListState<T> extends State<WalletCoinPickerList<T>> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final items = [...widget.items]
      ..sort((a, b) => widget.codeOf(a).compareTo(widget.codeOf(b)));
    final displayed = <T>[];
    final seenCodes = <String>{};
    void addItem(T item) {
      if (seenCodes.add(widget.codeOf(item).toUpperCase())) displayed.add(item);
    }

    if (!widget.searching) {
      for (final code in widget.popularCodes) {
        for (final item in items) {
          if (widget.codeOf(item).toUpperCase() == code.toUpperCase()) {
            addItem(item);
          }
        }
      }
    }
    for (final item in items) {
      addItem(item);
    }
    final i18n = AppI18n.of(context);

    return Material(
      color: colors.card,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: AppTokens.s7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.searching && displayed.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppTokens.s5, AppTokens.s5, AppTokens.s5, AppTokens.s3),
                child: Text(
                  i18n.t(
                    zhHans: '热门币种',
                    zhHant: '熱門幣種',
                    en: 'Popular coins',
                    ja: '人気の通貨',
                    ko: '인기 코인',
                  ),
                  style: TextStyle(
                    color: colors.text,
                    fontSize: WalletCoinPickerTokens.codeFont,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            for (final item in displayed)
              KeyedSubtree(
                key: ValueKey(
                    '${widget.keyPrefix}-${widget.searching ? 'search' : 'hot'}-${widget.codeOf(item)}'),
                child: widget.rowBuilder(item),
              ),
          ],
        ),
      ),
    );
  }
}
