import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

typedef SearchProfileLookup = Future<List<PublicUserInfo>> Function(
    List<String> ids);

/// Page-local cache, shared by repeated senders and overlapping result pages.
class SearchSenderProfiles {
  SearchSenderProfiles({SearchProfileLookup? lookup})
      : _lookup = lookup ??
            ((ids) =>
                OpenIM.iMManager.userManager.getUsersInfo(userIDList: ids));

  final SearchProfileLookup _lookup;
  final _pending = <String, Future<PublicUserInfo?>>{};

  Future<void> enrich(List<Message> messages,
      {required bool Function() isCurrent}) async {
    if (!isCurrent()) return;
    final ids = messages
        .map((m) => m.sendID ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final missing = ids.where((id) => !_pending.containsKey(id)).toList();
    if (missing.isNotEmpty) {
      final batch = Future.sync(() => _lookup(missing));
      for (final id in missing) {
        _pending[id] = batch.then((users) {
          for (final user in users) {
            if (user.userID == id) return user;
          }
          return null;
        }, onError: (Object _) {
          _pending.remove(id);
          return null;
        });
      }
    }
    final profiles = <String, PublicUserInfo?>{};
    for (final id in ids) {
      profiles[id] = await _pending[id];
    }
    if (!isCurrent()) return;
    for (final message in messages) {
      final profile = profiles[message.sendID];
      if (profile?.nickname?.trim().isNotEmpty == true) {
        message.senderNickname = profile!.nickname;
      }
      if (profile?.faceURL?.trim().isNotEmpty == true) {
        message.senderFaceUrl = profile!.faceURL;
      }
    }
  }
}
