import 'package:flutter/widgets.dart';
import 'package:openim_common/localization.dart';

String contextText(BuildContext context, String key) {
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  const words = {
    'title': ['聊天记录上下文', 'Message context'],
    'anchor': ['搜索命中', 'Search match'],
    'before': ['更早的消息', 'Earlier messages'],
    'after': ['更新的消息', 'Later messages'],
    'end': ['已到此方向末尾', 'No more messages in this direction'],
    'retry': ['重试', 'Retry'],
    'reload': ['重新加载上下文', 'Reload context'],
    '1001': ['查询已过期，请重新加载', 'Query expired. Reload to continue.'],
    '1002': ['无权查看此会话', 'This conversation is not accessible.'],
    '404': ['消息已不可见', 'This message is no longer visible.'],
    '410': ['消息已撤回', 'This message was revoked.'],
    '409': [
      '消息已变化，请返回刷新搜索结果',
      'Message changed. Return and refresh the search.'
    ],
    '429': ['请求较频繁，请稍后重试', 'Too many requests. Please retry shortly.'],
    'auth': ['登录状态已失效，请重新登录', 'Your session expired. Sign in again.'],
    'failed': ['暂时无法加载，请稍后重试', 'Unable to load. Please retry.'],
  };
  return AppCopy.text((words[key] ?? words['failed']!)[zh ? 0 : 1],
      locale: Localizations.localeOf(context));
}

String searchErrorText(BuildContext context, int? code) => contextText(
    context, code != null && code >= 1501 && code <= 1507 ? 'auth' : '$code');
