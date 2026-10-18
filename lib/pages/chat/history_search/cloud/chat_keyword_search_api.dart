import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import 'search_http_client.dart';
export 'search_http_client.dart';

/// A plain-text search projection, never an authoritative SDK message.
class CloudKeywordMessage extends Message {
  CloudKeywordMessage(Map<String, dynamic> item)
      : conversationID = item['conversationID'] as String,
        summary = item['summary'] as String,
        super(
          clientMsgID: item['clientMsgID'] as String,
          serverMsgID: item['serverMsgID'] as String?,
          seq: item['seq'] as int,
          sendID: item['sendID'] as String,
          sendTime: item['sendTime'] as int,
          contentType: item['contentType'] as int,
        );
  final String conversationID;
  final String summary;
}

class KeywordSearchPage {
  const KeywordSearchPage(
      this.items, this.hasMore, this.beforeSeq, this.snapshotSeq);
  final List<CloudKeywordMessage> items;
  final bool hasMore;
  final int beforeSeq, snapshotSeq;
}

class ChatKeywordSearchApi {
  ChatKeywordSearchApi(
      {KeywordSearchPost? post, KeywordSearchSession? Function()? session})
      : client = SearchHttpClient(post: post, session: session);
  final SearchHttpClient client;
  static const contentTypes = [101, 106, 114, 117];
  static KeywordSearchSession? currentSession() =>
      SearchHttpClient.currentSession();

  Future<KeywordSearchPage> search(
      {required String conversationID,
      required String keyword,
      int beforeSeq = 0,
      int snapshotSeq = 0,
      int startTime = 0,
      int endTime = 0,
      List<int> types = contentTypes,
      List<String> senderIDs = const [],
      bool Function()? isCurrent}) async {
    final filtered = keyword.isEmpty &&
        (senderIDs.isNotEmpty || (startTime > 0 && endTime > startTime));
    final length = keyword.runes.length;
    if (conversationID.isEmpty || (!filtered && (length < 2 || length > 64))) {
      throw const FormatException(
          'Keyword must contain 2–64 Unicode characters');
    }
    final data = await client.request(
        filtered ? '/msg/search_history_filters' : '/msg/search_messages',
        {
          'conversationID': conversationID,
          'keyword': keyword,
          'limit': 30,
          'beforeSeq': beforeSeq,
          'snapshotSeq': snapshotSeq,
          'startTime': startTime,
          'endTime': endTime,
          'contentTypes': types,
          if (filtered) 'senderIDs': senderIDs
        },
        isCurrent: isCurrent);
    final next = data['nextBeforeSeq'];
    final snapshot = data['snapshotSeq'];
    final more = data['hasMore'];
    final raw = data['items'];
    if (more is! bool ||
        next is! int ||
        snapshot is! int ||
        raw is! List ||
        snapshot < 0 ||
        (snapshotSeq != 0 && snapshot != snapshotSeq) ||
        (more &&
            (next <= 0 ||
                next > snapshot ||
                (beforeSeq > 0 && next >= beforeSeq)))) {
      throw const FormatException('Invalid search cursor');
    }
    final items = <CloudKeywordMessage>[];
    var previous = beforeSeq > 0 ? beforeSeq : snapshot + 1;
    for (final value in raw) {
      final item = Map<String, dynamic>.from(value as Map);
      final seq = item['seq'];
      if (item['conversationID'] != conversationID ||
          seq is! int ||
          seq <= 0 ||
          seq > snapshot ||
          seq >= previous ||
          item['clientMsgID'] is! String ||
          (item['clientMsgID'] as String).isEmpty ||
          item['sendID'] is! String ||
          item['sendTime'] is! int ||
          !types.contains(item['contentType']) ||
          item['summary'] is! String) {
        throw const FormatException('Invalid search result');
      }
      previous = seq;
      items.add(CloudKeywordMessage(item));
    }
    return KeywordSearchPage(items, more, next, snapshot);
  }
}
