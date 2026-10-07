import 'dart:async';

import 'package:flutter/material.dart';

import '../data/wallet_fund_api.dart';
import '../data/wallet_history_source_boundary.dart';
import '../data/wallet_session_source.dart';
import '../host/wallet_i18n.dart';
import '../host/wallet_navigation.dart';
import '../order/wallet_order_events.dart';
import '../wallet_repository.dart';
import '../wallet_repository_provider.dart';
import '../widgets/wallet_99chat_tokens.dart';
import '../widgets/wallet_page_colors.dart';
import 'filters/wallet_record_filters.dart';
import 'journals/wallet_journal_controller.dart';
import 'journals/wallet_journal_counterparty_source.dart';
import 'journals/wallet_journal_filters.dart';
import 'journals/wallet_journal_source.dart';
import 'journals/widgets/wallet_journal_list.dart';
import 'journals/widgets/wallet_journal_header.dart';
import 'wallet_record_detail_screen.dart';
import 'wallet_record_models.dart';
import 'wallet_record_tokens.dart';
import 'widgets/wallet_record_direction_tabs.dart';
import 'widgets/wallet_record_empty_content.dart';
import 'widgets/wallet_record_month_section.dart';
import 'widgets/wallet_record_source_notice.dart';

export 'filters/wallet_record_filters.dart' show walletRecordNormalizeCoin;

/// Owns the record request and route lifecycle. Presentation and local filters
/// stay in this module; the existing repository remains the production source.
class WalletRecordScreen extends StatefulWidget {
  const WalletRecordScreen(
      {super.key,
      this.initialCoin,
      this.repository,
      this.depositsOnly = false,
      this.withdrawalsOnly = false})
      : assert(!depositsOnly || !withdrawalsOnly);
  final String? initialCoin;
  final WalletRepository? repository;
  final bool depositsOnly;
  final bool withdrawalsOnly;

  @override
  State<WalletRecordScreen> createState() => _WalletRecordScreenState();
}

