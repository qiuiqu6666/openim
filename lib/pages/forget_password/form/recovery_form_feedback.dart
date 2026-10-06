import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

enum RecoveryField { phone, code, password, confirmation }

/// Interaction state is separate from request ownership and form controllers.
class RecoveryFormFeedback {
  final revision = 0.obs;
  final _touched = <RecoveryField>{};
  final _focused = <RecoveryField>{};
  Object? _failure;
  String? _failurePath;

  bool shouldShow(RecoveryField field) {
    revision.value;
    return _touched.contains(field);
  }

  void onFocusChanged(RecoveryField field, bool focused) {
    if (focused) {
      _focused.add(field);
    } else if (_focused.remove(field)) {
      touch(field);
    }
  }

  void touch(RecoveryField field) {
    if (_touched.add(field)) revision.value++;
  }

  void touchAll() {
    if (_touched.length == RecoveryField.values.length) return;
    _touched.addAll(RecoveryField.values);
    revision.value++;
  }

  void edited() {
    _failure = null;
    _failurePath = null;
    revision.value++;
  }

  void clearFormError() {
    if (_failure == null) return;
    _failure = null;
    _failurePath = null;
    revision.value++;
  }

  void showFailure(Object error, {required String path}) {
    _failure = error;
    _failurePath = path;
    revision.value++;
  }

  String? get formError {
    revision.value;
    final error = _failure;
    return error == null
        ? null
        : HttpUtil.errorMessage(error, path: _failurePath);
  }
}
