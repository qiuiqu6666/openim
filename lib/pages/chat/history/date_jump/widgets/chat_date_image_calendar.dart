import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart' show AppTokens;

import '../../../history_search/selection/date_availability/chat_date_day_image.dart';
import '../../../media/widgets/chat_video_thumbnail.dart';

/// A chat calendar whose confirmed days can show an existing image thumbnail.
/// Availability and thumbnail choice belong to the caller, not this widget.
class ChatDateImageCalendar extends StatefulWidget {
  const ChatDateImageCalendar({
    super.key,
    this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.currentDate,
    required this.selectableDayPredicate,
    required this.onDateChanged,
    this.onDisplayedMonthChanged,
    this.imageForDate,
  });

  final DateTime? initialDate;
  final DateTime firstDate, lastDate, currentDate;
  final SelectableDayPredicate selectableDayPredicate;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<DateTime>? onDisplayedMonthChanged;
  final ChatDateDayImage? Function(DateTime day)? imageForDate;

  @override
  State<ChatDateImageCalendar> createState() => _ChatDateImageCalendarState();
}

class _ChatDateImageCalendarState extends State<ChatDateImageCalendar> {
  static const _rowHeight = kMinInteractiveDimension;
  static const _circleSize = AppTokens.s8 + AppTokens.s3;
  late DateTime _month;
  DateTime? _selected;
  bool _yearMode = false;
  double _swipeDistance = 0;

  DateTime _day(DateTime value) => DateUtils.dateOnly(value);
  DateTime _monthOf(DateTime value) => DateTime(value.year, value.month);
  DateTime get _firstMonth => _monthOf(widget.firstDate);
  DateTime get _lastMonth => _monthOf(widget.lastDate);

  bool _inRange(DateTime day) =>
      !day.isBefore(_day(widget.firstDate)) &&
      !day.isAfter(_day(widget.lastDate));

  bool _enabled(DateTime day) =>
      _inRange(day) && widget.selectableDayPredicate(day);

  DateTime _clampMonth(DateTime value) {
    final month = _monthOf(value);
    if (month.isBefore(_firstMonth)) return _firstMonth;
    if (month.isAfter(_lastMonth)) return _lastMonth;
    return month;
  }

  @override
  void initState() {
    super.initState();
    assert(!widget.firstDate.isAfter(widget.lastDate));
    final initial = widget.initialDate;
    _month = _clampMonth(initial ?? widget.currentDate);
    _selected =
        initial != null && _enabled(_day(initial)) ? _day(initial) : null;
  }

  @override
  void didUpdateWidget(covariant ChatDateImageCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _month = _clampMonth(_month);
    if (widget.initialDate != oldWidget.initialDate) {
      final initial = widget.initialDate;
      _selected =
          initial != null && _enabled(_day(initial)) ? _day(initial) : null;
      if (initial != null) _month = _clampMonth(initial);
    }
  }

  void _displayMonth(DateTime value) {
    final month = _clampMonth(value);
    final changed = !DateUtils.isSameMonth(_month, month);
    setState(() {
      _month = month;
      _yearMode = false;
    });
    if (changed) widget.onDisplayedMonthChanged?.call(month);
  }

