import 'dart:convert';

import 'package:openim_common/openim_common.dart';

final _legacySourceTag = RegExp(r'\[99chat_src:(AddSource_Type_[^\]]+)\]');

/// Strip transport metadata for presentation; retain the SDK record verbatim.
String friendApplicationWording(String? wording) =>
    (wording ?? '').replaceAll(_legacySourceTag, '').trim();

String friendApplicationVerification(String? wording,
    {required bool english, String? nickname}) {
  var text = friendApplicationWording(wording);
  final name = nickname?.trim() ?? '';
  if (name.isNotEmpty) {
    for (final placeholder in ['{name}', '{option1}', '（name）', '(name)']) {
      text = text.replaceAll(placeholder, name);
    }
  }
  if (text.isEmpty) {
    return english
        ? 'Verification: Wants to add you as a friend'
        : '验证：请求添加你为好友';
  }
  if (text.startsWith('我是') ||
      text.startsWith('验证') ||
      text.startsWith('I am') ||
      text.startsWith('Verification')) {
    return text;
  }
  return english ? 'Verification: $text' : '验证：$text';
}

/// Application metadata is for display only, never for authorizing a request.
FriendAddSource? friendApplicationSource(String? extension) {
  try {
    final value = jsonDecode(extension ?? '');
    if (value is! Map) return null;
    final source = value['addSource'] ?? value['source'];
    if (source is! String) return null;
    final name = source.trim().toLowerCase();
    for (final candidate in FriendAddSource.values) {
      if (candidate.name == name) return candidate;
    }
  } catch (_) {
    // Old records and opaque signatures do not establish an adding method.
  }
  return null;
}

String friendApplicationSourceLabel(String? extension,
    {required bool english}) {
  final source = friendApplicationSource(extension);
  return switch (source) {
    FriendAddSource.account => english ? 'Added via 99 ID' : '通过99号添加',
    FriendAddSource.phone => english ? 'Added via phone number' : '通过手机号添加',
    FriendAddSource.email => english ? 'Added via email' : '通过邮箱添加',
    FriendAddSource.qrcode => english ? 'Added via QR code' : '通过二维码添加',
    FriendAddSource.link => english ? 'Added via invitation link' : '通过邀请链接添加',
    FriendAddSource.card => english ? 'Added via contact card' : '通过名片添加',
    FriendAddSource.group => english ? 'Added via group' : '通过群聊添加',
    FriendAddSource.manage =>
      english ? 'Added via group management' : '通过群管理添加',
    FriendAddSource.uid => english ? 'Added via user ID' : '通过用户ID添加',
    FriendAddSource.search => english ? 'Added via search' : '通过搜索添加',
    FriendAddSource.chat => english ? 'Added via chat' : '通过聊天添加',
    null => english ? 'Source unknown' : '来源未知',
  };
}
