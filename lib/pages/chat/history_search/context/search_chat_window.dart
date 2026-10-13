import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import '../cloud/chat_keyword_search_api.dart';
import 'search_context_api.dart';

/// A validated navigation target; context stays in memory, outside SDK storage.
class SearchChatTarget extends Message {
  SearchChatTarget(this.window)
      : super.fromJson(window.initial.anchor.toJson());
  final SearchChatWindow window;
}

class SearchChatWindow {
  SearchChatWindow(this.hit, this.api, this.initial)
      : _before = initial.beforeCursor,
        _after = initial.afterCursor,
        _beforeEnd = initial.beforeEnd,
        _afterEnd = initial.afterEnd;

  final CloudKeywordMessage hit;
  final SearchContextApi api;
  final SearchContextPage initial;
  String _before, _after;
  bool _beforeEnd, _afterEnd;

  Future<AdvancedMessage> read(bool older, bool Function() isCurrent) async {
    while (isCurrent()) {
      if (older ? _beforeEnd : _afterEnd) {
        return AdvancedMessage(messageList: [], isEnd: true);
      }
      final page = await api.fetch(hit,
          cursor: older ? _before : _after,
          before: older,
          isCurrent: isCurrent);
      if (!isCurrent()) throw StateError('Chat window changed');
      if (older) {
        _before = page.beforeCursor;
        _beforeEnd = page.beforeEnd;
      } else {
        _after = page.afterCursor;
        _afterEnd = page.afterEnd;
      }
      final end = older ? _beforeEnd : _afterEnd;
      if (page.messages.isNotEmpty || end) {
        return AdvancedMessage(messageList: page.messages, isEnd: end);
      }
    }
    throw StateError('Chat window changed');
  }
}
