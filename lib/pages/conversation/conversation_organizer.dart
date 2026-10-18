import 'organizer/organizer_request_diagnostics.dart';
import 'package:dio/dio.dart';
import 'package:openim_common/openim_common.dart';

class ChatFolder {
  final String id;
  final String name;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;

  ChatFolder.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        name = json['name'] as String,
        sortOrder = (json['sortOrder'] as num?)?.toInt() ?? 0,
        createdAt = (json['createdAt'] as num).toInt(),
        updatedAt = (json['updatedAt'] as num).toInt();
}

class ChatStatesSync {
  final Map<String, ChatConversationState> states;
  final int syncAt;
  ChatStatesSync(this.states, this.syncAt);
}

class ChatConversationState {
  final String conversationID;
  final String? folderID;
  final bool archived;
  final int version;

  ChatConversationState.fromJson(Map<String, dynamic> json)
      : conversationID = json['conversationID'] as String,
        folderID = json['folderID'] as String?,
        archived = json['archived'] == true,
        version = (json['version'] as num).toInt();
}

class ChatOrganizerConflict implements Exception {
  final ChatConversationState current;
  ChatOrganizerConflict(this.current);
}

class ChatOrganizerApi {
  static int _requestSequence = 0;

  static Options get _options => Options(headers: {
        'token': DataSp.chatToken,
        'operationID':
            '${DateTime.now().microsecondsSinceEpoch}-${_requestSequence++}',
        'Content-Type': 'application/json',
      });

  static String get _base => '${Config.appAuthUrl}/chat';

  static Future<Map<String, dynamic>> _request(String method, String path,
      {String? route,
      String source = 'manual',
      Map<String, dynamic>? data,
      Map<String, dynamic>? queryParameters}) {
    final options = _options;
    options.method = method;
    int? businessCode;
    return OrganizerRequestDiagnostics.run(
      route: '$method /chat/${route ?? path}',
      source: source,
      operationID: options.headers!['operationID'] as String,
      businessCode: () => businessCode,
      request: () async {
        final response = await dio.request('$_base/$path',
            options: options, data: data, queryParameters: queryParameters);
        final body = response.data;
        if (body is Map && body['errCode'] is int) {
          businessCode = body['errCode'];
        }
        return _data(response);
      },
    );
  }

  static Map<String, dynamic> _data(Response<dynamic> response) {
    final body = Map<String, dynamic>.from(response.data as Map);
    if (body['errCode'] != 0) {
      if (body['errCode'] == 20015 && body['data'] is Map) {
        throw ChatOrganizerConflict(ChatConversationState.fromJson(
            Map<String, dynamic>.from(body['data'] as Map)));
      }
      throw StateError('${body['errMsg']}: ${body['errDlt']}');
    }
    return Map<String, dynamic>.from(body['data'] as Map);
  }

  static Future<List<ChatFolder>> getFolders({String source = 'manual'}) async {
    final data = await _request('GET', 'folders', source: source);
    return (data['folders'] as List? ?? const [])
        .map((item) =>
            ChatFolder.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  static Future<ChatFolder> createFolder(String name,
      {int sortOrder = 0}) async {
    final data = await _request('POST', 'folders',
        data: {'name': name, 'sortOrder': sortOrder});
    return ChatFolder.fromJson(data);
  }

  static Future<ChatFolder> renameFolder(String id, String name) async {
    final data = await _request('PATCH', 'folders/${Uri.encodeComponent(id)}',
        route: 'folders/:id', data: {'name': name});
    return ChatFolder.fromJson(data);
  }

  static Future<ChatFolder> setFolderSortOrder(String id, int sortOrder) async {
    final data = await _request('PATCH', 'folders/${Uri.encodeComponent(id)}',
        route: 'folders/:id', data: {'sortOrder': sortOrder});
    return ChatFolder.fromJson(data);
  }

  static Future<void> deleteFolder(String id) async {
    await _request('DELETE', 'folders/${Uri.encodeComponent(id)}',
        route: 'folders/:id');
  }

  static Future<ChatStatesSync> getStates(
      {int updatedAfter = 0, String source = 'manual'}) async {
    final token = DataSp.chatToken;
    final states = <String, ChatConversationState>{};
    var cursor = updatedAfter;
    while (true) {
      if (DataSp.chatToken != token) {
        throw StateError('Session changed while loading conversation states');
      }
      final data = await _request('GET', 'conversation-states',
          source: source,
          queryParameters: {'updatedAfter': cursor, 'limit': 500});
      final page = data['states'] as List;
      for (final item in page) {
        final state = ChatConversationState.fromJson(
            Map<String, dynamic>.from(item as Map));
        states[state.conversationID] = state;
      }
      final next = (data['syncAt'] as num).toInt();
      if (next <= cursor) break;
      cursor = next;
      if (page.length < 500) break;
    }
    return ChatStatesSync(states, cursor);
  }

  static Future<ChatConversationState> putState({
    required String conversationID,
    required String? folderID,
    required bool archived,
    required int version,
  }) async {
    final data = await _request(
        'PUT', 'conversation-states/${Uri.encodeComponent(conversationID)}',
        route: 'conversation-states/:id',
        data: {'folderID': folderID, 'archived': archived, 'version': version});
    return ChatConversationState.fromJson(data);
  }
}
