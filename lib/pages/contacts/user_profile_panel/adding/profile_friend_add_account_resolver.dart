import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../search/contact_search_source.dart';

enum ProfileFriendAddUnavailableReason { missingAccount, targetUnavailable }

class ProfileFriendAddUnavailable implements Exception {
  const ProfileFriendAddUnavailable(this.reason);

  final ProfileFriendAddUnavailableReason reason;
}

/// Verifies a visible public account through the formal account search.
/// Its result belongs to this page's initial session and latest request only.
class ProfileFriendAddAccountResolver {
  ProfileFriendAddAccountResolver({
    ContactSearchSource? source,
    String? Function()? owner,
    String? Function()? sdkOwner,
    String? Function()? token,
    String Function()? server,
  })  : _source = source ?? ContactSearchSource(),
        _owner = owner ?? (() => DataSp.userID),
        _sdkOwner = sdkOwner ?? _readSdkUserID,
        _token = token ?? (() => DataSp.chatToken),
        _server = server ?? (() => Config.appAuthUrl) {
    _scope = _session;
  }

  final ContactSearchSource _source;
  final String? Function() _owner;
  final String? Function() _sdkOwner;
  final String? Function() _token;
  final String Function() _server;
  late final (String?, String?, String?, String) _scope;
  int _generation = 0;
  bool _closed = false;
  bool _invalidated = false;

  (String?, String?, String?, String) get _session =>
      (_owner(), _sdkOwner(), _token(), _server());

  bool get isCurrentSession {
    if (_closed || _invalidated) {
      return false;
    }
    if (_scope.$1?.trim().isNotEmpty != true ||
        _scope.$3?.isNotEmpty != true ||
        _scope != _session) {
      _invalidated = true;
      ++_generation;
      return false;
    }
    return true;
  }

  bool _accepts(int generation) =>
      isCurrentSession && generation == _generation;

  Future<String?> resolve({
    required String userID,
    required String account,
  }) async {
    final generation = ++_generation;
    if (!isCurrentSession) {
      return null;
    }
    final normalized = normalizePublicAccountSearch(account);
    if (normalized == null) {
      throw const ProfileFriendAddUnavailable(
          ProfileFriendAddUnavailableReason.missingAccount);
    }
    if (userID.trim().isEmpty) {
      throw const ProfileFriendAddUnavailable(
          ProfileFriendAddUnavailableReason.targetUnavailable);
    }
    try {
      final users = await _source.users('@$normalized', 1);
      if (!_accepts(generation)) {
        return null;
      }
      for (final user in users ?? <UserFullInfo>[]) {
        if (user.userID == userID &&
            normalizePublicAccountSearch(user.account ?? '') == normalized) {
          return user.account!.trim();
        }
      }
      throw const ProfileFriendAddUnavailable(
          ProfileFriendAddUnavailableReason.targetUnavailable);
    } catch (_) {
      if (!_accepts(generation)) {
        return null;
      }
      rethrow;
    }
  }

  void close() {
    _closed = true;
    ++_generation;
  }

  static String? _readSdkUserID() {
    try {
      return OpenIM.iMManager.userID;
    } catch (_) {
      return null;
    }
  }
}
