import 'package:openim/services/account_privilege/account_privilege_store.dart';

/// Explicit authenticated-account grant for business-permission widget tests.
class FixtureAccountPrivilege extends AccountPrivilegeAccess {
  FixtureAccountPrivilege({bool allowed = true}) : _allowed = allowed;
  bool _allowed;
  int _revision = 0;
  int refreshCount = 0;
  @override
  int get revision => _revision;
  @override
  bool allows({required String userID, required String baseUrl}) => _allowed;
  @override
  Future<bool> refresh() async {
    refreshCount++;
    return _allowed;
  }

  void setAllowed(bool value) {
    if (value == _allowed) return;
    _allowed = value;
    _revision++;
    notifyListeners();
  }
}
