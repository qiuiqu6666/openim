import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/history/date_jump/widgets/chat_date_image_calendar.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_source.dart';

import 'support/chat_date_picker_availability_fixture.dart';

class _PhotoDateJumpSource extends DateJumpSource {
  _PhotoDateJumpSource({this.failPictures = false})
      : super(days: {dateJumpPresent, dateJumpToday});

  final bool failPictures;

  @override
  Future<List<Message>> search({
    required String conversationID,
    required ChatHistorySearchQuery query,
    required int pageIndex,
    int count = 30,
  }) async {
    if (query.messageTypes.length != 1 ||
        query.messageTypes.single != MessageType.picture) {
      return super.search(
        conversationID: conversationID,
        query: query,
        pageIndex: pageIndex,
        count: count,
      );
    }
    expect(conversationID, dateJumpConversation);
    expect(query.keyword, isEmpty);
    expect(count, 20);
    final day = query.localStart!;
    imageCalls.add(day);
    if (failPictures) throw StateError('Picture metadata unavailable');
    if (pageIndex != 1 || day != dateJumpPresent) return [];
    return [
      for (final id in ['day-picture-a', 'day-picture-b'])
        Message.fromJson({
          'clientMsgID': id,
          'contentType': MessageType.picture,
          'sendID': 'member',
          'sendTime':
              DateTime(day.year, day.month, day.day, 12).millisecondsSinceEpoch,
          // A missing thumbnail exercises the ordinary-day fallback without
          // depending on external image servers or test-specific media state.
          'pictureElem': {'sourcePath': 'missing-calendar-test-$id.png'},
        }),
    ];
  }
}

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  testWidgets('jump dialog projects real day images and verifies a tapped day',
      (tester) async {
    final source = _PhotoDateJumpSource();
    final fixture = DateJumpFixture(source);
    await fixture.open(tester);

    var calendar = tester
        .widget<ChatDateImageCalendar>(find.byType(ChatDateImageCalendar));
    final chosen = calendar.imageForDate!(dateJumpPresent);
    expect(chosen, isNotNull);
    expect(chosen!.messageID, isIn(['day-picture-a', 'day-picture-b']));
    expect(calendar.imageForDate!(dateJumpToday), isNull);
    expect(calendar.imageForDate!(dateJumpEmpty), isNull);
    expect(source.imageCalls.toSet(), {dateJumpPresent, dateJumpToday});
    expect(dateJumpEnabled(tester, dateJumpEmpty), isFalse);

    await tester.pump();
    calendar = tester
        .widget<ChatDateImageCalendar>(find.byType(ChatDateImageCalendar));
    expect(
        calendar.imageForDate!(dateJumpPresent)!.messageID, chosen.messageID);
    final pictureReads = source.imageCalls.length;
    final dayReads = source.calls.where((day) => day == dateJumpPresent).length;
    await tester.tap(dateJumpDay(dateJumpPresent));
    await dateJumpFrames(tester);
    await tester.pumpAndSettle();
    expect(fixture.returned, dateJumpPresent);
    expect(fixture.completions, 1);
    expect(source.imageCalls, hasLength(pictureReads));
    expect(source.calls.where((day) => day == dateJumpPresent),
        hasLength(dayReads + 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('picture lookup failure keeps a confirmed date selectable',
      (tester) async {
    final source = _PhotoDateJumpSource(failPictures: true);
    final fixture = DateJumpFixture(source);
    await fixture.open(tester);

    final calendar = tester
        .widget<ChatDateImageCalendar>(find.byType(ChatDateImageCalendar));
    expect(calendar.imageForDate!(dateJumpPresent), isNull);
    expect(dateJumpEnabled(tester, dateJumpPresent), isTrue);
    expect(dateJumpEnabled(tester, dateJumpEmpty), isFalse);
    expect(dateJumpKey('retry'), findsNothing);
    await tester.tap(dateJumpDay(dateJumpPresent));
    await dateJumpFrames(tester);
    await tester.pumpAndSettle();
    expect(fixture.returned, dateJumpPresent);
    expect(tester.takeException(), isNull);
  });
}
