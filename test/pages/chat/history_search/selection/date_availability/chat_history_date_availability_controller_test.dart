import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_source.dart';
import 'package:openim/pages/chat/history_search/selection/date_availability/chat_history_date_availability_controller.dart';

typedef _SearchCall = ({
  String conversationID,
  ChatHistorySearchQuery query,
  int pageIndex,
  int count,
});

class _Source implements ChatHistorySearchSource {
  _Source(this.respond);
  final FutureOr<List<Message>> Function(_SearchCall) respond;
  final calls = <_SearchCall>[];
  int active = 0;
  int peak = 0;

  @override
  Future<List<Message>> search({
    required String conversationID,
    required ChatHistorySearchQuery query,
    required int pageIndex,
    int count = 30,
  }) async {
    final call = (
      conversationID: conversationID,
      query: query,
      pageIndex: pageIndex,
      count: count,
    );
    calls.add(call);
    ++active;
    if (active > peak) peak = active;
    try {
      return await respond(call);
    } finally {
      --active;
    }
  }
}

Message _message(DateTime time,
        {String id = 'record',
        int status = MessageStatus.succeeded,
        int type = MessageType.text}) =>
    Message(
      clientMsgID: id,
      sendID: 'member',
      sendTime: time.millisecondsSinceEpoch,
      contentType: type,
      status: status,
    );

