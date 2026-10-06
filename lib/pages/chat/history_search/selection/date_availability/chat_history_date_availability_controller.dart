import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import '../../chat_history_search_source.dart';
import 'chat_date_day_image.dart';
import 'chat_date_day_image_sampler.dart';

/// Confirms message existence for visible calendar days using local SDK queries.
/// A single queue also bounds requests still running after a month is changed.
class ChatHistoryDateAvailabilityController extends ChangeNotifier {
  ChatHistoryDateAvailabilityController({
    required this.conversationID,
    required DateTime firstDate,
    required DateTime lastDate,
    ChatHistorySearchSource? source,
    bool Function()? isCurrent,
    bool Function(DateTime day)? knownDayHasMessages,
    bool Function(Message message)? isRemoved,
    this.includeDayImages = false,
    int Function(int length)? chooseImageIndex,
  })  : firstDate = _day(firstDate),
        lastDate = _day(lastDate),
        source = source ?? OpenIMChatHistorySearchSource(),
        _isCurrent = isCurrent ?? _alwaysCurrent,
        _knownDayHasMessages = knownDayHasMessages,
        _isRemoved = isRemoved ?? _neverRemoved,
        _displayedMonth = _month(lastDate) {
    if (conversationID.trim().isEmpty ||
        this.lastDate.isBefore(this.firstDate)) {
      throw ArgumentError(
          'A conversation and valid calendar range are required.');
    }
    _imageSampler = ChatDateDayImageSampler(
      source: this.source,
      isRemoved: _isRemoved,
      chooseIndex: chooseImageIndex,
    );
  }

