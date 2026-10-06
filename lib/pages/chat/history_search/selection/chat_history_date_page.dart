import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../chat_history_search_source.dart';
import '../chat_history_search_strings.dart';
import 'date_availability/chat_history_date_availability_controller.dart';

class ChatHistoryDatePage extends StatefulWidget {
  const ChatHistoryDatePage({
    super.key,
    required this.conversationID,
    this.source,
    this.initialDate,
    this.isCurrent,
  });

  final String conversationID;
  final ChatHistorySearchSource? source;
  final DateTime? initialDate;
  final bool Function()? isCurrent;

  @override
  State<ChatHistoryDatePage> createState() => _ChatHistoryDatePageState();
}

class _ChatHistoryDatePageState extends State<ChatHistoryDatePage>
    with WidgetsBindingObserver {
  late final DateTime _today = DateUtils.dateOnly(DateTime.now());
  final DateTime _firstDate = DateTime(2000);
  late final ChatHistoryDateAvailabilityController _dates;
  late final bool Function() _sameSession;
  late DateTime _displayedMonth;
  DateTime? _selected;
  DateTime? _pendingInitial;
  int _calendarVersion = 0;
  bool _confirming = false;
  bool _appActive = true;

  bool get _current => mounted && _appActive && _sameSession();

  @override
  void initState() {
    super.initState();
    final guard = widget.isCurrent;
    final offset = DateTime.now().timeZoneOffset;
    if (guard != null) {
      _sameSession = () => guard() && DateTime.now().timeZoneOffset == offset;
    } else {
      final userID = OpenIM.iMManager.userID;
      final token = OpenIM.iMManager.token;
      _sameSession = () =>
          userID.isNotEmpty &&
          OpenIM.iMManager.userID == userID &&
          OpenIM.iMManager.token == token &&
          DateTime.now().timeZoneOffset == offset;
    }
    _appActive = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    final initial = widget.initialDate;
    if (initial != null) {
      final day = DateUtils.dateOnly(initial);
      if (!day.isBefore(_firstDate) && !day.isAfter(_today)) {
        _pendingInitial = day;
      }
    }
    _displayedMonth = DateTime(_today.year, _today.month);
    _dates = ChatHistoryDateAvailabilityController(
      conversationID: widget.conversationID,
      source: widget.source ?? OpenIMChatHistorySearchSource(),
      firstDate: _firstDate,
      lastDate: _today,
      isCurrent: () => mounted && _sameSession(),
    )..addListener(_datesChanged);
    unawaited(_loadMonth(_pendingInitial ?? _displayedMonth));
  }

  void _datesChanged() {
    if (mounted) setState(() {});
  }

  bool _checkCurrent() {
    if (_current) return true;
    if (mounted) setState(() {});
    return false;
  }

  Future<void> _loadMonth(DateTime month, {bool force = false}) async {
    await _dates.loadMonth(month, force: force);
    if (!_checkCurrent() ||
        _dates.loading ||
        _dates.failed ||
        !DateUtils.isSameMonth(_dates.displayedMonth, month)) {
      return;
    }
    final initial = _pendingInitial;
    if (initial != null && DateUtils.isSameMonth(initial, month)) {
      _pendingInitial = null;
      if (_dates.hasMessages(initial)) {
        setState(() {
          _selected = initial;
          _displayedMonth = DateTime(initial.year, initial.month);
          ++_calendarVersion;
        });
      } else if (!DateUtils.isSameMonth(month, _displayedMonth)) {
        unawaited(_loadMonth(_displayedMonth));
      }
    }
    final selected = _selected;
    if (selected != null &&
        DateUtils.isSameMonth(selected, month) &&
        !_dates.hasMessages(selected)) {
      _clearSelection();
    }
  }

  void _clearSelection() {
    if (!mounted) return;
    setState(() {
      _selected = null;
      _displayedMonth = DateTime(_today.year, _today.month);
      ++_calendarVersion;
    });
    unawaited(_loadMonth(_displayedMonth));
  }

  void _chooseDate(DateTime day) {
    if (!_checkCurrent() ||
        _confirming ||
        _dates.loading ||
        _dates.failed ||
        !_dates.hasMessages(day)) {
      return;
    }
    setState(() => _selected = DateUtils.dateOnly(day));
  }

  Future<void> _confirm() async {
    final day = _selected;
    if (!_checkCurrent() ||
        _confirming ||
        _dates.loading ||
        _dates.failed ||
        day == null ||
        !_dates.hasMessages(day)) {
      return;
    }
    setState(() => _confirming = true);
    final exists = await _dates.verifyDate(day);
    if (!mounted) return;
    setState(() => _confirming = false);
    if (!_current || _dates.loading) return;
    if (exists && _dates.hasMessages(day)) {
      Navigator.of(context).pop<DateTime>(day);
    } else if (!_dates.failed && !_dates.hasMessages(day)) {
      _clearSelection();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (mounted) setState(() {});
    if (_appActive) {
      unawaited(_loadMonth(_pendingInitial ?? _displayedMonth, force: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dates.removeListener(_datesChanged);
    _dates.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: GlassAppBar(
        backgroundColor: theme.colorScheme.surface,
        centerTitle: true,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: Styles.c_0089FF),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(chatHistorySearchText(context, 'chooseDate'),
            style: Styles.ts_0C1C33_17sp_semibold),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTokens.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KeyedSubtree(
                key: ValueKey(_calendarVersion),
                child: AbsorbPointer(
                  absorbing: _confirming,
                  child: CalendarDatePicker(
                    key: const ValueKey('chat-history-date-calendar'),
                    initialDate: _selected != null &&
                            _current &&
                            _dates.hasMessages(_selected!)
                        ? _selected
                        : null,
                    firstDate: _firstDate,
                    lastDate: _today,
                    currentDate: _today,
                    selectableDayPredicate: (day) =>
                        _current && _dates.hasMessages(day),
                    onDateChanged: _chooseDate,
                    onDisplayedMonthChanged: (month) {
                      _pendingInitial = null;
                      _displayedMonth = month;
                      unawaited(_loadMonth(month, force: true));
                    },
                  ),
                ),
              ),
              SizedBox(
                height: AppTokens.s2,
                child: _dates.loading || _confirming
                    ? const LinearProgressIndicator()
                    : null,
              ),
              if (!_sameSession())
                Text(chatHistorySearchText(context, 'accountChanged'))
              else if (_dates.failed)
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(chatHistorySearchText(context, 'failed')),
                    TextButton(
                      key: const ValueKey('chat-history-date-retry'),
                      onPressed: _current && !_confirming
                          ? () => _loadMonth(_pendingInitial ?? _displayedMonth,
                              force: true)
                          : null,
                      child: Text(chatHistorySearchText(context, 'retry')),
                    ),
                  ],
                ),
              const SizedBox(height: AppTokens.s5),
              FilledButton(
                key: const ValueKey('chat-history-date-confirm'),
                onPressed: !_current ||
                        _confirming ||
                        _dates.loading ||
                        _dates.failed ||
                        _selected == null ||
                        !_dates.hasMessages(_selected!)
                    ? null
                    : _confirm,
                child: Text(MaterialLocalizations.of(context).okButtonLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
