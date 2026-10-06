import 'package:flutter/material.dart';

import '../../host/wallet_i18n.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../wallet_record_models.dart';
import '../wallet_record_tokens.dart';
import '../journals/widgets/wallet_journal_filter_sections.dart';
import 'wallet_record_filters.dart';

String walletRecordDatePresetLabel(
        WalletHistoryDatePreset preset, AppI18n i18n) =>
    switch (preset) {
      WalletHistoryDatePreset.all => HistoryRecordFilter.all.txt,
      WalletHistoryDatePreset.week => i18n.t(
          zhHans: '近7天',
          zhHant: '近7天',
          en: 'Last 7 days',
          ja: '過去7日間',
          ko: '최근 7일'),
      WalletHistoryDatePreset.month => i18n.t(
          zhHans: '近1个月',
          zhHant: '近1個月',
          en: 'Last month',
          ja: '過去1か月',
          ko: '최근 1개월'),
      WalletHistoryDatePreset.threeMonths => i18n.t(
          zhHans: '近3个月',
          zhHant: '近3個月',
          en: 'Last 3 months',
          ja: '過去3か月',
          ko: '최근 3개월'),
      WalletHistoryDatePreset.year => i18n.t(
          zhHans: '近1年',
          zhHant: '近1年',
          en: 'Last year',
          ja: '過去1年',
          ko: '최근 1년'),
    };

/// Edits a local draft; only the confirmation action returns a selection.
class WalletRecordFilterSheet extends StatefulWidget {
  const WalletRecordFilterSheet({
    super.key,
    required this.selection,
    required this.coinOptions,
    required this.now,
    this.journalMode = false,
    this.fixedJournalBizType,
  });

  final WalletRecordSelection selection;
  final List<String> coinOptions;
  final DateTime now;
  final bool journalMode;
  final String? fixedJournalBizType;

  @override
  State<WalletRecordFilterSheet> createState() =>
      _WalletRecordFilterSheetState();
}

class _WalletRecordFilterSheetState extends State<WalletRecordFilterSheet> {
  late WalletRecordSelection _draft;
  late List<String> _coins;

  @override
  void initState() {
    super.initState();
    final selectedCoin = walletRecordNormalizeCoin(widget.selection.coin ?? '');
    _draft = widget.selection.copyWith(
      coin: selectedCoin,
      clearCoin: selectedCoin.isEmpty,
    );
    _coins = List<String>.unmodifiable({
      for (final coin in widget.coinOptions)
        if (walletRecordNormalizeCoin(coin).isNotEmpty)
          walletRecordNormalizeCoin(coin),
      if (selectedCoin.isNotEmpty) selectedCoin,
    });
  }

  void _reset() {
    setState(() {
      _draft = _draft.copyWith(
        clearCoin: true,
        type: HistoryRecordFilter.all,
        datePreset: WalletHistoryDatePreset.all,
        clearMonth: true,
        clearJournalBizType: true,
        clearJournalType: true,
        clearJournalDirection: true,
      );
    });
  }