  static const maxConcurrent = 3;
  final String conversationID;
  final DateTime firstDate, lastDate;
  final ChatHistorySearchSource source;
  final bool includeDayImages;
  final bool Function() _isCurrent;
  final bool Function(DateTime day)? _knownDayHasMessages;
  final bool Function(Message message) _isRemoved;
  final _months = <DateTime, Set<DateTime>>{};
  final _dayImages = <DateTime, Message>{};
  late final ChatDateDayImageSampler _imageSampler;
  final _queue = Queue<_DayProbe>();
  DateTime _displayedMonth;
  Future<void>? _monthRequest;
  int _generation = 0;
  int _active = 0;
  bool _loading = false;
  bool _failed = false;
  bool _disposed = false;
  bool _sessionInvalidated = false;

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);
  static DateTime _month(DateTime value) => DateTime(value.year, value.month);
  static bool _alwaysCurrent() => true;
  static bool _neverRemoved(Message message) => false;

  bool get _usable {
    if (_disposed || _sessionInvalidated) return false;
    if (!_isCurrent()) {
      _sessionInvalidated = true;
      _months.clear();
      _dayImages.clear();
      return false;
    }
    return true;
  }

  DateTime get displayedMonth => _displayedMonth;
  DateTime get currentMonth => displayedMonth;
  bool get loading => _usable && _loading;
  bool get failed => _usable && _failed;

  bool _inRange(DateTime day) =>
      !day.isBefore(firstDate) && !day.isAfter(lastDate);

  bool hasMessages(DateTime value) {
    final day = _day(value);
    return _usable &&
        _inRange(day) &&
        (_months[_month(day)]?.contains(day) ?? false);
  }

  ChatDateDayImage? imageForDate(DateTime value) {
    final day = _day(value);
    if (!includeDayImages || !hasMessages(day)) return null;
    final message = _dayImages[day];
    if (message == null) return null;
    try {
      return ChatDateDayImage.fromMessage(message,
          day: day, isRemoved: _isRemoved);
    } catch (_) {
      return null;
    }
  }

  Future<void> loadMonth(DateTime value, {bool force = false}) {
    if (!_usable) return Future.value();
    final month = _month(value);
    if (month.isBefore(_month(firstDate)) || month.isAfter(_month(lastDate))) {
      throw ArgumentError.value(value, 'month', 'Outside the calendar range');
    }
    if (!force && _displayedMonth == month && _monthRequest != null) {
      return _monthRequest!;
    }
    final generation = ++_generation;
    _discardQueued();
    _displayedMonth = month;
    _failed = false;
    if (force) _months.remove(month);
    if (_months.containsKey(month)) {
      _loading = false;
      _monthRequest = null;
      notifyListeners();
      return Future.value();
    }
    final completed = Completer<void>();
    _monthRequest = completed.future;
    _loading = true;
    notifyListeners();
    unawaited(_loadMonth(month, generation, completed));
    return completed.future;
  }

  Future<void> _loadMonth(
      DateTime month, int generation, Completer<void> completed) async {
    final days = <DateTime>[];
    final nextMonth = DateTime(month.year, month.month + 1);
    for (var day = month;
        day.isBefore(nextMonth);
        day = DateTime(day.year, day.month, day.day + 1)) {
      if (_inRange(day)) days.add(day);
    }
    final results = await Future.wait([
      for (final day in days)
        _enqueue(day, generation, loadImage: includeDayImages),
    ]);
    if (_current(generation)) {
      _failed = results.contains(_DayResult.failed);
      if (!_failed && !results.contains(_DayResult.stale)) {
        _months[month] = {
          for (var index = 0; index < days.length; index++)
            if (results[index] == _DayResult.present) days[index],
        };
      }
      _loading = false;
      _monthRequest = null;
      notifyListeners();
    }
    completed.complete();
  }

  /// Rechecks the selected date immediately before opening its results.
  Future<bool> verifyDate(DateTime value) async {
    final day = _day(value);
    if (!_usable || !_inRange(day)) return false;
    final generation = _generation;
    final result = await _enqueue(day, generation);
    if (!_current(generation)) return false;
    final dates = _months[_month(day)];
    if (result == _DayResult.present) {
      dates?.add(day);
    } else {
      dates?.remove(day);
      _dayImages.remove(day);
    }
    _failed = result == _DayResult.failed;
    notifyListeners();
    return result == _DayResult.present;
  }

  bool _current(int generation) => _usable && generation == _generation;

  Future<_DayResult> _enqueue(DateTime day, int generation,
      {bool loadImage = false}) {
    if (!_current(generation)) return Future.value(_DayResult.stale);
    final probe = _DayProbe(day, generation, loadImage);
    _queue.add(probe);
    _drain();
    return probe.completed.future;
  }

  void _drain() {
    while (_active < maxConcurrent && _queue.isNotEmpty) {
      final probe = _queue.removeFirst();
      if (!_current(probe.generation)) {
        probe.completed.complete(_DayResult.stale);
        continue;
      }
      ++_active;
      unawaited(_probe(probe));
    }
  }

  Future<void> _probe(_DayProbe probe) async {
    var result = _DayResult.stale;
    try {
      final query = ChatHistorySearchQuery(
        startDate: probe.day,
        endDate: probe.day,
      ).snapshot();
      // The SDK's upper bound is inclusive. Keep next midnight to retain the
      // final 999ms of the day, then skip adjacent-day rows before deciding.
      var pageIndex = 1;
      final seen = <String>{};
      while (_current(probe.generation)) {
        // A timeline can already contain real message types which this SDK's
        // search filter excludes. Re-read its guarded records for each probe.
        if (_knownDayHasMessages?.call(probe.day) == true) {
          result = _DayResult.present;
          break;
        }
        final messages = await source.search(
          conversationID: conversationID,
          query: query,
          pageIndex: pageIndex++,
          count: 1,
        );
        if (!_current(probe.generation)) break;
        if (_knownDayHasMessages?.call(probe.day) == true ||
            messages.any((message) =>
                query.accepts(message) &&
                query.sdkMessageTypes.contains(message.contentType) &&
                (message.status == null ||
                    message.status! <= MessageStatus.failed) &&
                !_isRemoved(message))) {
          result = _DayResult.present;
          break;
        }
        if (messages.isEmpty) {
          result = _DayResult.empty;
          break;
        }
        for (final message in messages) {
          final id = message.clientMsgID;
          if (id != null && id.isNotEmpty && !seen.add(id)) {
            throw StateError('The date search cursor did not advance.');
          }
        }
      }
      if (_current(probe.generation) && probe.loadImage) {
        if (result == _DayResult.present) {
          final image = await _imageSampler.sample(
            conversationID: conversationID,
            day: probe.day,
            isCurrent: () => _current(probe.generation),
            preferred: _dayImages[probe.day],
          );
          if (!_current(probe.generation)) {
            result = _DayResult.stale;
          } else if (image != null) {
            _dayImages[probe.day] = image;
          } else {
            _dayImages.remove(probe.day);
          }
        } else {
          _dayImages.remove(probe.day);
        }
      }
    } catch (_) {
      if (_current(probe.generation)) result = _DayResult.failed;
    } finally {
      --_active;
      probe.completed.complete(result);
      _drain();
    }
  }

  void _discardQueued() {
    while (_queue.isNotEmpty) {
      _queue.removeFirst().completed.complete(_DayResult.stale);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _months.clear();
    _dayImages.clear();
    _discardQueued();
    super.dispose();
  }
}

enum _DayResult { present, empty, failed, stale }

class _DayProbe {
  _DayProbe(this.day, this.generation, this.loadImage);
  final DateTime day;
  final int generation;
  final bool loadImage;
  final completed = Completer<_DayResult>();
}
