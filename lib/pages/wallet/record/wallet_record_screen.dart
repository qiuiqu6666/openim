import 'package:flutter/material.dart';

import '../host/app_empty_state.dart';
import '../host/wallet_i18n.dart';
import '../host/wallet_navigation.dart';
import '../wallet_repository_provider.dart';
import '../widgets/platform_coin_icon.dart';
import '../widgets/wallet_99chat_scale.dart';
import '../widgets/wallet_99chat_tokens.dart';
import '../widgets/wallet_page_colors.dart';
import 'wallet_record_detail_screen.dart';
import 'wallet_record_models.dart';

String walletRecordNormalizeCoin(String coin) {
  final raw = coin.trim();
  if (raw.isEmpty) return raw;
  if (raw == '元' || raw.toUpperCase() == '99') return '99';
  return raw.toUpperCase();
}

enum _HistoryDatePreset { all, week, month, threeMonths, year }

String _historyDatePresetLabel(_HistoryDatePreset preset) {
  switch (preset) {
    case _HistoryDatePreset.all:
      return AppI18n.current.t(
        zhHans: '全部', zhHant: '全部', en: 'All', ja: 'すべて', ko: '전체');
    case _HistoryDatePreset.week:
      return AppI18n.current.t(
        zhHans: '一周', zhHant: '一週', en: '1 Week', ja: '1週間', ko: '1주');
    case _HistoryDatePreset.month:
      return AppI18n.current.t(
        zhHans: '一月', zhHant: '一月', en: '1 Month', ja: '1ヶ月', ko: '1개월');
    case _HistoryDatePreset.threeMonths:
      return AppI18n.current.t(
        zhHans: '三月', zhHant: '三月', en: '3 Months', ja: '3ヶ月', ko: '3개월');
    case _HistoryDatePreset.year:
      return AppI18n.current.t(
        zhHans: '一年', zhHant: '一年', en: '1 Year', ja: '1年', ko: '1년');
  }
}

DateTimeRange _historyRangeForPreset(_HistoryDatePreset preset) {
  final now = DateTime.now();
  final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
  late final DateTime start;
  switch (preset) {
    case _HistoryDatePreset.all:
      start = DateTime(2000, 1, 1);
      break;
    case _HistoryDatePreset.week:
      start = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 6));
      break;
    case _HistoryDatePreset.month:
      start = DateTime(now.year, now.month - 1, now.day);
      break;
    case _HistoryDatePreset.threeMonths:
      start = DateTime(now.year, now.month - 3, now.day);
      break;
    case _HistoryDatePreset.year:
      start = DateTime(now.year - 1, now.month, now.day);
      break;
  }
  return DateTimeRange(start: start, end: end);
}

class WalletRecordScreen extends StatefulWidget {
  const WalletRecordScreen({super.key, this.initialCoin});

  final String? initialCoin;

  @override
  State<WalletRecordScreen> createState() => _WalletRecordScreenState();
}

class _WalletRecordScreenState extends State<WalletRecordScreen> {
  bool _loading = true;
  String _error = '';
  List<WalletRecordDto> _records = const [];
  HistoryRecordFilter _filter = HistoryRecordFilter.all;
  late String _selectedCoin;
  _HistoryDatePreset _selectedPreset = _HistoryDatePreset.week;

  String _allCoinsLabel() => AppI18n.current.t(
        zhHans: '全部币种',
        zhHant: '全部幣種',
        en: 'All Tokens',
        ja: 'すべての通貨',
        ko: '전체 코인',
      );

