import 'package:openim_common/localization.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

/// Revalidates a quote snapshot before using the chat's history positioning.
class ChatQuoteNavigation {
  ChatQuoteNavigation(
      {required this.findMessage,
      required this.focusMessage,
      required this.isAvailable,
      required this.showFeedback});

  final Future<Message?> Function(String) findMessage;
  final Future<bool> Function(Message) focusMessage;
  final bool Function(Message) isAvailable;
  final void Function(String) showFeedback;
  bool _opening = false;

  Future<bool> open(Message quote, {required bool Function() isCurrent}) async {
    if (_opening || !isCurrent()) return false;
    final id = quote.clientMsgID;
    if (id == null || id.isEmpty) {
      showFeedback(AppCopy.text('原消息不存在或已删除'));
      return false;
    }
    if (quote.hasExpired) {
      showFeedback(AppCopy.text('原消息已失效'));
      return false;
    }
    _opening = true;
    try {
      final target = await findMessage(id);
      if (!isCurrent()) return false;
      if (target == null || target.clientMsgID != id || !isAvailable(target)) {
        showFeedback(AppCopy.text('原消息不存在或已删除'));
        return false;
      }
      if (quote.hasExpired || target.hasExpired) {
        showFeedback(AppCopy.text('原消息已失效'));
        return false;
      }
      final positioned = await focusMessage(target);
      if (!isCurrent()) return false;
      if (!positioned) showFeedback(AppCopy.text('暂时无法定位原消息，请重试'));
      return positioned;
    } catch (_) {
      if (isCurrent()) showFeedback(AppCopy.text('暂时无法定位原消息，请重试'));
      return false;
    } finally {
      _opening = false;
    }
  }
}
