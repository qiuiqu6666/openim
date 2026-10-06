import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';

import '../../../widgets/auth/auth_form_rules.dart';

class ResetPasswordLogic extends GetxController {
  final pwdCtrl = TextEditingController();
  final pwdAgainCtrl = TextEditingController();
  final enabled = false.obs;
  final submitting = false.obs;
  bool _closed = false;
  String? phoneNumber;
  String? email;
  late String areaCode;
  late int usedFor;
  late String verificationCode;
  String? invitationCode;

  @override
  void onClose() {
    _closed = true;
    pwdCtrl.dispose();
    pwdAgainCtrl.dispose();
    super.onClose();
  }

  @override
  void onInit() {
    phoneNumber = Get.arguments['phoneNumber'];
    email = Get.arguments['email'];
    areaCode = Get.arguments['areaCode'];
    verificationCode = Get.arguments['verificationCode'];
    pwdCtrl.addListener(_onChanged);
    pwdAgainCtrl.addListener(_onChanged);
    super.onInit();
  }

  void _onChanged() {
    enabled.value =
        pwdCtrl.text.trim().isNotEmpty && pwdAgainCtrl.text.trim().isNotEmpty;
  }

  bool _checkingInput() {
    final error = (email != null
            ? AuthFormRules.email(email)
            : AuthFormRules.phone(phoneNumber, areaCode)) ??
        AuthFormRules.password(pwdCtrl.text) ??
        AuthFormRules.confirmPassword(pwdAgainCtrl.text, pwdCtrl.text) ??
        AuthFormRules.verificationCode(verificationCode);
    if (error == null) return true;
    IMViews.showToast(error);
    return false;
  }

  Future<void> resetPassword() async {
    if (_closed || isClosed || !_checkingInput()) return;
    final requestedPassword = pwdCtrl.text;
    await LoadingView.singleton.wrap(
        asyncFunction: () => Apis.resetPassword(
              areaCode: areaCode,
              phoneNumber: phoneNumber,
              email: email,
              password: requestedPassword,
              verificationCode: verificationCode,
            ));
  }

  Future<void> confirmTheChanges() async {
    if (_closed || isClosed || submitting.value || !_checkingInput()) return;
    submitting.value = true;
    try {
      await resetPassword();
      if (_closed || isClosed) return;
      IMViews.showToast(StrRes.changedSuccessfully);
      AppNavigator.startBackLogin();
    } catch (_) {
      // The API displays request errors; keep both passwords for retry.
    } finally {
      if (!_closed && !isClosed) submitting.value = false;
    }
  }
}
