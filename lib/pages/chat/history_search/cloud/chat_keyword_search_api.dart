import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:uuid/uuid.dart';

typedef KeywordSearchSession = ({String user, String token, String server});
typedef KeywordSearchPost = Future<dynamic> Function(
    String url, Map<String, dynamic> body, Options options);

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
      : _post = post ?? _defaultPost,
        _session = session ?? currentSession;
  final KeywordSearchPost _post;
  final KeywordSearchSession? Function() _session;
  KeywordSearchSession? _owner;
  static const contentTypes = [101, 106, 114, 117];

  static KeywordSearchSession? currentSession() {
    final manager = OpenIM.iMManager;
    final token = manager.token;
    if (manager.userID.isEmpty || token == null || token.isEmpty) return null;
    return (user: manager.userID, token: token, server: Config.imApiUrl);
  }

  Future<KeywordSearchPage> search(
      {required String conversationID,
      required String keyword,
      int beforeSeq = 0,
      int snapshotSeq = 0,
      int startTime = 0,
      int endTime = 0,
      List<int> types = contentTypes}) async {
    final length = keyword.runes.length;
    if (conversationID.isEmpty || length < 2 || length > 64) {
      throw const FormatException(
          'Keyword must contain 2–64 Unicode characters');
    }
    final session = _session();
    _owner ??= session;
    if (session == null || session != _owner) {
      throw StateError('Search session changed');
    }
    final response = await _post(
        '${session.server.replaceFirst(RegExp(r'/+$'), '')}/msg/search_messages',
        {
          'conversationID': conversationID,
          'keyword': keyword,
          'limit': 30,
          'beforeSeq': beforeSeq,
          'snapshotSeq': snapshotSeq,
          'startTime': startTime,
          'endTime': endTime,
          'contentTypes': types
        },
        Options(contentType: Headers.jsonContentType, headers: {
          'token': session.token,
          'operationID': const Uuid().v4(),
        }));
    if (_session() != session) throw StateError('Search session changed');
    if (response is! Map ||
        response['errCode'] != 0 ||
        response['data'] is! Map) {
      throw StateError('Cloud keyword search unavailable');
    }
    final data = response['data'] as Map;
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

  static Future<dynamic> _defaultPost(
      String url, Map<String, dynamic> body, Options options) async {
    final client = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        sendTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 6),
        followRedirects: false));
    try {
      return (await client.post<dynamic>(url, data: body, options: options))
          .data;
    } finally {
      client.close(force: true);
    }
  }
}
