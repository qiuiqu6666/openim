import 'package:flutter/material.dart';
import '../../../services/moments_repository.dart';

String momentsText(BuildContext context,
        {required String zh, required String en}) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

bool momentsDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

String momentsErrorText(BuildContext context, Object error) {
  if (error is MomentsException) {
    if (error.code == 'VERSION_CONFLICT') {
      return momentsText(context,
          zh: '内容已在其他设备变更，请刷新后重试',
          en: 'This changed on another device. Refresh and try again.');
    }
    if (error.code == 'RELATION_UNAVAILABLE') {
      return momentsText(context,
          zh: '暂时无法确认好友关系或拉黑状态，请稍后重试',
          en: 'Could not verify friendship or blocked status. Try again shortly.');
    }
    if (error.code == 'FRIENDSHIP_UNAVAILABLE') {
      return momentsText(context,
          zh: '暂时无法确认好友关系，请稍后重试',
          en: 'Could not verify friends. Try again shortly.');
    }
    if (error.code == 'CONTEXT_CHANGED') {
      return momentsText(context,
          zh: '好友关系或隐私设置已变化，请刷新后重试',
          en: 'Friendship or privacy changed. Refresh and try again.');
    }
    if (error.code == 'CURSOR_EXPIRED') {
      return momentsText(context,
          zh: '列表已更新，请重新加载后继续',
          en: 'This list has changed. Reload it to continue.');
    }
    if (const ['MEDIA_NOT_READY', 'MEDIA_PROCESSING'].contains(error.code)) {
      return momentsText(context,
          zh: '图片尚未处理完成，请稍后重试',
          en: 'The image is still processing. Try again shortly.');
    }
    if (error.code == 'MEDIA_EXPIRED') {
      return momentsText(context,
          zh: '上传的图片已过期，请重新选择图片',
          en: 'The uploaded image expired. Choose the image again.');
    }
    if (error.code == 'IDEMPOTENCY_CONFLICT') {
      return momentsText(context,
          zh: '原任务内容不一致，请保留原任务与原内容后重试',
          en: 'The original task has different content. Keep its original content before retrying.');
    }
    if (const ['MOMENT_UNAVAILABLE', 'PERMISSION_REVOKED']
        .contains(error.code)) {
      return momentsText(context,
          zh: '内容已不可用或查看权限已变更', en: 'This content is no longer available.');
    }
    if (error.authRequired) {
      return momentsText(context,
          zh: '请重新登录后再试', en: 'Sign in again to continue.');
    }
    if (error.unavailable) {
      return momentsText(context,
          zh: '朋友圈暂未开放，请稍后再来', en: 'Moments is not available yet.');
    }
    if (error.permissionDenied) {
      return momentsText(context,
          zh: '内容已不可用或查看权限已变更', en: 'This content is no longer available.');
    }
    if (error.unknownResult) {
      return momentsText(context,
          zh: '正在确认提交结果，请保持原内容重试',
          en: 'The result is not confirmed. Retry with the same content.');
    }
  }
  return momentsText(context,
      zh: '暂时无法完成，请检查网络后重试', en: 'Please check your connection and try again.');
}

String momentsTime(BuildContext context, int timestamp) {
  final local = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
  final now = DateTime.now();
  final elapsed = now.difference(local);
  if (elapsed.isNegative || elapsed.inMinutes < 1) {
    return momentsText(context, zh: '刚刚', en: 'Just now');
  }
  if (elapsed.inHours < 1) {
    return momentsText(context,
        zh: '${elapsed.inMinutes} 分钟前', en: '${elapsed.inMinutes}m ago');
  }
  if (elapsed.inDays < 1) {
    return momentsText(context,
        zh: '${elapsed.inHours} 小时前', en: '${elapsed.inHours}h ago');
  }
  if (elapsed.inDays < 7) {
    return momentsText(context,
        zh: '${elapsed.inDays} 天前', en: '${elapsed.inDays}d ago');
  }
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$month-$day';
}

String momentsDetailTime(BuildContext context, int timestamp,
    {bool includeYear = true}) {
  final local = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
  final clock =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return momentsText(context,
      zh: '${includeYear ? '${local.year}年' : ''}${local.month}月${local.day}日 $clock',
      en: '${includeYear ? '${local.year}-' : ''}$month-$day $clock');
}

String momentsVisibilityText(BuildContext context, String visibility) =>
    switch (visibility) {
      'SELF' => momentsText(context, zh: '仅自己可见', en: 'Only me'),
      'PARTIAL' => momentsText(context, zh: '部分好友可见', en: 'Selected friends'),
      'EXCLUDE' =>
        momentsText(context, zh: '不给部分好友看', en: 'Except selected friends'),
      _ => momentsText(context, zh: '好友可见', en: 'Friends'),
    };
