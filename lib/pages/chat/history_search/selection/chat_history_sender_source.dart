import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

class ChatHistorySender {
  const ChatHistorySender({
    required this.userID,
    required this.displayName,
    this.nickname,
    this.faceURL,
    this.ex,
  });

  final String userID;
  final String displayName;
  final String? nickname;
  final String? faceURL;
  final String? ex;

  String get name =>
      nickname?.trim().isNotEmpty == true ? nickname!.trim() : displayName;
}

class ChatHistorySenderPageData {
  const ChatHistorySenderPageData({
    required this.items,
    required this.nextOffset,
    required this.hasMore,
  });

  final List<ChatHistorySender> items;
  final int nextOffset;
  final bool hasMore;
}

/// Only resolves people belonging to the requested conversation.
abstract class ChatHistorySenderSource {
  String get currentUserID;

  Future<ChatHistorySenderPageData> load({
    required String conversationID,
    required String query,
    required int offset,
    required int count,
  });
}

class OpenIMChatHistorySenderSource implements ChatHistorySenderSource {
  @override
  String get currentUserID => OpenIM.iMManager.userID;

  void _checkAccount(String ownerID) {
    if (ownerID.isEmpty || currentUserID != ownerID) {
      throw StateError('Chat search account changed');
    }
  }

  @override
  Future<ChatHistorySenderPageData> load({
    required String conversationID,
    required String query,
    required int offset,
    required int count,
  }) async {
    final ownerID = currentUserID;
    _checkAccount(ownerID);
    if (conversationID.isEmpty || offset < 0 || count <= 0) {
      throw ArgumentError('Invalid conversation member request');
    }
    final conversations = await OpenIM.iMManager.conversationManager
        .getMultipleConversation(conversationIDList: [conversationID]);
    _checkAccount(ownerID);
    final matches =
        conversations.where((c) => c.conversationID == conversationID);
    if (matches.length != 1) throw StateError('Conversation unavailable');
    final conversation = matches.single;
    final groupID = conversation.groupID?.trim() ?? '';
    final keyword = query.trim();
    if (groupID.isNotEmpty) {
      if (conversation.isNotInGroup == true) {
        throw StateError('Conversation membership unavailable');
      }
      final manager = OpenIM.iMManager.groupManager;
      final members = keyword.isEmpty
          ? await manager.getGroupMemberList(
              groupID: groupID,
              filter: 0,
              offset: offset,
              count: count,
            )
          : await manager.searchGroupMembers(
              groupID: groupID,
              keywordList: [keyword],
              isSearchUserID: false,
              isSearchMemberNickname: true,
              offset: offset,
              count: count,
            );
      _checkAccount(ownerID);
      final seen = <String>{};
      final pageMembers = [
        for (final member in members)
          if ((member.userID?.trim().isNotEmpty ?? false) &&
              (member.groupID?.isNotEmpty != true ||
                  member.groupID == groupID) &&
              seen.add(member.userID!))
            member,
      ];
      // A group card can differ from the public nickname. Resolve only this
      // page's valid members without changing the SDK search or its cursor.
      var users = <PublicUserInfo>[];
      if (seen.isNotEmpty) {
        try {
          users = await OpenIM.iMManager.userManager.getUsersInfo(
            userIDList: seen.toList(growable: false),
          );
        } catch (_) {
          // Public profiles are optional; the member card remains a fallback.
        }
        _checkAccount(ownerID);
      }
      final profilesByID = {
        for (final user in users)
          if (seen.contains(user.userID)) user.userID: user,
      };
      return ChatHistorySenderPageData(
        items: [
          for (final member in pageMembers)
            ChatHistorySender(
              userID: member.userID!,
              displayName: _name(member.nickname, member.userID!),
              nickname: profilesByID[member.userID]?.nickname,
              faceURL: member.faceURL,
              ex: profilesByID[member.userID]?.ex ?? member.ex,
            ),
        ],
        // Advance by the raw SDK page, including duplicates and invalid rows.
        nextOffset: offset + members.length,
        hasMore: members.length >= count,
      );
    }
    final peerID = conversation.userID?.trim() ?? '';
    if (peerID.isEmpty) throw StateError('Conversation sender unavailable');
    final ids = <String>{ownerID, peerID};
    final users = await OpenIM.iMManager.userManager.getUsersInfo(
      userIDList: ids.toList(growable: false),
    );
    _checkAccount(ownerID);
    final usersByID = {for (final user in users) user.userID: user};
    final items = <ChatHistorySender>[
      for (final id in ids)
        ChatHistorySender(
          userID: id,
          displayName: _name(
            id == peerID ? conversation.showName : usersByID[id]?.nickname,
            _name(usersByID[id]?.nickname, id),
          ),
          nickname: usersByID[id]?.nickname,
          faceURL: usersByID[id]?.faceURL ??
              (id == peerID ? conversation.faceURL : null),
          ex: usersByID[id]?.ex,
        ),
    ]
        .where((sender) =>
            keyword.isEmpty ||
            sender.name.toLowerCase().contains(keyword.toLowerCase()) ||
            sender.displayName.toLowerCase().contains(keyword.toLowerCase()))
        .toList();
    return ChatHistorySenderPageData(
      items: items.skip(offset).take(count).toList(growable: false),
      nextOffset: offset + items.skip(offset).take(count).length,
      hasMore: offset + count < items.length,
    );
  }

  static String _name(String? value, String fallback) =>
      value?.trim().isNotEmpty == true ? value!.trim() : fallback;
}