  Widget _option({
    required String keyName,
    required String label,
    required bool selected,
    required double maxWidth,
    required WalletPageColors colors,
    required VoidCallback onPressed,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Semantics(
        selected: selected,
        child: TextButton(
          key: ValueKey(keyName),
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: colors.text,
            backgroundColor:
                selected ? colors.filterActiveBg : colors.filterInactiveBg,
            minimumSize:
                const Size(AppTokens.buttonHeight, AppTokens.buttonHeight),
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s4,
              vertical: AppTokens.s3,
            ),
            side: BorderSide(
              color: selected ? colors.filterActiveBorder : colors.line,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.rMd),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const ExcludeSemantics(
                  child: Icon(Icons.check_rounded, size: AppTokens.s6),
                ),
                const SizedBox(width: AppTokens.s3),
              ],
              Flexible(child: Text(label, textAlign: TextAlign.center)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> options, WalletPageColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: colors.text,
            fontSize: WalletRecordTokens.amount,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppTokens.s4),
        Wrap(
          spacing: AppTokens.s3,
          runSpacing: AppTokens.s3,
          children: options,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final colors = WalletPageColors.of(context);
    final title = i18n.t(
      zhHans: '筛选',
      zhHant: '篩選',
      en: 'Filters',
      ja: '絞り込み',
      ko: '필터',
    );
    final cancel = i18n.t(
      zhHans: '取消',
      zhHant: '取消',
      en: 'Cancel',
      ja: 'キャンセル',
      ko: '취소',
    );

    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: WalletRecordTokens.filterWidth,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Material(
          key: const ValueKey('wallet-record-filter-sheet'),
          color: colors.card,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTokens.rXl),
          ),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTokens.s5),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: colors.text,
                  fontFamily: AppTokens.fontFamilyOf(context),
                  fontFamilyFallback: AppTokens.fontFamilyFallbackOf(context),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final stackActions = width < 300 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.3;
                    final reset = OutlinedButton(
                      key: const ValueKey('wallet-record-filter-reset'),
                      onPressed: _reset,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.text,
                        minimumSize: const Size(0, AppTokens.buttonHeight),
                        padding: const EdgeInsets.all(AppTokens.s4),
                        side: BorderSide(color: colors.line),
                      ),
                      child: Text(i18n.t(
                        zhHans: '重置',
                        zhHant: '重設',
                        en: 'Reset',
                        ja: 'リセット',
                        ko: '초기화',
                      )),
                    );
                    final confirm = FilledButton(
                      key: const ValueKey('wallet-record-filter-confirm'),
                      onPressed: () => Navigator.of(context)
                          .pop<WalletRecordSelection>(_draft),
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.blue,
                        foregroundColor: AppTokens.ink900,
                        minimumSize: const Size(0, AppTokens.buttonHeight),
                        padding: const EdgeInsets.all(AppTokens.s4),
                      ),
                      child: Text(i18n.t(
                        zhHans: '确认',
                        zhHant: '確認',
                        en: 'Apply',
                        ja: '適用',
                        ko: '적용',
                      )),
                    );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: TextStyle(
                                  color: colors.text,
                                  fontSize: WalletRecordTokens.filterTitle,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: cancel,
                              onPressed: () => Navigator.of(context).pop(),
                              color: colors.text,
                              constraints: const BoxConstraints(
                                minWidth: AppTokens.buttonHeight,
                                minHeight: AppTokens.buttonHeight,
                              ),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppTokens.s7),
                        _section(
                          i18n.t(
                            zhHans: '币种',
                            zhHant: '幣種',
                            en: 'Coin',
                            ja: '通貨',
                            ko: '코인',
                          ),
                          [
                            _option(
                              keyName: 'wallet-record-filter-coin-all',
                              label: HistoryRecordFilter.all.txt,
                              selected: _draft.coin == null,
                              maxWidth: width,
                              colors: colors,
                              onPressed: () => setState(() {
                                _draft = _draft.copyWith(clearCoin: true);
                              }),
                            ),
                            for (final coin in _coins)
                              _option(
                                keyName: 'wallet-record-filter-coin-$coin',
                                label: coin,
                                selected: _draft.coin == coin,
                                maxWidth: width,
                                colors: colors,
                                onPressed: () => setState(() {
                                  _draft = _draft.copyWith(coin: coin);
                                }),
                              ),
                          ],
                          colors,
                        ),
                        const SizedBox(height: AppTokens.s7),
                        if (widget.journalMode)
                          WalletJournalFilterSections(
                            selection: _draft,
                            fixedBizType: widget.fixedJournalBizType,
                            onChanged: (selection) =>
                                setState(() => _draft = selection),
                            optionBuilder: (key, label, selected, onPressed) =>
                                _option(
                                    keyName: key,
                                    label: label,
                                    selected: selected,
                                    maxWidth: width,
                                    colors: colors,
                                    onPressed: onPressed),
                          )
                        else
                          _section(
                            i18n.t(
                              zhHans: '交易类型',
                              zhHant: '交易類型',
                              en: 'Transaction type',
                              ja: '取引タイプ',
                              ko: '거래 유형',
                            ),
                            [
                              for (final type in HistoryRecordFilter.values)
                                _option(
                                  keyName:
                                      'wallet-record-filter-type-${type.name}',
                                  label: type.txt,
                                  selected: _draft.type == type,
                                  maxWidth: width,
                                  colors: colors,
                                  onPressed: () => setState(() {
                                    _draft = _draft.copyWith(type: type);
                                  }),
                                ),
                            ],
                            colors,
                          ),
                        const SizedBox(height: AppTokens.s7),
                        _section(
                          i18n.t(
                            zhHans: '时间范围',
                            zhHant: '時間範圍',
                            en: 'Time range',
                            ja: '期間',
                            ko: '기간',
                          ),
                          [
                            for (final preset in WalletHistoryDatePreset.values)
                              _option(
                                keyName:
                                    'wallet-record-filter-date-${preset.name}',
                                label:
                                    walletRecordDatePresetLabel(preset, i18n),
                                selected: _draft.month == null &&
                                    _draft.datePreset == preset,
                                maxWidth: width,
                                colors: colors,
                                onPressed: () => setState(() {
                                  _draft = _draft.copyWith(
                                    datePreset: preset,
                                    clearMonth: true,
                                  );
                                }),
                              ),
                          ],
                          colors,
                        ),
                        if (_draft.month case final month?) ...[
                          const SizedBox(height: AppTokens.s4),
                          Text(i18n.format(
                            zhHans: '当前月份：{year}年{month}月',
                            zhHant: '目前月份：{year}年{month}月',
                            en: 'Selected month: {year}-{month}',
                            ja: '選択中の月：{year}年{month}月',
                            ko: '선택한 월: {year}년 {month}월',
                            vars: {'year': month.year, 'month': month.month},
                          )),
                        ],
                        const SizedBox(height: AppTokens.s8),
                        if (stackActions)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              reset,
                              const SizedBox(height: AppTokens.s4),
                              confirm,
                            ],
                          )
                        else
                          Row(
                            children: [
                              Expanded(child: reset),
                              const SizedBox(width: AppTokens.s4),
                              Expanded(child: confirm),
                            ],
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
