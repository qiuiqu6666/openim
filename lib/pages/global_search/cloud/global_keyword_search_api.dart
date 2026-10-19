import 'package:dio/dio.dart';
import '../../chat/history_search/cloud/chat_keyword_search_api.dart';

class GlobalKeywordPage {
  const GlobalKeywordPage(this.items, this.cursor, this.hasMore);
  final List<CloudKeywordMessage> items;
  final String cursor;
  final bool hasMore;
}

class GlobalKeywordSearchApi {
  GlobalKeywordSearchApi({SearchHttpClient? client})
      : client = client ?? SearchHttpClient(reuseConnections: true);
  final SearchHttpClient client;
  CancelToken? _pending;

  void cancelPending() {
    _pending?.cancel('Search replaced or closed');
    _pending = null;
  }

  Future<GlobalKeywordPage> search(String keyword, String cursor,
      {bool Function()? isCurrent}) async {
    if (keyword.runes.length < 2 || keyword.runes.length > 64) {
      throw const FormatException('Keyword must contain 2–64 characters');
    }
    final cancellation = CancelToken();
    _pending = cancellation;
    final data = await client.request(
        '/msg/search_messages_global',
        {
          'keyword': keyword,
          'groupByConversation': true,
          'cursor': cursor,
          'limit': 20,
          'startTime': 0,
          'endTime': 0,
          'contentTypes': ChatKeywordSearchApi.contentTypes,
        },
        isCurrent: isCurrent,
        cancelToken: cancellation);
    final next = data['nextCursor'];
    final more = data['hasMore'];
    if (next is! String ||
        more is! bool ||
        data['items'] is! List ||
        (more && (next.isEmpty || next == cursor))) {
      throw const FormatException('Invalid global search cursor');
    }
    final items = <CloudKeywordMessage>[];
    for (final raw in data['items'] as List) {
      final item = Map<String, dynamic>.from(raw as Map);
      if (item['conversationID'] is! String ||
          (item['conversationID'] as String).isEmpty ||
          item['seq'] is! int ||
          (item['seq'] as int) <= 0 ||
          item['clientMsgID'] is! String ||
          (item['clientMsgID'] as String).isEmpty ||
          item['summary'] is! String ||
          item['sendTime'] is! int ||
          !ChatKeywordSearchApi.contentTypes.contains(item['contentType'])) {
        throw const FormatException('Invalid global search item');
      }
      items.add(CloudKeywordMessage(item));
    }
    return GlobalKeywordPage(items, next, more);
  }
}