  @override
  void initState() {
    super.initState();
    final coin = widget.initialCoin?.trim() ?? '';
    _selectedCoin = coin.isEmpty ? _allCoinsLabel() : walletRecordNormalizeCoin(coin);
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = '';
      });
    }
    try {
      final repo = createWalletRepository();
      final results = await Future.wait([
        repo.getDepositRecords(),
        repo.getWithdrawRecords(),
      ]);
      final combined = <WalletRecordDto>[...results[0], ...results[1]];
      combined.sort((a, b) => b.time.compareTo(a.time));
      if (!mounted) return;
      setState(() {
        _records = combined;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _records = const [];
        _loading = false;
        _error = AppI18n.current.t(
          zhHans: '加载失败', zhHant: '載入失敗', en: 'Load failed', ja: '読み込みに失敗しました', ko: '불러오기에 실패했습니다');
      });
    }
  }

  List<String> get _coinOptions {
    final values = <String>{_allCoinsLabel()};
    for (final item in _records) {
      final coin = walletRecordNormalizeCoin(item.coin);
      if (coin.isNotEmpty) values.add(coin);
    }
    // Product metadata stays visible even when the backend has no records.
    values.addAll(const ['99', 'USDT']);
    return values.toList(growable: false);
  }

  bool _matchesType(WalletRecordDto item) {
    switch (_filter) {
      case HistoryRecordFilter.all:
        return true;
      case HistoryRecordFilter.chainWithdraw:
        return item.isChainWithdraw;
      case HistoryRecordFilter.chainDeposit:
        return item.isChainDeposit;
      case HistoryRecordFilter.internalDeposit:
        return item.isInternalReceive;
      case HistoryRecordFilter.internalWithdraw:
        return item.isInternalTransfer;
      case HistoryRecordFilter.redPacket:
        return item.type == WalletRecordType.redPacket && !item.isRedPacketRefund;
      case HistoryRecordFilter.redPacketRefund:
        return item.isRedPacketRefund;
      case HistoryRecordFilter.transfer:
        return item.type == WalletRecordType.transfer || item.type == WalletRecordType.receive;
      case HistoryRecordFilter.transferRefund:
        return item.title.contains('退款') || item.title.toLowerCase().contains('refund');
    }
  }

  bool _matchesDate(WalletRecordDto item) {
    final parsed = DateTime.tryParse(item.time.trim());
    if (parsed == null) return true;
    final range = _historyRangeForPreset(_selectedPreset);
    final local = parsed.toLocal();
    return !local.isBefore(range.start) && !local.isAfter(range.end);
  }

  List<WalletRecordDto> get _filteredRecords {
    return _records.where((item) {
      final coin = walletRecordNormalizeCoin(item.coin);
      final coinMatches = _selectedCoin == _allCoinsLabel() || coin == _selectedCoin;
      return coinMatches && _matchesType(item) && _matchesDate(item);
    }).toList(growable: false);
  }

  Future<void> _pickFilter() async {
    final selected = await showModalBottomSheet<HistoryRecordFilter>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _HistoryFilterSheet(selected: _filter),
    );
    if (!mounted || selected == null) return;
    setState(() => _filter = selected);
  }

  Future<void> _pickCoin() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CoinPickerSheet(
        options: _coinOptions,
        selectedCoin: _selectedCoin,
        allCoinsLabel: _allCoinsLabel(),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _selectedCoin = selected);
  }

  Future<void> _pickDatePreset() async {
    final i18n = AppI18n.of(context);
    final selected = await showModalBottomSheet<_HistoryDatePreset>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DatePresetSheet(
        title: i18n.t(
          zhHans: '选择时间范围',
          zhHant: '選擇時間範圍',
          en: 'Select Date Range',
          ja: '期間を選択',
          ko: '기간 선택',
        ),
        selected: _selectedPreset,
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _selectedPreset = selected);
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final cs = WalletPageColors.of(context);
    final appBar = WalletAppBarColors.of(context);
    return wrapWalletPage(
      context,
      Scaffold(
        backgroundColor: cs.bg,
        appBar: AppBar(
          leading: const AppBackButton(),
          centerTitle: true,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          backgroundColor: appBar.background,
          foregroundColor: appBar.title,
          systemOverlayStyle: walletPageOverlayStyle(context),
          leadingWidth: 54,
          title: Text(
            i18n.t(
              zhHans: '历史', zhHant: '歷史', en: 'History', ja: '履歴', ko: '기록'),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: appBar.title,
            ),
          ),
          actions: [
            IconButton(
              onPressed: _pickFilter,
              icon: Icon(Icons.tune_rounded, color: appBar.icon, size: 24),
            ),
            SizedBox(width: 10.w99),
          ],
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              _HistoryExtraFilterBar(
                coinText: _selectedCoin,
                dateRangeText: _historyDatePresetLabel(_selectedPreset),
                onCoinTap: _pickCoin,
                onDateTap: _pickDatePreset,
              ),
              Expanded(child: _buildBody(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: cs.blue));
    }
    if (_error.isNotEmpty) {
      return AppEmptyState(message: _error, onRetry: _load);
    }
    final records = _filteredRecords;
    if (records.isEmpty) {
      return AppEmptyState(
        message: i18n.t(
          zhHans: '暂无记录',
          zhHant: '暫無記錄',
          en: 'No records',
          ja: '記録はありません',
          ko: '기록이 없습니다',
        ),
      );
    }
    return RefreshIndicator(
      color: cs.blue,
      onRefresh: _load,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(24.w99, 18.h99, 24.w99, 54.h99),
        itemCount: records.length,
        itemBuilder: (_, index) {
          final item = records[index];
          final time = DateTime.tryParse(item.time.trim())?.toLocal();
          final previous = index == 0
              ? null
              : DateTime.tryParse(records[index - 1].time.trim())?.toLocal();
          final showDate = index == 0 ||
              time == null ||
              previous == null ||
              time.year != previous.year ||
              time.month != previous.month ||
              time.day != previous.day;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showDate)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    6.w99,
                    index == 0 ? 0 : 24.h99,
                    6.w99,
                    15.h99,
                  ),
                  child: Text(
                    time == null
                        ? '--'
                        : '${time.month.toString().padLeft(2, '0')}月${time.day.toString().padLeft(2, '0')}日',
                    style: TextStyle(
                      fontSize: 25.5.sp99,
                      fontWeight: FontWeight.w700,
                      color: cs.subText,
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.only(bottom: 18.h99),
                child: _RecordCard(
                  item: item,
                  onTap: () => openWalletPage<void>(
                    context,
                    WalletRecordDetailScreen(item: item),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HistoryExtraFilterBar extends StatelessWidget {
  const _HistoryExtraFilterBar({
    required this.coinText,
    required this.dateRangeText,
    required this.onCoinTap,
    required this.onDateTap,
  });

  final String coinText;
  final String dateRangeText;
  final VoidCallback onCoinTap;
  final VoidCallback onDateTap;

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(36.w99, 27.h99, 36.w99, 9.h99),
      child: Row(
        children: [
          GestureDetector(
            onTap: onCoinTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 66.h99,
              padding: EdgeInsets.symmetric(horizontal: 24.w99),
              decoration: BoxDecoration(
                color: cs.filterInactiveBg,
                borderRadius: BorderRadius.circular(33.r99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    coinText,
                    style: TextStyle(
                      fontSize: 27.sp99,
                      fontWeight: FontWeight.w500,
                      color: cs.filterInactiveText,
                    ),
                  ),
                  SizedBox(width: 12.w99),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 42.sp99,
                    color: cs.subText,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: 18.w99),
          const Spacer(),
          GestureDetector(
            onTap: onDateTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 66.h99,
              padding: EdgeInsets.symmetric(horizontal: 24.w99),
              decoration: BoxDecoration(
                color: cs.filterInactiveBg,
                borderRadius: BorderRadius.circular(33.r99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dateRangeText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 27.sp99,
                      fontWeight: FontWeight.w500,
                      color: cs.filterInactiveText,
                    ),
                  ),
                  SizedBox(width: 12.w99),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 42.sp99,
                    color: cs.subText,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.item, required this.onTap});

  final WalletRecordDto item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final amountColor = item.income
        ? const Color(0xFF0BA36E)
        : (item.status == WalletRecordStatus.failed ? cs.red : cs.text);
    final rawCoin = walletRecordNormalizeCoin(item.coin);
    final platformCoin = rawCoin == '99';
    final title = item.title.trim().isEmpty ? item.type.txt : item.title.trim();
    final subLine = item.subTitle.trim().isNotEmpty
        ? item.subTitle.trim()
        : (item.time.trim().isEmpty ? '--' : item.time.trim());
    final sign = item.income ? '+' : '-';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.rCard.r99),
      child: Container(
        padding: EdgeInsets.fromLTRB(24.w99, 24.h99, 24.w99, 24.h99),
        decoration: BoxDecoration(
          color: cs.card,
          borderRadius: BorderRadius.circular(AppTokens.rCard.r99),
          border: Border.all(color: cs.line, width: 0.5),
        ),
        child: Row(
          children: [
            _CoinIcon(item: item),
            SizedBox(width: 21.w99),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 27.sp99,
                      color: cs.text,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  SizedBox(height: 9.h99),
                  Text(
                    subLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 21.sp99,
                      color: cs.subText,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 18.w99),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      platformCoin
                          ? '$sign${item.amount}'
                          : '$sign${item.amount} $rawCoin',
                      style: TextStyle(
                        fontSize: 27.sp99,
                        color: amountColor,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    if (platformCoin) ...[
                      SizedBox(width: 8.w99),
                      PlatformCoinIcon(size: 27.w99, imageScale: 1.28),
                    ],
                  ],
                ),
                SizedBox(height: 9.h99),
                Text(
                  item.status.txt,
                  style: TextStyle(
                    fontSize: 21.sp99,
                    color: item.status == WalletRecordStatus.failed
                        ? cs.red
                        : cs.subText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryFilterSheet extends StatelessWidget {
  const _HistoryFilterSheet({required this.selected});

  final HistoryRecordFilter selected;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final items = HistoryRecordFilter.values
        .where((e) => e != HistoryRecordFilter.transferRefund)
        .toList();
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final cs = WalletPageColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: cs.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.r99)),
      ),
      padding: EdgeInsets.fromLTRB(24.w99, 22.h99, 24.w99, 28.h99 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            i18n.t(
              zhHans: '选择类型',
              zhHant: '選擇類型',
              en: 'Select Type',
              ja: '種類を選択',
              ko: '유형 선택',
            ),
            style: TextStyle(
              fontSize: 23.sp99,
              fontWeight: FontWeight.w700,
              color: cs.text,
            ),
          ),
          SizedBox(height: 20.h99),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12.w99,
              mainAxisSpacing: 12.h99,
              childAspectRatio: 2.15,
            ),
            itemBuilder: (_, i) {
              final item = items[i];
              final active = item == selected;
              return GestureDetector(
                onTap: () => Navigator.of(context).pop(item),
                child: Container(
                  alignment: Alignment.center,
                  padding: EdgeInsets.symmetric(
                    horizontal: 10.w99,
                    vertical: 12.h99,
                  ),
                  decoration: BoxDecoration(
                    color: active ? cs.filterActiveBg : cs.filterInactiveBg,
                    borderRadius: BorderRadius.circular(14.r99),
                    border: Border.all(
                      color: active
                          ? cs.filterActiveBorder
                          : cs.line.withValues(alpha: 0.55),
                      width: active ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    item.txt,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20.sp99,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? cs.filterActiveText
                          : cs.filterInactiveText,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CoinPickerSheet extends StatefulWidget {
  const _CoinPickerSheet({
    required this.options,
    required this.selectedCoin,
    required this.allCoinsLabel,
  });

  final List<String> options;
  final String selectedCoin;
  final String allCoinsLabel;

  @override
  State<_CoinPickerSheet> createState() => _CoinPickerSheetState();
}

class _CoinPickerSheetState extends State<_CoinPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<String> get _filteredCoins {
    final keyword = _query.trim().toUpperCase();
    final list = widget.options.where((e) => e != widget.allCoinsLabel);
    if (keyword.isEmpty) return list.toList();
    return list.where((e) => e.toUpperCase().contains(keyword)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    return FractionallySizedBox(
      heightFactor: 0.4,
      child: Container(
        decoration: BoxDecoration(
          color: cs.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(39.r99)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              SizedBox(height: 15.h99),
              Container(
                width: 111.w99,
                height: 9.h99,
                decoration: BoxDecoration(
                  color: cs.line,
                  borderRadius: BorderRadius.circular(99.r99),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(30.w99, 27.h99, 30.w99, 12.h99),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        i18n.t(
                          zhHans: '选择币种',
                          zhHant: '選擇幣種',
                          en: 'Select Token',
                          ja: '通貨を選択',
                          ko: '코인 선택',
                        ),
                        style: TextStyle(
                          fontSize: 31.5.sp99,
                          fontWeight: FontWeight.w600,
                          color: cs.text,
                        ),
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(30.r99),
                      onTap: () => Navigator.of(context).pop(),
                      child: Padding(
                        padding: EdgeInsets.all(6.w99),
                        child: Icon(
                          Icons.close_rounded,
                          size: 39.sp99,
                          color: cs.subText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(30.w99, 15.h99, 30.w99, 18.h99),
                child: Container(
                  height: 78.h99,
                  decoration: BoxDecoration(
                    color: cs.inputFill,
                    borderRadius: BorderRadius.circular(21.r99),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _query = v),
                    cursorColor: cs.inputCursor,
                    style: TextStyle(
                      fontSize: 25.5.sp99,
                      color: cs.text,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 36.sp99,
                        color: cs.subText,
                      ),
                      hintText: i18n.t(
                        zhHans: '搜索',
                        zhHant: '搜尋',
                        en: 'Search',
                        ja: '検索',
                        ko: '검색',
                      ),
                      hintStyle: TextStyle(
                        fontSize: 25.5.sp99,
                        color: cs.inputHint,
                      ),
                      contentPadding: EdgeInsets.symmetric(vertical: 21.h99),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(30.w99, 9.h99, 30.w99, 24.h99),
                  children: [
                    _CoinSheetRow(
                      title: widget.allCoinsLabel,
                      selected: widget.selectedCoin == widget.allCoinsLabel,
                      onTap: () =>
                          Navigator.of(context).pop(widget.allCoinsLabel),
                    ),
                    ..._filteredCoins.map(
                      (coin) => _CoinSheetRow(
                        title: coin,
                        selected: coin == widget.selectedCoin,
                        icon: _CoinSheetIcon(coin: coin),
                        onTap: () => Navigator.of(context).pop(coin),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoinSheetRow extends StatelessWidget {
  const _CoinSheetRow({
    required this.title,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String title;
  final bool selected;
  final Widget? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(21.r99),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 22.5.h99),
        child: Row(
          children: [
            if (icon != null) ...[
              icon!,
              SizedBox(width: 24.w99),
            ],
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 27.sp99,
                  fontWeight: FontWeight.w500,
                  color: cs.text,
                ),
              ),
            ),
            if (selected) Icon(Icons.check_rounded, color: cs.blue),
          ],
        ),
      ),
    );
  }
}

class _CoinSheetIcon extends StatelessWidget {
  const _CoinSheetIcon({required this.coin});

  final String coin;

  @override
  Widget build(BuildContext context) {
    return _CoinIcon(
      item: WalletRecordDto(
        id: '',
        type: WalletRecordType.all,
        status: WalletRecordStatus.success,
        title: '',
        subTitle: '',
        amount: '',
        coin: coin,
        income: true,
        network: '',
        fee: '',
        payer: '',
        payee: '',
        addr: '',
        hash: '',
        block: '',
        time: '',
        orderNo: '',
        memo: '',
      ),
    );
  }
}

class _CoinIcon extends StatelessWidget {
  const _CoinIcon({required this.item});

  final WalletRecordDto item;

  @override
  Widget build(BuildContext context) {
    final upper = walletRecordNormalizeCoin(item.coin);
    final size = 75.w99;
    if (upper == '99') {
      return PlatformCoinIcon(size: size);
    }
    if (upper == 'USDT') {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFF26A17B),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: CustomPaint(
          size: Size(size * 0.62, size * 0.62),
          painter: _UsdtCoinPainter(),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFF5B8CFF),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        upper.isEmpty ? '?' : upper.substring(0, 1),
        style: TextStyle(
          fontSize: 33.sp99,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}

class _UsdtCoinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.08
      ..strokeCap = StrokeCap.round;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.08, h * 0.12, w * 0.84, h * 0.16),
        Radius.circular(w * 0.02),
      ),
      fill,
    );
    final stem = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.41, h * 0.12, w * 0.18, h * 0.76),
      Radius.circular(w * 0.02),
    );
    canvas.drawRRect(stem, fill);
    final oval = Rect.fromCenter(
      center: Offset(w / 2, h * 0.53),
      width: w * 0.92,
      height: h * 0.28,
    );
    canvas.drawArc(oval, 0.06, 6.16, false, stroke);
    final cover = Paint()
      ..color = const Color(0xFF26A17B)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(w * 0.35, h * 0.43, w * 0.30, h * 0.13),
      cover,
    );
    canvas.drawRRect(stem, fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DatePresetSheet extends StatelessWidget {
  const _DatePresetSheet({required this.title, required this.selected});

  final String title;
  final _HistoryDatePreset selected;

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: cs.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.r99)),
      ),
      padding: EdgeInsets.fromLTRB(24.w99, 22.h99, 24.w99, 28.h99 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 23.sp99,
              fontWeight: FontWeight.w700,
              color: cs.text,
            ),
          ),
          SizedBox(height: 20.h99),
          for (final value in _HistoryDatePreset.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _historyDatePresetLabel(value),
                style: TextStyle(color: cs.text, fontSize: 27.sp99),
              ),
              trailing: value == selected
                  ? Icon(Icons.check_rounded, color: cs.blue)
                  : null,
              onTap: () => Navigator.of(context).pop(value),
            ),
        ],
      ),
    );
  }
}
