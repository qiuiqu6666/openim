import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/date_jump/chat_date_jump_controller.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_source.dart';
import 'package:openim/pages/chat/history_search/selection/date_availability/chat_history_date_availability_controller.dart';

final _day = DateTime(2026, 10, 4);
final _nextDay = DateTime(2026, 10, 5);

Message _message(String id, DateTime time, {int type = MessageType.text}) =>
    Message(
      clientMsgID: id,
      contentType: type,
      sendTime: time.millisecondsSinceEpoch,
      status: MessageStatus.succeeded,
    );

typedef _Call = ({ChatHistorySearchQuery query, int pageIndex});

class _Source implements ChatHistorySearchSource {
  final calls = <_Call>[];
  FutureOr<List<Message>> Function(_Call)? respond;

  @override
  Future<List<Message>> search({
    required String conversationID,
    required ChatHistorySearchQuery query,
    required int pageIndex,
    int count = 30,
  }) async {
    expect(conversationID, 'current-chat');
    expect(count, 1);
    final call = (query: query, pageIndex: pageIndex);
    calls.add(call);
    return await (respond?.call(call) ?? []);
  }
}

class _Fixture {
  _Fixture() {
    jump = ChatDateJumpController(
      conversationID: () => 'current-chat',
      isClosed: () => !current,
      isRemoved: (message) => removed.contains(message.clientMsgID),
      messages: () => loaded,
      search: (
          {required conversationID,
          required messageTypeList,
          required searchTimePosition,
          required searchTimePeriod,
          required pageIndex,
          required count}) async {
        jumpSearches++;
        return SearchResult(totalCount: 0, searchResultItems: []);
      },
      jumpToMessage: (_, message, __) => opened.add(message),
      showFeedback: feedback.add,
      runLoading: (operation) => operation(),
    );
    dates = ChatHistoryDateAvailabilityController(
      conversationID: 'current-chat',
      firstDate: _day,
      lastDate: _day,
      source: source,
      isCurrent: () => current,
      knownDayHasMessages: jump.hasLoadedMessagesOn,
      isRemoved: (message) => removed.contains(message.clientMsgID),
    );
  }

  bool current = true;
  int jumpSearches = 0;
  final loaded = <Message>[];
  final removed = <String>{};
  final opened = <Message>[];
  final feedback = <String>[];
  final source = _Source();
  late final ChatDateJumpController jump;
  late final ChatHistoryDateAvailabilityController dates;
}

void main() {
  for (final type in [
    MessageType.customFace,
    MessageType.advancedText,
    MessageType.groupInfoSetNotification,
  ]) {
    test('loaded type $type enables its actual day and preserves direct jump',
        () async {
      final fixture = _Fixture();
      addTearDown(fixture.dates.dispose);
      final message = _message('loaded-$type', _day, type: type);
      fixture.loaded.add(message);
      expect(fixture.jump.hasLoadedMessagesOn(_day), isTrue);
      expect(fixture.jump.hasLoadedMessagesOn(_nextDay), isFalse);
      await fixture.dates.loadMonth(_day);
      expect(fixture.dates.hasMessages(_day), isTrue);
      expect(await fixture.dates.verifyDate(_day), isTrue);
      expect(fixture.source.calls, isEmpty);
      await fixture.jump.pickAndJump(
        initialDate: _day,
        pickDate: (_) async =>
            await fixture.dates.verifyDate(_day) ? _day : null,
      );
      expect(fixture.opened.single, same(message));
      expect(fixture.jumpSearches, 0);
      expect(fixture.feedback, isEmpty);
    });
  }

  test('loaded day checks exclude invalid IDs/times and next midnight',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dates.dispose);
    fixture.loaded.addAll([
      Message(clientMsgID: 'missing-time', contentType: MessageType.customFace),
      _message('', _day, type: MessageType.customFace),
      _message('next-midnight', _nextDay, type: MessageType.customFace),
      _message('previous-day', _day.subtract(const Duration(milliseconds: 1)),
          type: MessageType.customFace),
    ]);
    expect(fixture.jump.hasLoadedMessagesOn(_day), isFalse);
    await fixture.dates.loadMonth(_day);
    expect(fixture.dates.hasMessages(_day), isFalse);
    expect(fixture.source.calls, hasLength(1));
  });

  test('an already removed loaded message cannot enable the date', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dates.dispose);
    fixture.loaded.add(_message('removed', _day, type: MessageType.customFace));
    fixture.removed.add('removed');
    await fixture.dates.loadMonth(_day);
    expect(fixture.jump.hasLoadedMessagesOn(_day), isFalse);
    expect(fixture.dates.hasMessages(_day), isFalse);
    expect(fixture.source.calls, hasLength(1));
  });

  test('deletion while the dialog is open invalidates its loaded proof',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dates.dispose);
    fixture.loaded
        .add(_message('last-record', _day, type: MessageType.customFace));
    await fixture.dates.loadMonth(_day);
    expect(fixture.dates.hasMessages(_day), isTrue);
    fixture.removed.add('last-record');
    expect(await fixture.dates.verifyDate(_day), isFalse);
    expect(fixture.dates.hasMessages(_day), isFalse);
    expect(fixture.source.calls, hasLength(1));
  });

  test('local removal tombstones also exclude stale SDK search rows', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dates.dispose);
    fixture.removed.add('sdk-delete-pending');
    fixture.source.respond = (call) =>
        call.pageIndex == 1 ? [_message('sdk-delete-pending', _day)] : [];
    await fixture.dates.loadMonth(_day);
    expect(fixture.dates.hasMessages(_day), isFalse);
    expect(fixture.source.calls.map((call) => call.pageIndex), [1, 2]);
    expect(fixture.dates.failed, isFalse);
  });

  test('a real loaded message arriving during a read confirms the day',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dates.dispose);
    final response = Completer<List<Message>>();
    fixture.source.respond = (_) => response.future;
    final request = fixture.dates.loadMonth(_day);
    expect(fixture.source.calls, hasLength(1));
    fixture.loaded
        .add(_message('new-real-record', _day, type: MessageType.customFace));
    response.complete([]);
    await request;
    expect(fixture.dates.hasMessages(_day), isTrue);
    expect(await fixture.dates.verifyDate(_day), isTrue);
    expect(fixture.source.calls, hasLength(1));
  });

  test('closing the original conversation refuses loaded records and caches',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dates.dispose);
    fixture.loaded
        .add(_message('original-account', _day, type: MessageType.customFace));
    await fixture.dates.loadMonth(_day);
    expect(fixture.dates.hasMessages(_day), isTrue);
    fixture.current = false;
    expect(fixture.jump.hasLoadedMessagesOn(_day), isFalse);
    expect(fixture.dates.hasMessages(_day), isFalse);
    expect(await fixture.dates.verifyDate(_day), isFalse);
    expect(fixture.source.calls, isEmpty);
  });

  test('a refresh rechecks deleted loaded records rather than trusting cache',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dates.dispose);
    fixture.loaded
        .add(_message('loaded-once', _day, type: MessageType.customFace));
    await fixture.dates.loadMonth(_day);
    fixture.loaded.clear();
    await fixture.dates.loadMonth(_day, force: true);
    expect(fixture.dates.hasMessages(_day), isFalse);
    expect(fixture.source.calls, hasLength(1));
  });
}
