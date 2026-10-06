import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart' show AppTokens;

import '../../../history_search/chat_history_search_source.dart';
import '../../../history_search/chat_history_search_strings.dart';
import '../../../history_search/selection/date_availability/chat_history_date_availability_controller.dart';
import 'chat_date_image_calendar.dart';
import 'chat_date_picker_style.dart';

/// Only confirmed days in this conversation can return a jump destination.
Future<DateTime?> showChatDatePicker({
  required BuildContext context,
  required String conversationID,
  required DateTime initialDate,
  DateTime? now,
  ChatHistorySearchSource? source,
  bool Function()? isCurrent,
  bool Function(DateTime)? knownDayHasMessages,
  bool Function(Message)? isRemoved,
}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final tappedDate = DateUtils.dateOnly(initialDate);
  final selectedDate = tappedDate.isAfter(today) ? today : tappedDate;
  final defaultFirstDate = DateTime(2000);
  final firstDate =
      selectedDate.isBefore(defaultFirstDate) ? selectedDate : defaultFirstDate;
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _ChatDatePickerDialog(
      conversationID: conversationID,
      initialDate: selectedDate,
      firstDate: firstDate,
      today: today,
      source: source,
      isCurrent: isCurrent,
      knownDayHasMessages: knownDayHasMessages,
      isRemoved: isRemoved,
    ),
  );
}

class _ChatDatePickerDialog extends StatefulWidget {
  const _ChatDatePickerDialog({
    required this.conversationID,
    required this.initialDate,
    required this.firstDate,
    required this.today,
    this.source,
    this.isCurrent,
    this.knownDayHasMessages,
    this.isRemoved,
  });

  final String conversationID;
  final DateTime initialDate, firstDate, today;
  final ChatHistorySearchSource? source;
  final bool Function()? isCurrent;
  final bool Function(DateTime)? knownDayHasMessages;
  final bool Function(Message)? isRemoved;

  @override
  State<_ChatDatePickerDialog> createState() => _ChatDatePickerDialogState();
}

