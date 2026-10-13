import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import '../cloud/chat_keyword_search_api.dart';

class SearchContextPage {
  const SearchContextPage(
      {required this.messages,
      required this.anchor,
      required this.beforeCursor,
      required this.afterCursor,
      required this.beforeEnd,
      required this.afterEnd});
  final List<Message> messages;
  final Message anchor;
  final String beforeCursor, afterCursor;
  final bool beforeEnd, afterEnd;
}

class SearchContextApi {
  SearchContextApi({SearchHttpClient? client})
      : client = client ?? SearchHttpClient();
  final SearchHttpClient client;

  Future<SearchContextPage> fetch(CloudKeywordMessage hit,
      {String? cursor, bool before = true, bool Function()? isCurrent}) async {
    final data = await client.request(
        '/msg/search_message_context',
        {
          'conversationID': hit.conversationID,
          if (cursor == null) ...{
            'seq': hit.seq,
            'before': 20,
            'after': 20,
            if (hit.serverMsgID?.isNotEmpty == true)
              'serverMsgID': hit.serverMsgID,
          } else ...{
            'cursor': cursor,
            'limit': 20
          },
        },
        isCurrent: isCurrent);
    if (data['conversationID'] != hit.conversationID ||
        data['anchorSeq'] != hit.seq ||
        data['direction'] !=
            (cursor == null
                ? 'around'
                : before
                    ? 'before'
                    : 'after')) {
      throw const FormatException('Wrong context scope');
    }
    final anchor = Message.fromJson(
        Map<String, dynamic>.from(data['anchorMessage'] as Map));
    if (anchor.seq != hit.seq ||
        anchor.clientMsgID != hit.clientMsgID ||
        (hit.serverMsgID?.isNotEmpty == true &&
            anchor.serverMsgID != hit.serverMsgID)) {
      throw const SearchApiException(409);
    }
    final messages = (data['messages'] as List)
        .map((raw) => Message.fromJson(Map<String, dynamic>.from(raw as Map)))
        .toList();
    var previous = 0;
    for (final message in messages) {
      final seq = message.seq;
      if (seq == null ||
          seq <= previous ||
          message.clientMsgID?.isNotEmpty != true ||
          (cursor != null && (before ? seq >= hit.seq! : seq <= hit.seq!))) {
        throw const FormatException('Invalid context messages');
      }
      previous = seq;
    }
    String checkedCursor(String key, String endKey) {
      final value = data[key];
      final end = data[endKey];
      if (value is! String ||
          end is! bool ||
          (end ? value.isNotEmpty : value.isEmpty || value == cursor)) {
        throw const FormatException('Invalid context cursor');
      }
      return value;
    }

    if (cursor == null) {
      if (messages
              .where(
                  (m) => m.seq == hit.seq && m.clientMsgID == hit.clientMsgID)
              .length !=
          1) {
        throw const FormatException('Missing context anchor');
      }
      // The full anchor is authoritative even if the combined list is minimal.
      messages[messages.indexWhere((m) => m.seq == hit.seq)] = anchor;
      return SearchContextPage(
          messages: messages,
          anchor: anchor,
          beforeCursor: checkedCursor('beforeCursor', 'beforeEnd'),
          afterCursor: checkedCursor('afterCursor', 'afterEnd'),
          beforeEnd: data['beforeEnd'] as bool,
          afterEnd: data['afterEnd'] as bool);
    }
    final next = checkedCursor('nextCursor', 'isEnd');
    return SearchContextPage(
        messages: messages,
        anchor: anchor,
        beforeCursor: before ? next : '',
        afterCursor: before ? '' : next,
        beforeEnd: before && data['isEnd'] == true,
        afterEnd: !before && data['isEnd'] == true);
  }
}
