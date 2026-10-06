import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Filters for one conversation's local message history.
class ChatHistorySearchQuery {
  const ChatHistorySearchQuery({
    this.keyword = '',
    this.messageTypes = const [],
    this.senderIDs = const [],
    this.startDate,
    this.endDate,
  });

  final String keyword;
  final List<int> messageTypes;
  final List<String> senderIDs;
  final DateTime? startDate;
  final DateTime? endDate;

  // These are the types accepted by filterMsg in OpenIM core 3.8.3-patch.12.
  // In particular, notifications, customFace and advancedText are not accepted.
  static const searchableMessageTypes = <int>[
    MessageType.text,
    MessageType.picture,
    MessageType.voice,
    MessageType.video,
    MessageType.file,
    MessageType.atText,
    MessageType.merger,
    MessageType.card,
    MessageType.location,
    MessageType.custom,
    MessageType.quote,
  ];

  /// Never submit an empty keyword list together with an empty type list.
  List<int> get sdkMessageTypes => messageTypes.isNotEmpty
      ? messageTypes
      : keyword.trim().isEmpty
          ? searchableMessageTypes
          : const [];

  DateTime? get localStart => startDate == null
      ? null
      : DateTime(startDate!.year, startDate!.month, startDate!.day);

  // Calendar construction, rather than adding 24 hours, also handles DST days.
  DateTime? get localEndExclusive => endDate == null
      ? null
      : DateTime(endDate!.year, endDate!.month, endDate!.day + 1);

  int get searchTimePosition =>
      (localEndExclusive?.millisecondsSinceEpoch ?? 0) ~/ 1000;

  int get searchTimePeriod => localStart == null || localEndExclusive == null
      ? 0
      : localEndExclusive!.difference(localStart!).inSeconds;

  ChatHistorySearchQuery snapshot() {
    if ((startDate == null) != (endDate == null)) {
      throw ArgumentError('Both startDate and endDate must be provided.');
    }
    if (localStart != null && !localStart!.isBefore(localEndExclusive!)) {
      throw ArgumentError('The end date must not precede the start date.');
    }
    return ChatHistorySearchQuery(
      keyword: keyword.trim(),
      messageTypes: List.unmodifiable(messageTypes.toSet()),
      senderIDs: List.unmodifiable(
        senderIDs.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet(),
      ),
      startDate: localStart,
      endDate: endDate == null
          ? null
          : DateTime(endDate!.year, endDate!.month, endDate!.day),
    );
  }

  /// Sender filtering is not implemented by the current native SDK. Date and
  /// type checks also keep inclusive SDK boundaries/fallback types out of UI.
  bool accepts(Message message) {
    if (senderIDs.isNotEmpty && !senderIDs.contains(message.sendID)) {
      return false;
    }
    if (messageTypes.isNotEmpty &&
        !messageTypes.contains(message.contentType)) {
      return false;
    }
    final start = localStart;
    final end = localEndExclusive;
    if (start != null && end != null) {
      final sentAt = message.sendTime;
      if (sentAt == null ||
          sentAt < start.millisecondsSinceEpoch ||
          sentAt >= end.millisecondsSinceEpoch) {
        return false;
      }
    }
    return true;
  }
}

/// Returns a raw SDK page. The controller applies sender filtering while
/// advancing through raw pages, so sparse sender matches still paginate.
abstract class ChatHistorySearchSource {
  Future<List<Message>> search({
    required String conversationID,
    required ChatHistorySearchQuery query,
    required int pageIndex,
    int count = 30,
  });
}

class OpenIMChatHistorySearchSource implements ChatHistorySearchSource {
  String? _userID;
  String? _token;
  bool _sessionCaptured = false;

  void _checkSession() {
    final manager = OpenIM.iMManager;
    if (!_sessionCaptured) {
      if (manager.userID.isEmpty) {
        throw StateError('A signed-in chat session is required.');
      }
      _userID = manager.userID;
      _token = manager.token;
      _sessionCaptured = true;
    }
    if (manager.userID != _userID || manager.token != _token) {
      throw StateError('The chat session changed during history search.');
    }
  }

  @override
  Future<List<Message>> search({
    required String conversationID,
    required ChatHistorySearchQuery query,
    required int pageIndex,
    int count = 30,
  }) async {
    if (conversationID.trim().isEmpty) {
      throw ArgumentError.value(conversationID, 'conversationID');
    }
    // Keep the entire page's pagination in one account session, not merely each
    // individual SDK request. A new page creates a fresh production source.
    _checkSession();
    final response = await OpenIM.iMManager.messageManager.searchLocalMessages(
      conversationID: conversationID,
      keywordList: query.keyword.isEmpty ? const [] : [query.keyword],
      messageTypeList: query.sdkMessageTypes,
      senderUserIDList: query.senderIDs,
      searchTimePosition: query.searchTimePosition,
      searchTimePeriod: query.searchTimePeriod,
      pageIndex: pageIndex,
      count: count,
    );
    _checkSession();
    return [
      for (final item in response.searchResultItems ?? <SearchResultItems>[])
        if (item.conversationID == conversationID) ...?item.messageList,
    ];
  }
}
