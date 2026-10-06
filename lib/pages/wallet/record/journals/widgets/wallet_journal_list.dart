import 'dart:async';

import 'package:flutter/material.dart';

import '../../../host/wallet_i18n.dart';
import '../../../widgets/wallet_99chat_tokens.dart';
import '../../../widgets/wallet_page_colors.dart';
import '../../filters/wallet_record_filters.dart';
import '../../wallet_record_models.dart';
import '../../wallet_record_tokens.dart';
import '../../widgets/wallet_record_month_section.dart';
import '../../widgets/wallet_record_row.dart';
import '../wallet_journal_controller.dart';

/// Builds individual ledger rows lazily while preserving month headers.
class WalletJournalList extends StatefulWidget {
  const WalletJournalList({
    super.key,
    required this.controller,
    required this.canLoad,
    required this.emptyContent,
    required this.onMonthChanged,
    required this.onOpenRecord,
    this.selectedFilters,
  });
  final WalletJournalController controller;
  final bool Function() canLoad;
  final Widget emptyContent;
  final Widget? selectedFilters;
  final ValueChanged<String> onMonthChanged;
  final ValueChanged<WalletRecordDto> onOpenRecord;

  @override
  State<WalletJournalList> createState() => _WalletJournalListState();
}

class _WalletJournalListState extends State<WalletJournalList> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_nearEnd);
  }

  void _nearEnd() {
    final pager = widget.controller;
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < 180 &&
        widget.canLoad() &&
        !pager.busy &&
        pager.hasMore &&
        pager.moreError == null &&
        pager.error == null) {
      unawaited(pager.loadMore());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pager = widget.controller;
    final records = widget.canLoad() || pager.isCurrentAccount()
        ? pager.records
        : <WalletRecordDto>[];
    final groups = walletRecordGroupMonths(records);
    final entries = <Object>[
      for (final group in groups) ...[group, ...group.records],
    ];
    final colors = WalletPageColors.of(context);
    final filters = widget.selectedFilters;
    return RefreshIndicator(
      color: colors.blue,
      onRefresh: pager.refresh,
      child: LayoutBuilder(builder: (context, constraints) {
        if (entries.isEmpty) {
          return SingleChildScrollView(
            key: const ValueKey('wallet-record-scroll'),
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(children: [
                if (filters != null) filters,
                widget.emptyContent,
                if (pager.hasMore) _footer(context),
              ]),
            ),
          );
        }
        final prefix =
            (filters == null ? 0 : 1) + (pager.error == null ? 0 : 1);
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: WalletRecordTokens.maxWidth),
            child: ListView.builder(
              key: const ValueKey('wallet-record-scroll'),
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                  AppTokens.s4, AppTokens.s2, AppTokens.s4, AppTokens.s7),
              itemCount: entries.length + prefix + 1,
              itemBuilder: (context, index) {
                if (filters != null && index == 0) return filters;
                if (pager.error != null && index == prefix - 1) {
                  return _retry(context, pager.error!, pager.refresh,
                      'wallet-record-refresh-retry');
                }
                final entryIndex = index - prefix;
                if (entryIndex == entries.length) return _footer(context);
                final entry = entries[entryIndex];
                if (entry is WalletRecordMonthGroup) {
                  return WalletRecordMonthSection(
                    group: entry,
                    months: groups,
                    headerOnly: true,
                    onMonthChanged: widget.onMonthChanged,
                    onOpenRecord: widget.onOpenRecord,
                  );
                }
                final item = entry as WalletRecordDto;
                final first = entryIndex == 0 ||
                    entries[entryIndex - 1] is WalletRecordMonthGroup;
                final last = entryIndex == entries.length - 1 ||
                    entries[entryIndex + 1] is WalletRecordMonthGroup;
                return Material(
                  color: colors.card,
                  clipBehavior: Clip.antiAlias,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(first ? AppTokens.rCard : 0),
                    bottom: Radius.circular(last ? AppTokens.rCard : 0),
                  ),
                  child: Column(children: [
                    if (!first)
                      Divider(
                          height: WalletRecordTokens.divider,
                          thickness: WalletRecordTokens.divider,
                          color: colors.line,
                          indent: AppTokens.s4 +
                              WalletRecordTokens.avatar +
                              AppTokens.s4),
                    WalletRecordRow(
                        item: item, onTap: () => widget.onOpenRecord(item)),
                  ]),
                );
              },
            ),
          ),
        );
      }),
    );
  }

  Widget _footer(BuildContext context) {
    final pager = widget.controller;
    final i18n = AppI18n.of(context);
    if (pager.loadingMore) {
      return Padding(
        padding: const EdgeInsets.all(AppTokens.s5),
        child: Center(
            child: SizedBox.square(
          key: const ValueKey('wallet-journal-more-loading'),
          dimension: AppTokens.s7,
          child: CircularProgressIndicator(
              color: WalletPageColors.of(context).blue),
        )),
      );
    }
    if (pager.moreError != null) {
      return _retry(context, pager.moreError!, pager.loadMore,
          'wallet-journal-more-retry');
    }
    if (!pager.hasMore) return const SizedBox(height: AppTokens.s5);
    return TextButton(
      key: const ValueKey('wallet-journal-load-more'),
      onPressed: widget.canLoad() && !pager.busy ? pager.loadMore : null,
      style: TextButton.styleFrom(
          minimumSize: const Size(0, WalletRecordTokens.minTap)),
      child: Text(i18n.t(
          zhHans: '加载更多',
          zhHant: '載入更多',
          en: 'Load more',
          ja: 'さらに読み込む',
          ko: '더 불러오기')),
    );
  }

  Widget _retry(BuildContext context, String message,
      Future<void> Function() retry, String key) {
    final i18n = AppI18n.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppTokens.s4),
      child: Column(children: [
        Text(message,
            textAlign: TextAlign.center,
            style: TextStyle(color: WalletRecordTokens.muted(context))),
        TextButton(
            key: ValueKey(key),
            onPressed:
                widget.canLoad() && !widget.controller.busy ? retry : null,
            child: Text(i18n.t(
                zhHans: '重试',
                zhHant: '重試',
                en: 'Retry',
                ja: '再試行',
                ko: '다시 시도'))),
      ]),
    );
  }
}