class _ChatDatePickerDialogState extends State<_ChatDatePickerDialog>
    with WidgetsBindingObserver {
  late final ChatHistoryDateAvailabilityController _dates;
  late final bool Function() _sameSession;
  late DateTime _displayedMonth;
  DateTime? _seed;
  bool _initialPending = true;
  bool _closing = false, _selecting = false, _appActive = true;
  int _calendarVersion = 0, _selectionRevision = 0;

  bool get _current => mounted && !_closing && _appActive && _sameSession();

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
    _displayedMonth =
        DateTime(widget.initialDate.year, widget.initialDate.month);
    _dates = ChatHistoryDateAvailabilityController(
      conversationID: widget.conversationID,
      firstDate: widget.firstDate,
      lastDate: widget.today,
      source: widget.source,
      isCurrent: () => mounted && !_closing && _sameSession(),
      knownDayHasMessages: widget.knownDayHasMessages,
      isRemoved: widget.isRemoved,
      includeDayImages: true,
    )..addListener(_changed);
    unawaited(_loadMonth(_displayedMonth));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _loadMonth(DateTime month, {bool force = false}) async {
    await _dates.loadMonth(month, force: force);
    if (!mounted) return;
    if (!_current) {
      setState(() {});
      return;
    }
    if (_dates.loading ||
        _dates.failed ||
        !DateUtils.isSameMonth(_dates.displayedMonth, month)) {
      return;
    }
    if (_initialPending) {
      _initialPending = false;
      if (_dates.hasMessages(widget.initialDate)) {
        setState(() {
          _seed = widget.initialDate;
          ++_calendarVersion;
        });
      } else if (!DateUtils.isSameMonth(month, widget.today)) {
        _resetCalendar();
      }
    } else if (_seed != null &&
        DateUtils.isSameMonth(_seed, month) &&
        !_dates.hasMessages(_seed!)) {
      _resetCalendar();
    }
  }

  void _resetCalendar() {
    if (!mounted || _closing) return;
    setState(() {
      _seed = null;
      _displayedMonth = DateTime(widget.today.year, widget.today.month);
      ++_calendarVersion;
    });
    unawaited(_loadMonth(_displayedMonth));
  }

  Future<void> _select(DateTime day) async {
    if (!_current || _selecting || _dates.loading || !_dates.hasMessages(day)) {
      if (mounted) setState(() {});
      return;
    }
    final revision = ++_selectionRevision;
    setState(() => _selecting = true);
    final exists = await _dates.verifyDate(day);
    if (!mounted || revision != _selectionRevision) return;
    setState(() => _selecting = false);
    if (!_current || _dates.loading) return;
    if (exists && _dates.hasMessages(day)) {
      _finish(DateUtils.dateOnly(day));
    } else if (!_dates.failed && !_dates.hasMessages(day)) {
      _resetCalendar();
    }
  }

  void _finish([DateTime? date]) {
    if (_closing || !mounted || ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    _closing = true;
    ++_selectionRevision;
    Navigator.of(context).pop(date);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    ++_selectionRevision;
    if (mounted) setState(() => _selecting = false);
    if (_appActive) unawaited(_loadMonth(_displayedMonth, force: true));
  }

  @override
  void dispose() {
    ++_selectionRevision;
    WidgetsBinding.instance.removeObserver(this);
    _dates.removeListener(_changed);
    _dates.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme.copyWith(
      surface: AppTokens.surface(dark: dark),
      onSurface: AppTokens.textPrimary(dark: dark),
      primary: AppTokens.accent,
    );
    final dialogTheme = theme.copyWith(colorScheme: scheme);
    return Theme(
      data: dialogTheme,
      child: Dialog(
        key: const ValueKey('chat-date-picker-dialog'),
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surface.withValues(alpha: 0),
        insetPadding: const EdgeInsets.all(AppTokens.s5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rLg),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: ChatDatePickerStyle.maxWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  key: const ValueKey('chat-date-picker-scroll'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppTokens.s6,
                            AppTokens.s5, AppTokens.s6, AppTokens.s2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              namesRoute: true,
                              child: Text('chatJumpToDate'.tr,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                      fontSize: ChatDatePickerStyle.titleSize,
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface)),
                            ),
                          ],
                        ),
                      ),
                      LayoutBuilder(
                        builder: (context, constraints) =>
                            MediaQuery.withClampedTextScaling(
                          // Follow the native landscape scale limit on narrow
                          // calendars so two-digit days stay on a single line.
                          maxScaleFactor: constraints.maxWidth <
                                  ChatDatePickerStyle.compactWidth
                              ? ChatDatePickerStyle.compactCalendarMaxScale
                              : 3,
                          child: Theme(
                            data:
                                ChatDatePickerStyle.calendarTheme(dialogTheme),
                            child: KeyedSubtree(
                              key: ValueKey(_calendarVersion),
                              child: AbsorbPointer(
                                absorbing: _selecting,
                                child: ChatDateImageCalendar(
                                  key: const ValueKey(
                                      'chat-date-picker-calendar'),
                                  initialDate: _seed != null &&
                                          _current &&
                                          _dates.hasMessages(_seed!)
                                      ? _seed
                                      : null,
                                  firstDate: widget.firstDate,
                                  lastDate: widget.today,
                                  currentDate: widget.today,
                                  selectableDayPredicate: (day) =>
                                      _current && _dates.hasMessages(day),
                                  imageForDate: _dates.imageForDate,
                                  onDateChanged: _select,
                                  onDisplayedMonthChanged: (month) {
                                    _initialPending = false;
                                    _displayedMonth = month;
                                    ++_selectionRevision;
                                    setState(() => _selecting = false);
                                    unawaited(_loadMonth(month, force: true));
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (!_sameSession())
                        Padding(
                          padding: const EdgeInsets.all(AppTokens.s5),
                          child: Text(
                              chatHistorySearchText(context, 'accountChanged')),
                        )
                      else if (_dates.failed)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppTokens.s5),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(chatHistorySearchText(context, 'failed')),
                              TextButton(
                                key: const ValueKey('chat-date-picker-retry'),
                                onPressed: _current && !_selecting
                                    ? () =>
                                        _loadMonth(_displayedMonth, force: true)
                                    : null,
                                child: Text(
                                    chatHistorySearchText(context, 'retry')),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: AppTokens.s2,
                child: _dates.loading || _selecting
                    ? const LinearProgressIndicator(
                        key: ValueKey('chat-date-picker-progress'),
                        color: AppTokens.accent)
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppTokens.s5, AppTokens.s2, AppTokens.s5, AppTokens.s3),
                child: TextButton(
                  key: const ValueKey('chat-date-picker-cancel'),
                  onPressed: () => _finish(),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onSurface,
                    backgroundColor: AppTokens.surfaceAlt(dark: dark),
                    minimumSize:
                        const Size(0, ChatDatePickerStyle.actionHeight),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.rMd),
                    ),
                  ),
                  child:
                      Text(MaterialLocalizations.of(context).cancelButtonLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