  void _choose(DateTime day) {
    // Check again when invoked, including a semantics or keyboard action.
    if (!_enabled(day)) return;
    setState(() => _selected = day);
    widget.onDateChanged(day);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final previous = DateTime(_month.year, _month.month - 1);
    final next = DateTime(_month.year, _month.month + 1);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
          child: Row(children: [
            Expanded(
              child: TextButton(
                key: const ValueKey('chat-date-image-calendar-month'),
                onPressed: () => setState(() => _yearMode = !_yearMode),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                  minimumSize: const Size(0, _rowHeight),
                  padding: const EdgeInsets.symmetric(horizontal: AppTokens.s3),
                ),
                child: Row(children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(localizations.formatMonthYear(_month),
                          maxLines: 1,
                          softWrap: false,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: AppTokens.captionFontSize,
                              fontWeight: FontWeight.w500)),
                    ),
                  ),
                  Icon(_yearMode ? Icons.arrow_drop_up : Icons.arrow_drop_down),
                ]),
              ),
            ),
            IconButton(
              tooltip: localizations.previousMonthTooltip,
              onPressed: !_yearMode && !previous.isBefore(_firstMonth)
                  ? () => _displayMonth(previous)
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: localizations.nextMonthTooltip,
              onPressed: !_yearMode && !next.isAfter(_lastMonth)
                  ? () => _displayMonth(next)
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ]),
        ),
        if (_yearMode)
          SizedBox(
            height: _rowHeight * 6 + _circleSize,
            child: YearPicker(
              key: const ValueKey('chat-date-image-calendar-years'),
              firstDate: _day(widget.firstDate),
              lastDate: _day(widget.lastDate),
              currentDate: _day(widget.currentDate),
              selectedDate: _month,
              onChanged: (year) =>
                  _displayMonth(DateTime(year.year, _month.month)),
            ),
          )
        else
          _days(context, localizations),
      ],
    );
  }

  Widget _days(BuildContext context, MaterialLocalizations localizations) {
    final firstWeekday = localizations.firstDayOfWeekIndex;
    final offset = (_month.weekday % 7 - firstWeekday + 7) % 7;
    final count = DateUtils.getDaysInMonth(_month.year, _month.month);
    return GestureDetector(
      key: const ValueKey('chat-date-image-calendar-days'),
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => _swipeDistance = 0,
      onHorizontalDragUpdate: (details) => _swipeDistance += details.delta.dx,
      onHorizontalDragCancel: () => _swipeDistance = 0,
      onHorizontalDragEnd: (_) {
        if (_swipeDistance.abs() < kMinInteractiveDimension) return;
        final rtl = Directionality.of(context) == TextDirection.rtl;
        final forward = rtl ? _swipeDistance > 0 : _swipeDistance < 0;
        _displayMonth(DateTime(_month.year, _month.month + (forward ? 1 : -1)));
        _swipeDistance = 0;
      },
      child: Column(children: [
        ExcludeSemantics(
          child: SizedBox(
            height: _circleSize,
            child: Row(children: [
              for (var weekday = 0; weekday < 7; weekday++)
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                          localizations
                              .narrowWeekdays[(weekday + firstWeekday) % 7],
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        for (var row = 0; row < 6; row++)
          Row(children: [
            for (var column = 0; column < 7; column++)
              Expanded(
                child: SizedBox(
                  height: _rowHeight,
                  child: row * 7 + column < offset ||
                          row * 7 + column >= offset + count
                      ? const SizedBox.shrink()
                      : _cell(
                          context,
                          DateTime(_month.year, _month.month,
                              row * 7 + column - offset + 1)),
                ),
              ),
          ]),
      ]),
    );
  }

  Widget _cell(BuildContext context, DateTime day) {
    final enabled = _enabled(day);
    final selected = enabled && DateUtils.isSameDay(_selected, day);
    final today = DateUtils.isSameDay(widget.currentDate, day);
    final localizations = MaterialLocalizations.of(context);
    final label = '${localizations.formatDecimal(day.day)}, '
        '${localizations.formatFullDate(day)}'
        '${today ? ', ${localizations.currentDateLabel}' : ''}';
    return Semantics(
      key: ValueKey<DateTime>(day),
      container: true,
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      onTap: enabled ? () => _choose(day) : null,
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? () => _choose(day) : null,
        excludeFromSemantics: true,
        customBorder: const CircleBorder(),
        child: LayoutBuilder(builder: (context, constraints) {
          final size =
              math.min(_circleSize, constraints.maxWidth - AppTokens.s2);
          final image = enabled ? widget.imageForDate?.call(day) : null;
          return Center(
            child: SizedBox.square(
              dimension: size,
              child: _DateCircle(
                  day: day,
                  image: image,
                  enabledNow: () => _enabled(day),
                  imageIsCurrent: () {
                    if (!_enabled(day)) return false;
                    final current = widget.imageForDate?.call(day);
                    return current?.messageID == image?.messageID &&
                        current?.localPath == image?.localPath &&
                        current?.url == image?.url;
                  },
                  selected: selected,
                  today: today),
            ),
          );
        }),
      ),
    );
  }
}

class _DateCircle extends StatelessWidget {
  const _DateCircle({
    required this.day,
    required this.image,
    required this.enabledNow,
    required this.imageIsCurrent,
    required this.selected,
    required this.today,
  });
  final DateTime day;
  final ChatDateDayImage? image;
  final bool Function() enabledNow, imageIsCurrent;
  final bool selected, today;

  Widget _number(BuildContext context, Color foreground) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.s2),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(MaterialLocalizations.of(context).formatDecimal(day.day),
              maxLines: 1,
              softWrap: false,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: foreground,
                  fontSize: AppTokens.secondaryFontSize,
                  fontWeight: FontWeight.w500)),
        ),
      );

  Widget _plain(BuildContext context) {
    final enabled = enabledNow();
    final isSelected = selected && enabled;
    final scheme = Theme.of(context).colorScheme;
    final foreground = !enabled
        ? scheme.onSurfaceVariant.withValues(alpha: .6)
        : isSelected
            ? AppTokens.onAccent
            : today
                ? AppTokens.accent
                : scheme.onSurface;
    return _ring(
      context,
      ColoredBox(
        color: isSelected ? AppTokens.accent : Colors.transparent,
        child: Center(child: _number(context, foreground)),
      ),
    );
  }

  Widget _ring(BuildContext context, Widget child) {
    final enabled = enabledNow();
    final isSelected = selected && enabled;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: isSelected || today
            ? Border.all(
                color: enabled
                    ? AppTokens.accent
                    : Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: .6),
                width: isSelected ? 2 : 1)
            : null,
      ),
      child: Padding(
        padding: EdgeInsets.all(isSelected
            ? 2
            : today
                ? 1
                : 0),
        child: ClipOval(
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => image == null
      ? _plain(context)
      : LayoutBuilder(
          builder: (context, constraints) => ChatVideoThumbnail(
            key: ValueKey(image!.messageID),
            path: image!.localPath,
            url: image!.url,
            width: constraints.maxWidth,
            fallbackBuilder: _plain,
            imageBuilder: (context, thumbnail) {
              // A decoder can finish after a removal or account change
              // without the calendar itself rebuilding in between.
              if (!imageIsCurrent()) return _plain(context);
              return _ring(
                  context,
                  Stack(
                    fit: StackFit.expand,
                    children: [
                      thumbnail,
                      ColoredBox(
                          color:
                              AppTokens.backgroundDark.withValues(alpha: .65)),
                      Center(child: _number(context, AppTokens.onAccent)),
                    ],
                  ));
            },
          ),
        );
}
