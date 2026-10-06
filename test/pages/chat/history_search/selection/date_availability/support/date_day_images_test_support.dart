import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_source.dart';
import 'package:openim/pages/chat/history_search/selection/date_availability/chat_history_date_availability_controller.dart';

final imageDay = DateTime(2026, 10, 4);

Message dayRecord(DateTime day) => Message(
      clientMsgID: 'record-${day.toIso8601String()}',
      sendTime:
          DateTime(day.year, day.month, day.day, 12).millisecondsSinceEpoch,
      contentType: MessageType.text,
      status: MessageStatus.succeeded,
    );

Message dayPicture(String id,
        {DateTime? time,
        String? snapshot = 'https://media.example/snapshot.webp',
        String? big = 'https://media.example/big.webp',
        String? original = 'https://media.example/source.webp',
        String? path,
        bool private = false}) =>
    Message(
      clientMsgID: id,
      sendTime: (time ?? imageDay.add(const Duration(hours: 12)))
          .millisecondsSinceEpoch,
      contentType: MessageType.picture,
      status: MessageStatus.succeeded,
      attachedInfoElem: AttachedInfoElem(isPrivateChat: private),
      pictureElem: PictureElem(
        sourcePath: path,
        snapshotPicture: PictureInfo(url: snapshot),
        bigPicture: PictureInfo(url: big),
        sourcePicture: PictureInfo(url: original),
      ),
    );

typedef DayImageCall = ({
  ChatHistorySearchQuery query,
  int pageIndex,
  int count,
  bool picture,
});

class DayImageSource implements ChatHistorySearchSource {
  final calls = <DayImageCall>[];
  FutureOr<List<Message>> Function(DayImageCall)? records;
  FutureOr<List<Message>> Function(DayImageCall)? pictures;
  int active = 0, peak = 0;

  @override
  Future<List<Message>> search({
    required String conversationID,
    required ChatHistorySearchQuery query,
    required int pageIndex,
    int count = 30,
  }) async {
    expect(conversationID, 'current-chat');
    final picture = query.messageTypes.length == 1 &&
        query.messageTypes.single == MessageType.picture;
    expect(count, picture ? 20 : 1);
    expect(query.startDate, query.endDate);
    final call = (
      query: query,
      pageIndex: pageIndex,
      count: count,
      picture: picture,
    );
    calls.add(call);
    ++active;
    if (active > peak) peak = active;
    try {
      return await (picture
          ? pictures?.call(call) ?? <Message>[]
          : records?.call(call) ?? [dayRecord(query.startDate!)]);
    } finally {
      --active;
    }
  }
}

ChatHistoryDateAvailabilityController imageController(DayImageSource source,
        {DateTime? first,
        DateTime? last,
        bool include = true,
        int Function(int length)? choose,
        bool Function()? isCurrent,
        bool Function(Message message)? isRemoved}) =>
    ChatHistoryDateAvailabilityController(
      conversationID: 'current-chat',
      firstDate: first ?? imageDay,
      lastDate: last ?? imageDay,
      source: source,
      includeDayImages: include,
      chooseImageIndex: choose,
      isCurrent: isCurrent,
      isRemoved: isRemoved,
    );

Future<void> flushImageReads() => Future<void>.delayed(Duration.zero);