class _WalletRecordScreenState extends State<WalletRecordScreen>
    with WidgetsBindingObserver {
  late final WalletRepository _repository;
  late WalletRecordSelection _selection;
  List<WalletRecordDto> _records = const [];
  bool _loading = true;
  bool _failed = false;
  String? _failureMessage;
  Future<void>? _loadFuture;
  StreamSubscription<String>? _recordSubscription;
  bool _routeVisible = true;
  bool _foreground = true;
  bool _dirty = false;
  WalletJournalController? _journals;
  String? get _fixedBizType => widget.depositsOnly
      ? 'deposit'
      : widget.withdrawalsOnly
          ? 'withdraw'
          : null;
  bool get _sameAccount =>
      _repository is! WalletSessionSource ||
      (_repository as WalletSessionSource).isCurrentAccount;
  bool get _active => _routeVisible && _foreground;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? createWalletRepository();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    final source = _repository;
    if (source is WalletSessionSource) {
      final owner = (source as WalletSessionSource).ownerAccountKey;
      _recordSubscription = WalletOrderEvents.recordChanges.listen((key) {
        if (!mounted || key != owner || !_sameAccount) return;
        _dirty = true;
        _consumeRefresh();
      });
    }
    final coin = walletRecordNormalizeCoin(widget.initialCoin ?? '');
    _selection = WalletRecordSelection(coin: coin.isEmpty ? null : coin);
    if (_repository is WalletJournalSource) {
      _journals = WalletJournalController(
        source: _repository as WalletJournalSource,
        query: walletJournalQueryForSelection(_selection,
            now: DateTime.now(), fixedBizType: _fixedBizType),
        isCurrentAccount: () => _sameAccount,
        counterpartySource: _repository is WalletJournalCounterpartySource
            ? _repository as WalletJournalCounterpartySource
            : null,
      )..addListener(_journalChanged);
    }
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeVisible = (ModalRoute.isCurrentOf(context) ?? true) &&
        TickerMode.valuesOf(context).enabled;
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeRefresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _consumeRefresh();
  }

  void _consumeRefresh() {
    if (!mounted ||
        !_active ||
        !_dirty ||
        _loadFuture != null ||
        (_journals?.busy ?? false) ||
        !_sameAccount) {
      return;
    }
    _dirty = false;
    unawaited(_load());
  }

  void _journalChanged() {
    if (!mounted) return;
    final pager = _journals!;
    setState(() {
      _records = pager.records;
      _loading = pager.refreshing && pager.records.isEmpty;
      _failed = pager.error != null && pager.records.isEmpty;
      _failureMessage = pager.error;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeRefresh());
  }

  void _select(WalletRecordSelection selection) {
    setState(() => _selection = selection);
    final pager = _journals;
    if (pager != null) {
      unawaited(pager.updateQuery(walletJournalQueryForSelection(selection,
          now: DateTime.now(), fixedBizType: _fixedBizType)));
    }
  }

  Future<void> _load() =>
      _journals?.refresh() ??
      (_loadFuture ??= _performLoad().whenComplete(() {
        _loadFuture = null;
        _consumeRefresh();
      }));

  Future<void> _performLoad() async {
    if (!mounted || !_sameAccount) return;
    setState(() {
      _loading = _records.isEmpty;
      _failed = false;
      _failureMessage = null;
    });
    try {
      final results = await Future.wait([
        if (!widget.withdrawalsOnly) _repository.getDepositRecords(),
        if (!widget.depositsOnly) _repository.getWithdrawRecords(),
      ]).timeout(const Duration(seconds: 6));
      if (!mounted) return;
      if (!_sameAccount) {
        setState(() {
          _records = const [];
          _loading = false;
        });
        return;
      }
      setState(() {
        _records = List.unmodifiable(results.expand((items) => items));
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (!_sameAccount) {
        setState(() {
          _records = const [];
          _loading = false;
        });
        return;
      }
      setState(() {
        _loading = false;
        // Keep a previously loaded ledger visible when refreshing fails.
        _failed = _records.isEmpty;
        _failureMessage = walletFundErrorMessage(error);
      });
    }
  }

  @override
  void dispose() {
    _recordSubscription?.cancel();
    _journals?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _pickMonth(String key) {
    if (key == 'all') {
      _select(_selection.copyWith(
          clearMonth: true, datePreset: WalletHistoryDatePreset.all));
      return;
    }
    final parts = key.split('-');
    if (parts.length != 2) return;
    final year = int.tryParse(parts[0]), month = int.tryParse(parts[1]);
    if (year == null || month == null || month < 1 || month > 12) return;
    _select(_selection.copyWith(
        month: DateTime(year, month), datePreset: WalletHistoryDatePreset.all));
  }

  @override
  Widget build(BuildContext context) {
    if (_journals != null) return _buildJournalPage(context);
    final colors = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    final coin = _selection.coin;
    final title = coin != null
        ? i18n.t(
            zhHans: '$coin变动',
            zhHant: '$coin變動',
            en: '$coin changes',
            ja: '$coinの変動',
            ko: '$coin 변동')
        : i18n.t(
            zhHans: '历史记录', zhHant: '歷史記錄', en: 'History', ja: '履歴', ko: '기록');
    final titleStyle = Theme.of(context).textTheme.titleLarge!.copyWith(
        fontSize: WalletRecordTokens.title,
        fontWeight: FontWeight.w600,
        color: colors.text);
    final titleWidth =
        (MediaQuery.sizeOf(context).width - kToolbarHeight - AppTokens.s5 * 2)
            .clamp(WalletRecordTokens.minTap, double.infinity);
    final titlePainter = TextPainter(
        text: TextSpan(text: title, style: titleStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context))
      ..layout(maxWidth: titleWidth);
    final toolbarHeight = (titlePainter.height + AppTokens.s4 * 2)
        .clamp(kToolbarHeight, double.infinity);
    final titleLines = titlePainter.computeLineMetrics().length;
    titlePainter.dispose();
    return wrapWalletPage(
        context,
        Scaffold(
          backgroundColor: colors.bg,
          appBar: AppBar(
            leading: const AppBackButton(),
            centerTitle: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: colors.card,
            foregroundColor: colors.text,
            surfaceTintColor: Colors.transparent,
            toolbarHeight: toolbarHeight,
            title: Text(title,
                textAlign: TextAlign.center,
                maxLines: titleLines,
                softWrap: true,
                overflow: TextOverflow.visible,
                style: titleStyle),
          ),
          body: SafeArea(
              top: false,
              child: Column(children: [
                WalletRecordDirectionTabs(
                    selected: _selection.direction,
                    onChanged: (value) => _select(_selection.copyWith(
                        direction: value, clearJournalDirection: true))),
                Expanded(child: _buildBody(context)),
              ])),
        ));
  }

  Widget _buildJournalPage(BuildContext context) {
    final colors = WalletPageColors.of(context);
    return wrapWalletPage(
      context,
      Scaffold(
        backgroundColor: colors.bg,
        appBar: WalletJournalAppBar.forContext(
          context,
          coin: _selection.coin,
        ),
        body: SafeArea(
          top: false,
          child: Column(children: [
            WalletRecordDirectionTabs(
              selected: _selection.direction,
              onChanged: (value) => _select(_selection.copyWith(
                  direction: value, clearJournalDirection: true)),
            ),
            Expanded(child: _buildBody(context)),
          ]),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final pager = _journals;
    if (pager != null) {
      return WalletJournalList(
        key: ValueKey(pager.query),
        controller: pager,
        canLoad: () => _active && _sameAccount,
        emptyContent: _emptyContent(context),
        onMonthChanged: _pickMonth,
        onOpenRecord: (item) => openWalletPage<void>(
          context,
          ListenableBuilder(
            listenable: pager,
            builder: (_, __) => WalletRecordDetailScreen(
              item: pager.records.firstWhere(
                (current) => current.id == item.id,
                orElse: () => item,
              ),
            ),
          ),
          activityPage: 'wallet_order',
        ),
      );
    }
    final colors = WalletPageColors.of(context);
    final now = DateTime.now();
    final filtered = (_sameAccount ? _records : <WalletRecordDto>[])
        .where((item) => _selection.matches(item, now: now))
        .toList();
    final groups = walletRecordGroupMonths(filtered);
    final allMonths = walletRecordGroupMonths(_records
        .where((item) => _selection
            .copyWith(clearMonth: true, datePreset: WalletHistoryDatePreset.all)
            .matches(item, now: now))
        .toList());
    return RefreshIndicator(
      color: colors.blue,
      onRefresh: _load,
      child: LayoutBuilder(builder: (context, constraints) {
        if (_loading || _failed || groups.isEmpty) {
          return SingleChildScrollView(
            key: const ValueKey('wallet-record-scroll'),
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_hasSourceNotice) _sourceNotice,
                  _emptyContent(context),
                ])),
          );
        }
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: WalletRecordTokens.maxWidth),
            child: ListView.builder(
              key: const ValueKey('wallet-record-scroll'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                  AppTokens.s4, AppTokens.s2, AppTokens.s4, AppTokens.s7),
              itemCount: groups.length + (_hasSourceNotice ? 1 : 0),
              itemBuilder: (_, index) {
                if (_hasSourceNotice && index == 0) return _sourceNotice;
                final contentIndex = index - (_hasSourceNotice ? 1 : 0);
                return WalletRecordMonthSection(
                    group: groups[contentIndex],
                    months: allMonths,
                    onMonthChanged: _pickMonth,
                    onOpenRecord: (item) => openWalletPage<void>(
                          context,
                          WalletRecordDetailScreen(item: item),
                          activityPage: 'wallet_order',
                        ));
              },
            ),
          ),
        );
      }),
    );
  }

  bool get _hasSourceNotice =>
      _journals == null && _repository is WalletHistorySourceBoundary;
  Widget get _sourceNotice => WalletRecordSourceNotice(
      source: _repository as WalletHistorySourceBoundary,
      withdrawalsOnly: widget.withdrawalsOnly);

  Widget _emptyContent(BuildContext context) => WalletRecordEmptyContent(
      loading: _loading,
      failed: _failed,
      failureMessage: _failureMessage,
      onRetry: _load);
}
