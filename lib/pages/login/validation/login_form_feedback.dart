import 'package:get/get.dart';

enum LoginFormField { account, password, code }

/// Owns display timing; validation rules remain in the existing auth rules.
class LoginFormFeedback {
  final failure = Rxn<Object>();
  String? failurePath;
  final _revision = 0.obs;
  final _focused = <LoginFormField>{};
  final _touched = <LoginFormField>{};

  void focusChanged(LoginFormField field, bool hasFocus) {
    if (hasFocus) {
      _focused.add(field);
    } else if (_focused.remove(field)) {
      _touched.add(field);
      _revision.value++;
    }
  }

  bool touched(LoginFormField field) {
    _revision.value;
    return _touched.contains(field);
  }

  void refresh({bool edited = false}) {
    _revision.value++;
    if (edited) failure.value = null;
  }

  void recordFailure(Object error, String path) {
    failurePath = path;
    failure.value = error;
  }

  bool validate({
    required String? account,
    required String? password,
    required String? code,
    required bool passwordLogin,
    bool accountOnly = false,
  }) {
    _touched.add(LoginFormField.account);
    if (!accountOnly) {
      _touched
          .add(passwordLogin ? LoginFormField.password : LoginFormField.code);
    }
    refresh(edited: true);
    return account == null &&
        (accountOnly || (passwordLogin ? password == null : code == null));
  }

  void reset() {
    _touched.clear();
    _focused.clear();
    failurePath = null;
    refresh(edited: true);
  }
}
