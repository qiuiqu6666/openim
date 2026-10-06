import 'package:openim/pages/mine/settings/widgets/account_code_request.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';

import '../login/login_logic.dart';
import '../../widgets/auth/auth_copy.dart';
import '../../widgets/auth/auth_form_rules.dart';
import '../../services/auth_credentials/auth_credentials_store.dart';
import 'form/recovery_form_feedback.dart';

class ForgetPasswordLogic extends GetxController {
  final phoneCtrl = TextEditingController();
  final verificationCodeCtrl = TextEditingController();
  final pwdCtrl = TextEditingController();
  final pwdAgainCtrl = TextEditingController();
  final areaCode = "+86".obs;
  final enabled = false.obs;
  final submitting = false.obs;
  final feedback = RecoveryFormFeedback();
  bool _closed = false;
  Worker? _areaCodeWorker;
  ({
    String phone,
    String code,
    String password,
    String confirmation,
    String areaCode,
  })? _lastInputs;
  final loginController = Get.find<LoginLogic>();
  ({String areaCode, String phone, String code, String password})? _submission;

  // The reference recovery form sends SMS to the phone entered on this page,
  // independently of the credential tab used on the login page.
  String? get email => null;
  String get phone => phoneCtrl.text.trim();
  String? get formError => feedback.formError;

  String? fieldError(RecoveryField field) {
    if (!feedback.shouldShow(field)) return null;
    return switch (field) {
      RecoveryField.phone => AuthFormRules.phone(phone, areaCode.value),
      RecoveryField.code => AuthFormRules.verificationCode(
          verificationCodeCtrl.text,
          sixDigits: true),
      RecoveryField.password => passwordError(pwdCtrl.text),
      RecoveryField.confirmation =>
        AuthFormRules.confirmPassword(pwdAgainCtrl.text, pwdCtrl.text),
    };
  }

  void onFocusChanged(RecoveryField field, bool focused) {
    if (!_closed && !isClosed) feedback.onFocusChanged(field, focused);
  }

  static final _passwordPattern =
      RegExp(r'^(?=.*[A-Za-z])(?=.*\d)[A-Za-z\d]{8,}$');

  String? passwordError(String? value) {
    if ((value ?? '').isEmpty) return StrRes.plsEnterPassword;
    return _passwordPattern.hasMatch(value!)
        ? null
        : authText('密码需为 8 位以上英文和数字组合',
            'Password must contain letters and numbers with at least 8 characters');
  }

  @override
  void onClose() {
    _closed = true;
    _areaCodeWorker?.dispose();
    phoneCtrl.dispose();
    verificationCodeCtrl.dispose();
    pwdCtrl.dispose();
    pwdAgainCtrl.dispose();
    super.onClose();
  }

  @override
  void onInit() {
    phoneCtrl.addListener(_onChanged);
    verificationCodeCtrl.addListener(_onChanged);
    pwdCtrl.addListener(_onChanged);
    pwdAgainCtrl.addListener(_onChanged);
    _areaCodeWorker = ever(areaCode, (_) => _onChanged());
    super.onInit();
  }

  void _onChanged() {
    if (_closed || isClosed) return;
    final inputs = (
      phone: phoneCtrl.text,
      code: verificationCodeCtrl.text,
      password: pwdCtrl.text,
      confirmation: pwdAgainCtrl.text,
      areaCode: areaCode.value,
    );
    if (_lastInputs != inputs) {
      _lastInputs = inputs;
      feedback.edited();
    }
    enabled.value = AuthFormRules.phone(phone, areaCode.value) == null &&
        AuthFormRules.verificationCode(verificationCodeCtrl.text,
                sixDigits: true) ==
            null &&
        passwordError(pwdCtrl.text) == null &&
        AuthFormRules.confirmPassword(pwdAgainCtrl.text, pwdCtrl.text) == null;
  }

  void openCountryCodePicker() async {
    if (_closed || isClosed || submitting.value) return;
    String? code = await IMViews.showCountryCodePicker();
    if (!_closed && !isClosed && code != null) {
      areaCode.value = code;
    }
  }

  Future<bool> getVerificationCode() async {
    if (_closed || isClosed || submitting.value || !_checkingAccount()) {
      return false;
    }
    return sendVerificationCode();
  }

  bool _checkingAccount() {
    feedback.touch(RecoveryField.phone);
    final error = AuthFormRules.phone(phone, areaCode.value);
    if (error == null) return true;
    return false;
  }

  Future<bool> sendVerificationCode() => requestAccountVerificationCode(
        areaCode: areaCode.value,
        phoneNumber: phone,
        email: email,
        usedFor: 2,
      );

  Future<void> checkVerificationCode() async {
    final request = _submission;
    if (request == null || _closed || isClosed) return;
    await Apis.checkVerificationCode(
      areaCode: request.areaCode,
      phoneNumber: request.phone,
      verificationCode: request.code,
      usedFor: 2,
      showErrorToast: false,
    );
  }

  Future<void> resetPassword() async {
    final request = _submission;
    if (request == null || _closed || isClosed) return;
    await Apis.resetPassword(
      areaCode: request.areaCode,
      phoneNumber: request.phone,
      verificationCode: request.code,
      password: request.password,
      showErrorToast: false,
    );
  }

  Future<void> nextStep() async {
    if (_closed || isClosed || submitting.value) return;
    feedback.touchAll();
    if (!_checkingAccount()) return;
    final error = AuthFormRules.verificationCode(verificationCodeCtrl.text,
            sixDigits: true) ??
        passwordError(pwdCtrl.text) ??
        AuthFormRules.confirmPassword(pwdAgainCtrl.text, pwdCtrl.text);
    if (error != null) {
      return;
    }
    feedback.clearFormError();
    _submission = (
      areaCode: areaCode.value,
      phone: phone,
      code: verificationCodeCtrl.text.trim(),
      password: pwdCtrl.text,
    );
    final request = _submission!;
    submitting.value = true;
    var failurePath = Urls.checkVerificationCode;
    try {
      await checkVerificationCode();
      if (_closed || isClosed) return;
      failurePath = Urls.resetPwd;
      await resetPassword();
      if (_closed || isClosed) return;
      try {
        await AuthCredentialsStore.instance.updatePasswordIfRemembered(
          account: request.phone,
          areaCode: request.areaCode,
          password: request.password,
          isCurrent: () => !_closed && !isClosed && _submission == request,
        );
      } catch (error) {
        // A successful reset must remain successful when secure storage fails.
        Logger.print('Remembered password update failed: ${error.runtimeType}');
      }
      if (_closed || isClosed) return;
      if (!loginController.isClosed &&
          loginController.rememberPassword.value &&
          loginController.phoneCtrl.text.trim() == request.phone &&
          loginController.areaCode.value == request.areaCode) {
        loginController.pwdCtrl.text = request.password;
      }
      IMViews.showToast(StrRes.changedSuccessfully);
      AppNavigator.startBackLogin();
    } catch (error) {
      if (!_closed && !isClosed) {
        feedback.showFailure(error, path: failurePath);
      }
    } finally {
      _submission = null;
      if (!_closed && !isClosed) submitting.value = false;
    }
  }
}
