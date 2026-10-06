import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/history/date_jump/chat_date_jump_controller.dart';

final _day = DateTime(2026, 10, 4);
final _nextDay = DateTime(2026, 10, 5);

Message _message(String id, DateTime time) => Message(
      clientMsgID: id,
      sendTime: time.millisecondsSinceEpoch,
      contentType: MessageType.text,
      status: MessageStatus.succeeded,
    );

SearchResult _page(List<Message> messages, {String id = 'chat'}) =>
    SearchResult(
      // The SDK reports the count in this response, even when more pages exist.
      totalCount: messages.length,
      searchResultItems: [
        SearchResultItems(conversationID: id, messageList: messages),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  test('picker receives the tapped message day in local time', () async {
    final fixture = _Fixture();
    final tapped = DateTime.utc(2026, 10, 4, 17, 16);
    DateTime? shown;
    await fixture.controller.pickAndJump(
      initialDate: tapped,
      pickDate: (initial) async {
        shown = initial;
        return null;
      },
    );
    expect(shown, tapped.toLocal());
    expect(shown!.isUtc, isFalse);
    expect(fixture.calls, isEmpty);
    expect(fixture.opened, isEmpty);
    expect(fixture.loadingCount, 0);
  });

  test('canceling selection performs no search, loading, or navigation',
      () async {
    final fixture = _Fixture();
    await fixture.jump(cancel: true);
    expect(fixture.pickerCount, 1);
    expect(fixture.calls, isEmpty);
    expect(fixture.loadingCount, 0);
    expect(fixture.opened, isEmpty);
    expect(fixture.feedback, isEmpty);
    // Cancellation releases the guard so the next tap can open the picker.
    await fixture.jump(cancel: true);
    expect(fixture.pickerCount, 2);
  });

  test('selected calendar day searches explicit types and current conversation',
      () async {
    final fixture = _Fixture()..id = 'current-conversation';
    final first = _message('first', _day);
    final latest = _message('latest', DateTime(2026, 10, 4, 23, 40));
    fixture.onSearch = (_) async => _page([first, latest], id: fixture.id);

    await fixture.jump(selected: DateTime(2026, 10, 4, 9, 47));

    expect(fixture.calls, hasLength(1));
    final call = fixture.calls.single;
    expect(call.conversationID, 'current-conversation');
    expect(
        call.messageTypeList,
        unorderedEquals([
          MessageType.text,
          MessageType.atText,
          MessageType.picture,
          MessageType.voice,
          MessageType.video,
          MessageType.file,
          MessageType.merger,
          MessageType.card,
          MessageType.location,
          MessageType.custom,
          MessageType.quote,
        ]));
    expect(call.searchTimePosition, _nextDay.millisecondsSinceEpoch ~/ 1000);
    expect(
        call.searchTimePeriod,
        (_nextDay.millisecondsSinceEpoch - _day.millisecondsSinceEpoch) ~/
            1000);
    expect(call.pageIndex, 1);
    expect(call.count, 20);
    expect(fixture.loadingCount, 1);
    expect(fixture.opened.single.conversationID, fixture.id);
    expect(fixture.opened.single.target, same(latest));
    expect(fixture.opened.single.day, _day);
    expect(fixture.feedback, isEmpty);
  });

  test('inclusive next midnight is excluded and final millisecond is retained',
      () async {
    final fixture = _Fixture();
    final lastMillisecond = _message(
        'last-millisecond', _nextDay.subtract(const Duration(milliseconds: 1)));
    fixture.onSearch = (_) async => _page([
          _message('next-midnight', _nextDay),
          _message('earlier', DateTime(2026, 10, 4, 18)),
          lastMillisecond,
          _message(
              'previous-day', _day.subtract(const Duration(milliseconds: 1))),
        ]);
    await fixture.jump();
    expect(fixture.opened.single.target, same(lastMillisecond));
    expect(fixture.calls, hasLength(1));
  });

  test('a full next-day-only SDK page advances despite page-sized totalCount',
      () async {
    final fixture = _Fixture();
    final target = _message('chosen-day', DateTime(2026, 10, 4, 23, 59));
    fixture.onSearch = (call) async => call.pageIndex == 1
        ? _page(List.generate(20, (i) => _message('next-$i', _nextDay)))
        : _page([target]);

    await fixture.jump();

    expect(fixture.calls.map((call) => call.pageIndex), [1, 2]);
    expect(fixture.opened.single.target, same(target));
    expect(fixture.feedback, isEmpty);
  });

  test('selected day midnight itself is included', () async {
    final fixture = _Fixture();
    final midnight = _message('midnight', _day);
    fixture.onSearch = (_) async => _page([midnight]);
    await fixture.jump();
    expect(fixture.opened.single.target, same(midnight));
  });

  test('loaded history anchors unsupported types without an SDK query',
      () async {
    final fixture = _Fixture()..removed.add('removed-loaded');
    final sticker = _message('loaded-sticker', DateTime(2026, 10, 4, 20))
      ..contentType = MessageType.customFace;
    fixture.loaded.addAll([
      _message('loaded-text', DateTime(2026, 10, 4, 19)),
      sticker,
      _message('removed-loaded', DateTime(2026, 10, 4, 23)),
      _message('next-midnight', _nextDay),
      _message('previous-day', _day.subtract(const Duration(milliseconds: 1))),
      _message('', DateTime(2026, 10, 4, 22)),
      Message(clientMsgID: 'loaded-without-time'),
    ]);
    await fixture.jump();
    expect(fixture.calls, isEmpty);
    expect(fixture.opened.single.target, same(sticker));
    expect(fixture.opened.single.day, _day);
    expect(fixture.feedback, isEmpty);
  });

  test('unusable loaded messages fall back to the selected-day SDK query',
      () async {
    final fixture = _Fixture()..removed.add('removed-loaded');
    fixture.loaded.addAll([
      _message('removed-loaded', DateTime(2026, 10, 4, 23)),
      _message('next-midnight', _nextDay),
      _message('previous-day', _day.subtract(const Duration(milliseconds: 1))),
    ]);
    final target = _message('sdk-target', _day);
    fixture.onSearch = (_) async => _page([target]);
    await fixture.jump();
    expect(fixture.calls, hasLength(1));
    expect(fixture.opened.single.target, same(target));
  });

  test('foreign conversation and unusable or removed anchors are ignored',
      () async {
    final fixture = _Fixture()..removed.add('deleted');
    final target = _message('valid', DateTime(2026, 10, 4, 18));
    fixture.onSearch = (_) async => SearchResult(searchResultItems: [
          SearchResultItems(conversationID: 'other-chat', messageList: [
            _message('foreign', DateTime(2026, 10, 4, 23, 59)),
          ]),
          SearchResultItems(conversationID: fixture.id, messageList: [
            target,
            _message('deleted', DateTime(2026, 10, 4, 23)),
            _message('', DateTime(2026, 10, 4, 22)),
            Message(clientMsgID: 'no-time'),
          ]),
        ]);
    await fixture.jump();
    expect(fixture.opened.single.target, same(target));
  });

  test('empty day gives feedback and allows another selection to succeed',
      () async {
    final fixture = _Fixture();
    await fixture.jump();
    expect(fixture.opened, isEmpty);
    expect(fixture.feedback, ['chatDateHistoryEmpty'.tr]);
    expect(fixture.calls, hasLength(1));

    final target = _message('retry', DateTime(2026, 10, 4, 12));
    fixture.onSearch = (_) async => _page([target]);
    await fixture.jump();
    expect(fixture.calls, hasLength(2));
    expect(fixture.opened.single.target, same(target));
  });

  test('SDK failure gives feedback and releases the busy guard for retry',
      () async {
    final fixture = _Fixture();
    fixture.onSearch = (_) async => throw StateError('SDK unavailable');
    await fixture.jump();
    expect(fixture.feedback, ['chatDateHistoryFailed'.tr]);
    expect(fixture.opened, isEmpty);

    final target = _message('retry', _day);
    fixture.onSearch = (_) async => _page([target]);
    await fixture.jump();
    expect(fixture.opened.single.target, same(target));
    expect(fixture.calls, hasLength(2));
  });

  test('picker failure gives feedback and allows retry', () async {
    final fixture = _Fixture();
    await fixture.controller.pickAndJump(
      initialDate: _day,
      pickDate: (_) async => throw StateError('picker unavailable'),
    );
    expect(fixture.feedback, ['chatDateHistoryFailed'.tr]);
    expect(fixture.calls, isEmpty);
    await fixture.jump(cancel: true);
    expect(fixture.pickerCount, 1);
  });

  test('repeated taps while a picker is open are coalesced', () async {
    final fixture = _Fixture();
    final picker = Completer<DateTime?>();
    final pending = fixture.controller.pickAndJump(
      initialDate: _day,
      pickDate: (_) {
        fixture.pickerCount++;
        return picker.future;
      },
    );
    await fixture.jump();
    expect(fixture.pickerCount, 1);
    expect(fixture.calls, isEmpty);
    picker.complete(null);
    await pending;
    await fixture.jump(cancel: true);
    expect(fixture.pickerCount, 2);
  });

  test('repeated taps during SDK lookup open only one context', () async {
    final fixture = _Fixture();
    final result = Completer<SearchResult>();
    final queryStarted = Completer<void>();
    final target = _message('target', _day);
    fixture.onSearch = (_) {
      queryStarted.complete();
      return result.future;
    };
    final pending = fixture.jump();
    await queryStarted.future;
    await fixture.jump();
    expect(fixture.pickerCount, 1);
    expect(fixture.calls, hasLength(1));
    expect(fixture.loadingCount, 1);
    result.complete(_page([target]));
    await pending;
    expect(fixture.opened, hasLength(1));
    expect(fixture.opened.single.target, same(target));
  });

  test('invalidate permits a new picker before an old SDK lookup settles',
      () async {
    final fixture = _Fixture();
    final staleResult = Completer<SearchResult>();
    final firstStarted = Completer<void>();
    final target = _message('new-selection', _day);
    fixture.onSearch = (call) {
      if (fixture.calls.length == 1) {
        firstStarted.complete();
        return staleResult.future;
      }
      return Future.value(_page([target]));
    };
    final oldJump = fixture.jump();
    await firstStarted.future;

    fixture.controller.invalidate();
    await fixture.jump();

    expect(fixture.pickerCount, 2);
    expect(fixture.calls, hasLength(2));
    expect(fixture.opened.single.target, same(target));
    staleResult.complete(_page([_message('stale-selection', _day)]));
    await oldJump;
    expect(fixture.opened, hasLength(1));
    expect(fixture.feedback, isEmpty);
  });

  test('old lookup finally cannot release the newer picker busy guard',
      () async {
    final fixture = _Fixture();
    final staleResult = Completer<SearchResult>();
    final firstStarted = Completer<void>();
    fixture.onSearch = (_) {
      firstStarted.complete();
      return staleResult.future;
    };
    final oldJump = fixture.jump();
    await firstStarted.future;
    fixture.controller.invalidate();

    final newPicker = Completer<DateTime?>();
    final newJump = fixture.controller.pickAndJump(
      initialDate: _day,
      pickDate: (_) {
        fixture.pickerCount++;
        return newPicker.future;
      },
    );
    staleResult.complete(_page([_message('stale-selection', _day)]));
    await oldJump;
    await fixture.jump(cancel: true);

    expect(fixture.pickerCount, 2);
    expect(fixture.calls, hasLength(1));
    expect(fixture.opened, isEmpty);
    expect(fixture.feedback, isEmpty);

    newPicker.complete(null);
    await newJump;
    await fixture.jump(cancel: true);
    expect(fixture.pickerCount, 3);
  });

  for (final stale in ['invalidate', 'closed', 'conversation changed']) {
    test('$stale during picker prevents search and late navigation', () async {
      final fixture = _Fixture();
      final picker = Completer<DateTime?>();
      final pending = fixture.controller.pickAndJump(
        initialDate: _day,
        pickDate: (_) => picker.future,
      );
      fixture.makeStale(stale);
      picker.complete(_day);
      await pending;
      expect(fixture.calls, isEmpty);
      expect(fixture.loadingCount, 0);
      expect(fixture.opened, isEmpty);
      expect(fixture.feedback, isEmpty);
    });

    test('$stale during query discards the result without late navigation',
        () async {
      final fixture = _Fixture();
      final result = Completer<SearchResult>();
      final queryStarted = Completer<void>();
      fixture.onSearch = (_) {
        queryStarted.complete();
        return result.future;
      };
      final pending = fixture.jump();
      await queryStarted.future;
      fixture.makeStale(stale);
      result.complete(_page([_message('late-result', _day)]));
      await pending;
      expect(fixture.calls, hasLength(1));
      expect(fixture.opened, isEmpty);
      expect(fixture.feedback, isEmpty);
    });
  }

  test('removed anchor after query but before loading settles is not opened',
      () async {
    final fixture = _Fixture();
    final target = _message('removed-after-search', _day);
    final resolved = Completer<void>();
    final finishLoading = Completer<void>();
    fixture.onSearch = (_) async => _page([target]);
    fixture.onLoading = (operation) async {
      final found = await operation();
      resolved.complete();
      await finishLoading.future;
      return found;
    };
    final pending = fixture.jump();
    await resolved.future;
    fixture.removed.add(target.clientMsgID!);
    finishLoading.complete();
    await pending;
    expect(fixture.opened, isEmpty);
    expect(fixture.feedback, ['chatDateHistoryEmpty'.tr]);
  });

  test('already closed conversation never opens its picker', () async {
    final fixture = _Fixture()..closed = true;
    await fixture.jump();
    expect(fixture.pickerCount, 0);
    expect(fixture.calls, isEmpty);
    expect(fixture.opened, isEmpty);
  });
}

class _SearchCall {
  _SearchCall({
    required this.conversationID,
    required List<int> messageTypeList,
    required this.searchTimePosition,
    required this.searchTimePeriod,
    required this.pageIndex,
    required this.count,
  }) : messageTypeList = List.of(messageTypeList);

  final String conversationID;
  final List<int> messageTypeList;
  final int searchTimePosition;
  final int searchTimePeriod;
  final int pageIndex;
  final int count;
}

class _Fixture {
  _Fixture() {
    controller = ChatDateJumpController(
      conversationID: () => id,
      isClosed: () => closed,
      isRemoved: (message) => removed.contains(message.clientMsgID),
      messages: () => loaded,
      search: ({
        required conversationID,
        required messageTypeList,
        required searchTimePosition,
        required searchTimePeriod,
        required pageIndex,
        required count,
      }) {
        final call = _SearchCall(
          conversationID: conversationID,
          messageTypeList: messageTypeList,
          searchTimePosition: searchTimePosition,
          searchTimePeriod: searchTimePeriod,
          pageIndex: pageIndex,
          count: count,
        );
        calls.add(call);
        return onSearch(call);
      },
      jumpToMessage: (id, target, day) =>
          opened.add((conversationID: id, target: target, day: day)),
      showFeedback: feedback.add,
      runLoading: (operation) {
        loadingCount++;
        return onLoading?.call(operation) ?? operation();
      },
    );
  }

  late final ChatDateJumpController controller;
  String id = 'chat';
  bool closed = false;
  int loadingCount = 0;
  int pickerCount = 0;
  final removed = <String>{};
  final loaded = <Message>[];
  final calls = <_SearchCall>[];
  final opened = <({String conversationID, Message target, DateTime day})>[];
  final feedback = <String>[];
  Future<SearchResult> Function(_SearchCall) onSearch = (_) async => _page([]);
  Future<Message?> Function(Future<Message?> Function())? onLoading;

  Future<void> jump({DateTime? selected, bool cancel = false}) =>
      controller.pickAndJump(
        initialDate: _day,
        pickDate: (_) async {
          pickerCount++;
          return cancel ? null : selected ?? _day;
        },
      );

  void makeStale(String reason) {
    switch (reason) {
      case 'invalidate':
        controller.invalidate();
      case 'closed':
        closed = true;
      case 'conversation changed':
        id = 'different-chat';
    }
  }
}
