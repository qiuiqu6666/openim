/// Positive membership evidence only; never stores conversation/message data.
/// Weak ownership keeps the cache within the lifetime of the live directory.
class RecentMembershipCache {
  static final _owners = Expando<RecentMembershipCache>();

  RecentMembershipCache({this.accountID, this.sessionToken});

  static RecentMembershipCache forSession(
      Object owner, String? accountID, String? sessionToken) {
    final cached = _owners[owner];
    if (cached != null &&
        cached.accountID == accountID &&
        cached.sessionToken == sessionToken) {
      return cached;
    }
    return _owners[owner] =
        RecentMembershipCache(accountID: accountID, sessionToken: sessionToken);
  }

  final String? accountID;
  final String? sessionToken;
  final _joined = <String>{};
  final _checks = <String, int>{};
  var _revision = 0;

  bool contains(String? groupID) => _joined.contains(groupID);

  int begin(String groupID) => _checks[groupID] = ++_revision;

  /// A slower background check cannot overwrite a newer send-time check.
  bool complete(String groupID, int revision, bool joined) {
    if (_checks[groupID] != revision) return false;
    if (joined) {
      _joined.add(groupID);
    } else {
      _joined.remove(groupID);
    }
    return true;
  }
}