ChatHistoryDateAvailabilityController _controller(_Source source,
        {DateTime? first, DateTime? last, bool Function()? isCurrent}) =>
    ChatHistoryDateAvailabilityController(
      conversationID: 'current-chat',
      firstDate: first ?? DateTime(2026, 9),
      lastDate: last ?? DateTime(2026, 10, 31),
      source: source,
      isCurrent: isCurrent,
    );

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('only real days with searchable messages can be selected', () async {
    final source = _Source((call) => call.query.startDate!.day == 7
        ? [_message(DateTime(2026, 10, 7, 12))]
        : []);
    final controller = _controller(source);
    addTearDown(controller.dispose);
    await controller.loadMonth(DateTime(2026, 10));
    expect(controller.currentMonth, DateTime(2026, 10));
    expect(controller.displayedMonth, controller.currentMonth);
    expect(controller.hasMessages(DateTime(2026, 10, 7)), isTrue);
    expect(controller.hasMessages(DateTime(2026, 10, 6)), isFalse);
    expect(controller.loading, isFalse);
    expect(controller.failed, isFalse);
    expect(source.calls, hasLength(31));
    for (final call in source.calls) {
      expect(call.conversationID, 'current-chat');
      expect(call.count, 1);
      expect(call.query.startDate, call.query.endDate);
      expect(call.query.sdkMessageTypes,
          ChatHistorySearchQuery.searchableMessageTypes);
      expect(call.query.keyword, isEmpty);
      expect(call.query.searchTimePosition,
          call.query.localEndExclusive!.millisecondsSinceEpoch ~/ 1000);
      expect(
          call.query.searchTimePeriod,
          call.query.localEndExclusive!
              .difference(call.query.localStart!)
              .inSeconds);
    }
  });

  test('never queries days outside first/last bounds or future months',
      () async {
    final source = _Source((_) => []);
    final controller = _controller(source,
        first: DateTime(2026, 10, 5), last: DateTime(2026, 10, 8));
    addTearDown(controller.dispose);
    await controller.loadMonth(DateTime(2026, 10));
    expect(source.calls.map((call) => call.query.startDate!.day), [5, 6, 7, 8]);
    expect(controller.hasMessages(DateTime(2026, 10, 4)), isFalse);
    expect(() => controller.loadMonth(DateTime(2026, 11)), throwsArgumentError);
    expect(await controller.verifyDate(DateTime(2026, 10, 9)), isFalse);
    expect(source.calls, hasLength(4));
  });

  test('same-month work is shared and completed month data is cached',
      () async {
    final pending = Completer<List<Message>>();
    final source = _Source((_) => pending.future);
    final controller = _controller(source,
        first: DateTime(2026, 10, 1), last: DateTime(2026, 10, 3));
    addTearDown(controller.dispose);
    final first = controller.loadMonth(DateTime(2026, 10));
    final same = controller.loadMonth(DateTime(2026, 10, 20));
    expect(identical(first, same), isTrue);
    expect(source.calls, hasLength(3));
    pending.complete([]);
    await first;
    await controller.loadMonth(DateTime(2026, 10));
    expect(source.calls, hasLength(3));
  });

  test('a cached date belongs to its own month when the visible month changes',
      () async {
    final source = _Source((call) => call.query.startDate!.day == 1
        ? [_message(call.query.startDate!.add(const Duration(hours: 12)))]
        : []);
    final controller = _controller(source);
    addTearDown(controller.dispose);
    await controller.loadMonth(DateTime(2026, 10));
    await controller.loadMonth(DateTime(2026, 9));
    expect(controller.hasMessages(DateTime(2026, 10, 1)), isTrue);
    expect(controller.hasMessages(DateTime(2026, 10, 2)), isFalse);
    expect(controller.hasMessages(DateTime(2026, 9, 1)), isTrue);
    final calls = source.calls.length;
    await controller.loadMonth(DateTime(2026, 10));
    expect(source.calls, hasLength(calls));
    expect(controller.currentMonth, DateTime(2026, 10));
  });

  test('force refresh removes old enabled dates until the new result completes',
      () async {
    Completer<List<Message>>? pending;
    final source =
        _Source((call) => pending?.future ?? [_message(call.query.startDate!)]);
    final day = DateTime(2026, 10, 1);
    final controller = _controller(source, first: day, last: day);
    addTearDown(controller.dispose);
    await controller.loadMonth(day);
    expect(controller.hasMessages(day), isTrue);
    pending = Completer<List<Message>>();
    final refreshed = controller.loadMonth(day, force: true);
    expect(controller.loading, isTrue);
    expect(controller.hasMessages(day), isFalse);
    pending.complete([]);
    await refreshed;
    expect(controller.hasMessages(day), isFalse);
  });

  test('rapid month switching keeps old and new in-flight work below three',
      () async {
    final pending = <Completer<List<Message>>>[];
    final source = _Source((_) {
      final completion = Completer<List<Message>>();
      pending.add(completion);
      return completion.future;
    });
    final controller = _controller(source);
    addTearDown(controller.dispose);
    final october = controller.loadMonth(DateTime(2026, 10));
    expect(source.calls, hasLength(3));
    final september = controller.loadMonth(DateTime(2026, 9));
    expect(source.calls, hasLength(3));
    for (var index = 0; index < 3; index++) {
      pending[index].complete([_message(DateTime(2026, 10, index + 1, 12))]);
    }
    await _flush();
    expect(source.calls, hasLength(6));
    expect(
        source.calls.skip(3).every((call) => call.query.startDate!.month == 9),
        isTrue);
    while (controller.loading) {
      for (final response in pending) {
        if (!response.isCompleted) response.complete([]);
      }
      await _flush();
    }
    await Future.wait([october, september]);
    expect(source.peak, lessThanOrEqualTo(3));
    expect(source.calls.where((call) => call.query.startDate!.month == 10),
        hasLength(3));
    expect(controller.currentMonth, DateTime(2026, 9));
    expect(controller.hasMessages(DateTime(2026, 10, 1)), isFalse);
  });

  test('next midnight alone cannot enable the preceding date', () async {
    final day = DateTime(2026, 10, 1);
    final source = _Source(
        (call) => call.pageIndex == 1 ? [_message(DateTime(2026, 10, 2))] : []);
    final controller = _controller(source, first: day, last: day);
    addTearDown(controller.dispose);
    await controller.loadMonth(day);
    expect(controller.hasMessages(day), isFalse);
    expect(source.calls.map((call) => call.pageIndex), [1, 2]);
  });

  test('midnight boundary rows are skipped and the last 999ms are retained',
      () async {
    final day = DateTime(2026, 10, 1);
    final end = DateTime(2026, 10, 2);
    final source = _Source((call) => [
          switch (call.pageIndex) {
            1 => _message(end, id: 'next-day-a'),
            2 => _message(end, id: 'next-day-b'),
            _ => _message(end.subtract(const Duration(milliseconds: 1))),
          },
        ]);
    final controller = _controller(source, first: day, last: day);
    addTearDown(controller.dispose);
    await controller.loadMonth(day);
    expect(controller.hasMessages(day), isTrue);
    expect(source.calls.map((call) => call.pageIndex), [1, 2, 3]);
  });

  test('deleted and unsupported SDK rows cannot enable a day', () async {
    final day = DateTime(2026, 10, 1);
    final source = _Source((call) => switch (call.pageIndex) {
          1 => [_message(day, status: MessageStatus.deleted, id: 'deleted')],
          2 => [_message(day, type: MessageType.typing, id: 'unsupported')],
          _ => [],
        });
    final controller = _controller(source, first: day, last: day);
    addTearDown(controller.dispose);
    await controller.loadMonth(day);
    expect(controller.hasMessages(day), isFalse);
    expect(source.calls, hasLength(3));
  });

  test('invalid local timestamps and a broken cursor fail safely', () async {
    final day = DateTime(2026, 10, 1);
    final source = _Source((_) => [
          Message(clientMsgID: 'same-row', contentType: MessageType.text),
        ]);
    final controller = _controller(source, first: day, last: day);
    addTearDown(controller.dispose);
    await controller.loadMonth(day);
    expect(controller.hasMessages(day), isFalse);
    expect(controller.failed, isTrue);
    expect(controller.loading, isFalse);
    expect(source.calls, hasLength(2));
  });

  test('query errors do not create an empty cache and can be retried',
      () async {
    var fail = true;
    final day = DateTime(2026, 10, 1);
    final source = _Source((_) {
      if (fail) throw StateError('Local history unavailable');
      return [_message(day)];
    });
    final controller = _controller(source, first: day, last: day);
    addTearDown(controller.dispose);
    await controller.loadMonth(day);
    expect(controller.failed, isTrue);
    expect(controller.hasMessages(day), isFalse);
    fail = false;
    await controller.loadMonth(day);
    expect(controller.failed, isFalse);
    expect(controller.hasMessages(day), isTrue);
    expect(source.calls, hasLength(2));
  });

  test('date confirmation rechecks a deletion and updates cached availability',
      () async {
    var deleted = false;
    final day = DateTime(2026, 10, 1);
    final source = _Source((_) => deleted ? [] : [_message(day)]);
    final controller = _controller(source, first: day, last: day);
    addTearDown(controller.dispose);
    await controller.loadMonth(day);
    expect(controller.hasMessages(day), isTrue);
    deleted = true;
    expect(await controller.verifyDate(day), isFalse);
    expect(controller.hasMessages(day), isFalse);
    expect(controller.failed, isFalse);
    deleted = false;
    expect(await controller.verifyDate(day), isTrue);
    expect(controller.hasMessages(day), isTrue);
  });

  test('date confirmation errors disable the stale date and expose retry',
      () async {
    var fail = false;
    final day = DateTime(2026, 10, 1);
    final source = _Source((_) {
      if (fail) throw StateError('SDK unavailable');
      return [_message(day)];
    });
    final controller = _controller(source, first: day, last: day);
    addTearDown(controller.dispose);
    await controller.loadMonth(day);
    fail = true;
    expect(await controller.verifyDate(day), isFalse);
    expect(controller.hasMessages(day), isFalse);
    expect(controller.failed, isTrue);
  });

  test('account invalidation stops queued reads and refuses completed caches',
      () async {
    var current = true;
    final source = _Source((call) => [_message(call.query.startDate!)]);
    final controller = _controller(source, isCurrent: () => current);
    addTearDown(controller.dispose);
    await controller.loadMonth(DateTime(2026, 10));
    final calls = source.calls.length;
    expect(controller.hasMessages(DateTime(2026, 10, 1)), isTrue);
    current = false;
    expect(controller.hasMessages(DateTime(2026, 10, 1)), isFalse);
    current = true;
    await controller.loadMonth(DateTime(2026, 10));
    expect(await controller.verifyDate(DateTime(2026, 10, 1)), isFalse);
    expect(source.calls, hasLength(calls));
  });

  test('an account change during reads ignores results and stops the queue',
      () async {
    var current = true;
    final response = Completer<List<Message>>();
    final source = _Source((_) => response.future);
    final controller = _controller(source, isCurrent: () => current);
    addTearDown(controller.dispose);
    final request = controller.loadMonth(DateTime(2026, 10));
    expect(source.calls, hasLength(3));
    current = false;
    response.complete([_message(DateTime(2026, 10, 1))]);
    await request;
    expect(source.calls, hasLength(3));
    expect(controller.hasMessages(DateTime(2026, 10, 1)), isFalse);
    expect(controller.loading, isFalse);
  });

  test('a date verification finishing after month change cannot mutate cache',
      () async {
    Completer<List<Message>>? verification;
    final day = DateTime(2026, 10, 1);
    final source = _Source((call) =>
        verification?.future ??
        (call.query.startDate!.day == 1
            ? [_message(call.query.startDate!)]
            : []));
    final controller = _controller(source);
    addTearDown(controller.dispose);
    await controller.loadMonth(day);
    verification = Completer<List<Message>>();
    final checked = controller.verifyDate(day);
    final september = controller.loadMonth(DateTime(2026, 9));
    verification.complete([]);
    await september;
    expect(await checked, isFalse);
    expect(controller.hasMessages(day), isTrue);
  });

  test('disposing ignores late results and releases queued work', () async {
    final response = Completer<List<Message>>();
    final source = _Source((_) => response.future);
    final controller = _controller(source);
    var notifications = 0;
    controller.addListener(() => notifications++);
    final request = controller.loadMonth(DateTime(2026, 10));
    expect(notifications, 1);
    controller.dispose();
    response.complete([_message(DateTime(2026, 10, 1))]);
    await request;
    expect(notifications, 1);
    expect(source.calls, hasLength(3));
    expect(controller.hasMessages(DateTime(2026, 10, 1)), isFalse);
  });

  test('leap months and local midnight use calendar construction', () async {
    final source = _Source((_) => []);
    final controller = _controller(source,
        first: DateTime(2024, 2), last: DateTime(2024, 2, 29));
    addTearDown(controller.dispose);
    await controller.loadMonth(DateTime(2024, 2));
    expect(source.calls, hasLength(29));
    final leapDay = source.calls.last.query;
    expect(leapDay.localStart, DateTime(2024, 2, 29));
    expect(leapDay.localEndExclusive, DateTime(2024, 3));
    expect(leapDay.searchTimePosition,
        DateTime(2024, 3).millisecondsSinceEpoch ~/ 1000);
  });
}
