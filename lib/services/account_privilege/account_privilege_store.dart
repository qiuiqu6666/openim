import 'package:flutter/foundation.dart';
import 'package:openim_common/openim_common.dart';

class AccountPrivilegeSession {
  const AccountPrivilegeSession(
      {required this.userID, required this.chatToken, required this.baseUrl});
  final String userID, chatToken, baseUrl;
  Object get key => (userID, chatToken, baseUrl);
}

/// Account display permission is independent of group or administrator roles.
abstract class AccountPrivilegeAccess extends ChangeNotifier {
  int get revision;
  bool allows({required String userID, required String baseUrl});
  Future<bool> refresh();
}

class AccountPrivilegeStore extends AccountPrivilegeAccess {
  AccountPrivilegeStore({required this.session, required this.fetchProfile});
  final AccountPrivilegeSession? Function() session;
  final Future<UserFullInfo?> Function(AccountPrivilegeSession) fetchProfile;
  AccountPrivilegeSession? _verified;
  bool _allowed = false;
  int _revision = 0, _generation = 0;
  Future<UserFullInfo?>? _pending;
  Object? _pendingSession;
  Object? lastError;
  bool _closed = false;
  @override
  int get revision => _revision;

  @override
  bool allows({required String userID, required String baseUrl}) {
    final current = session();
    return !_closed &&
        _allowed &&
        current != null &&
        _verified?.key == current.key &&
        userID == current.userID &&
        _base(baseUrl) == _base(current.baseUrl);
  }

  String _base(String value) => value.replaceFirst(RegExp(r'/+$'), '');

  void _set(AccountPrivilegeSession? verified, bool allowed) {
    if (_verified?.key == verified?.key && _allowed == allowed) return;
    _verified = verified;
    _allowed = allowed;
    _revision++;
    notifyListeners();
  }

  void reset() {
    _generation++;
    _pending = null;
    _pendingSession = null;
    lastError = null;
    _set(null, false);
  }

  @override
  Future<bool> refresh() async {
    final profile = await refreshProfile();
    final current = session();
    return profile?.isPrivileged == true &&
        current != null &&
        allows(userID: current.userID, baseUrl: current.baseUrl);
  }

  /// Concurrent login/foreground/entry refreshes share one authenticated read.
  Future<UserFullInfo?> refreshProfile() {
    if (_closed) return Future.value(null);
    final current = session();
    if (current == null ||
        current.userID.isEmpty ||
        current.chatToken.isEmpty ||
        current.baseUrl.isEmpty) {
      reset();
      return Future.value(null);
    }
    if (_pending != null && _pendingSession == current.key) return _pending!;
    if (_verified?.key != current.key) _set(null, false);
    final generation = ++_generation;
    _pendingSession = current.key;
    lastError = null;
    bool accepts() =>
        !_closed && generation == _generation && session()?.key == current.key;
    late final Future<UserFullInfo?> task;
    task =
        Future<UserFullInfo?>.sync(() => fetchProfile(current)).then((profile) {
      if (!accepts()) return null;
      if (profile == null || profile.userID != current.userID) {
        _set(null, false);
        return null;
      }
      _set(current, profile.isPrivileged == true);
      return profile;
    }).catchError((Object error) {
      if (accepts()) {
        lastError = error;
        _set(null, false);
      }
      return null;
    }).whenComplete(() {
      if (identical(_pending, task)) {
        _pending = null;
        _pendingSession = null;
      }
    });
    _pending = task;
    return task;
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    _pending = null;
    super.dispose();
  }
}
