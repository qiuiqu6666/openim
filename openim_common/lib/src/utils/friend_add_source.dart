import 'dart:convert';
import 'package:flutter/services.dart';
import 'data_sp.dart';
import '../models/user_full_info.dart';
import '../apis.dart';
import '../models/contact_card/contact_card_identity.dart';

Future<String> createFriendCardExtension(String userID,
        {String? account}) async =>
    jsonEncode({
      'inviteCode': await Apis.createFriendInvite(FriendAddSource.card,
          targetUserID: userID),
      ...contactCardIdentityFields(userID, account),
    });

String? friendCardInviteCode(String? extension) {
  try {
    final value = jsonDecode(extension ?? '')['inviteCode'];
    return value is String ? value : null;
  } catch (_) {
    return null;
  }
}

Map<String, String>? parseFriendInvite(String text) {
  final uri = Uri.tryParse(text.trim());
  if (uri?.scheme != 'openim' ||
      uri?.host != 'user' ||
      uri!.pathSegments.length != 1) {
    return null;
  }
  final source = uri.queryParameters['source'];
  final code = uri.queryParameters['inviteCode'];
  if (!{'qrcode', 'link'}.contains(source) || code?.startsWith('fi_') != true) {
    return null;
  }
  return {
    'userID': uri.pathSegments.first,
    'inviteCode': code!,
    'source': source!
  };
}

enum FriendAddSource {
  qrcode,
  link,
  manage,
  card,
  group,
  phone,
  uid,
  account,
  email,
  search,
  chat
}

FriendAddSource resolveFriendAddSource(Object? source, {String? groupID}) =>
    source is FriendAddSource
        ? source
        : groupID?.trim().isNotEmpty == true
            ? FriendAddSource.group
            : FriendAddSource.chat;

/// Public accounts may be entered with or without their display prefix.
String? normalizePublicAccountSearch(String value) {
  final account = value.trim().replaceFirst(RegExp(r'^@'), '');
  return RegExp(r'^[a-z0-9]{10}$').hasMatch(account) ? account : null;
}

FriendAddSource friendSearchSource(String keyword, UserFullInfo info) {
  final query = keyword.trim();
  final account = normalizePublicAccountSearch(query);
  if (account != null) {
    return account == normalizePublicAccountSearch(info.account ?? '')
        ? FriendAddSource.account
        : FriendAddSource.search;
  }
  if (info.email?.isNotEmpty == true && query == info.email) {
    return FriendAddSource.email;
  }
  final phone = info.phoneNumber?.trim();
  if (phone != null && phone.isNotEmpty && query == phone) {
    return FriendAddSource.phone;
  }
  if (query.contains('@') && !query.startsWith('@')) {
    return FriendAddSource.email;
  }
  if (RegExp(r'^\+?\d+$').hasMatch(query)) return FriendAddSource.phone;
  return FriendAddSource.search;
}

/// Exchange entry details only when the user submits, then consume the grant.
class FriendAddRequest {
  static bool canSend({
    required String userID,
    required FriendAddSource source,
    String? groupID,
    Map<String, String> fields = const {},
  }) =>
      input(
        userID: userID,
        source: source,
        groupID: groupID,
        fields: fields,
      ) !=
      null;

  /// The same entry requirements are used by the UI and the actual request.
  /// Unsupported or incomplete entries never infer another source from fields.
  static Map<String, String>? input({
    required String userID,
    required FriendAddSource source,
    String? groupID,
    Map<String, String> fields = const {},
  }) {
    final requiredFields = switch (source) {
      FriendAddSource.account => ['account'],
      FriendAddSource.phone => ['areaCode', 'phoneNumber'],
      FriendAddSource.email => ['email'],
      FriendAddSource.qrcode ||
      FriendAddSource.link ||
      FriendAddSource.card =>
        ['inviteCode'],
      FriendAddSource.group || FriendAddSource.manage => [
          'groupID',
          'targetUserID'
        ],
      _ => null,
    };
    if (requiredFields == null) {
      return null;
    }
    final entry = {
      ...fields,
      if (source == FriendAddSource.group || source == FriendAddSource.manage)
        'groupID': groupID ?? '',
      if (source == FriendAddSource.group || source == FriendAddSource.manage)
        'targetUserID': userID,
    };
    if (requiredFields.any((key) => entry[key]?.trim().isNotEmpty != true)) {
      return null;
    }
    return {
      'source': source.name,
      for (final key in requiredFields) key: entry[key]!.trim(),
    };
  }

  static Future<dynamic> send({
    required String userID,
    required String reason,
    required FriendAddSource source,
    String? groupID,
    Map<String, String> fields = const {},
  }) async {
    final owner = DataSp.userID;
    final token = DataSp.chatToken;
    if (owner == null || token == null) throw PlatformException(code: '20013');
    final parameters = input(
      userID: userID,
      source: source,
      groupID: groupID,
      fields: fields,
    );
    if (parameters == null) {
      throw PlatformException(code: 'FriendGrantRequired');
    }
    final grant = await Apis.createFriendGrant(parameters);
    if (DataSp.userID != owner || DataSp.chatToken != token) {
      throw PlatformException(code: '20013');
    }
    return Apis.applyFriendGrant(grant: grant, message: reason);
  }
}

String? friendAddErrorMessage(Object error, {required bool chinese}) {
  final code = error is PlatformException
      ? error.code
      : error is (int, String)
          ? '${error.$1}'
          : null;
  final detail = error is (int, String) ? error.$2 : '';
  if (code == '20020') {
    return switch (detail) {
      'too frequent' =>
        chinese ? '操作过于频繁，请稍后重试' : 'Too many attempts. Please try later.',
      'group protected' => chinese
          ? '该群已开启成员保护，无法从群内添加'
          : 'This group protects its members from friend requests.',
      'invite invalid' => chinese
          ? '邀请已失效，请获取新的邀请'
          : 'This invitation is invalid. Request a new invitation.',
      'target invalid' => chinese ? '未找到可添加的用户' : 'No eligible user found.',
      _ => chinese ? '对方不允许通过此方式添加' : 'This person does not allow this method.',
    };
  }
  return switch (code) {
    '20044' => chinese
        ? '对方不允许通过此方式添加'
        : 'This person does not allow this method of adding friends.',
    '20013' => chinese
        ? '添加邀请无效或已过期，请重新进入添加入口'
        : 'The friend invitation is invalid or expired. Reopen the entry.',
    '500' =>
      chinese ? '服务暂不可用，请稍后重试' : 'Service unavailable. Please try again later.',
    'FriendGrantRequired' => chinese
        ? '请通过对方的聊天号、二维码或名片添加好友'
        : 'Please add this person using their chat number, QR code or contact card.',
    _ => null,
  };
}
