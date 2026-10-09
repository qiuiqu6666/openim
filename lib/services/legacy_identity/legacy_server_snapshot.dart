import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:uuid/uuid.dart';

typedef LegacyCleanupSession = ({String owner, String token, String server});
typedef LegacyCleanupPost = Future<dynamic> Function(
    String url, Map<String, dynamic> body, Options options);

/// Authenticated, account-bound authoritative snapshot for migration cleanup.
class LegacyServerSnapshot {
  static Future<Set<String>> serverIDs(LegacyCleanupSession session,
      {LegacyCleanupPost? post}) async {
    final response = await (post ?? defaultPost)(
      '${session.server.replaceFirst(RegExp(r'/+$'), '')}/conversation/get_full_conversation_ids',
      // The empty-server hash is zero; a nonzero request also requests that list.
      // A rare equal hash is handled conservatively as no deletion permission.
      {'userID': session.owner, 'idHash': 1},
      Options(contentType: Headers.jsonContentType, headers: {
        'token': session.token,
        'operationID': const Uuid().v4(),
      }),
    );
    if (response is! Map || response['errCode'] != 0) {
      throw const FormatException('Conversation cleanup response unavailable');
    }
    final data = response['data'];
    if (data is! Map ||
        data['versionID'] is! String ||
        (data['versionID'] as String).isEmpty ||
        (data['equal'] != null && data['equal'] != false)) {
      throw const FormatException('Conversation cleanup needs a full snapshot');
    }
    final ids = data['conversationIDs'];
    // Protobuf JSON omits an empty list. versionID above proves a real response.
    if (ids == null) return {};
    if (ids is! List || ids.any((id) => id is! String || id.isEmpty)) {
      throw const FormatException('Invalid conversation cleanup IDs');
    }
    return ids.cast<String>().toSet();
  }

  static bool allowedServer(String server) {
    final uri = Uri.tryParse(server);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host == '129.226.192.93' &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  static LegacyCleanupSession? currentSession() {
    final owner = DataSp.userID;
    final token = DataSp.imToken;
    if (owner == null ||
        owner.isEmpty ||
        token == null ||
        token.isEmpty ||
        OpenIM.iMManager.userID != owner) {
      return null;
    }
    return (owner: owner, token: token, server: Config.imApiUrl);
  }

  static Future<dynamic> defaultPost(
      String url, Map<String, dynamic> body, Options options) async {
    // Dedicated client: no shared auth interceptor, credential logging, or redirects.
    final client = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      followRedirects: false,
    ));
    try {
      return (await client.post<dynamic>(url, data: body, options: options))
          .data;
    } finally {
      client.close();
    }
  }
}
