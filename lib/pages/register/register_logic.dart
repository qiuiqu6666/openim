import 'package:openim/pages/mine/settings/widgets/account_code_request.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim/pages/login/login_logic.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';

import '../../core/controller/app_controller.dart';
import '../../core/controller/im_controller.dart';
import '../../widgets/auth/auth_form_rules.dart';
import 'profile/registration_profile_draft.dart';
import 'rules/register_password_rules.dart';
import 'rules/registration_field.dart';
import 'session/registration_session.dart';

class RegisterLogic extends GetxController {
  final appLogic = Get.find<AppController>();
  final profileDraft = RegistrationProfileDraft();
  final phoneCtrl = TextEditingController();
  final verificationCodeCtrl = TextEditingController();
  final pwdCtrl = TextEditingController();
  final pwdAgainCtrl = TextEditingController();
  final invitationCodeCtrl = TextEditingController();
  final phoneFocus = FocusNode();
  final codeFocus = FocusNode();
  final pwdFocus = FocusNode();
  final pwdAgainFocus = FocusNode();
  final obscurePassword = true.obs;
  final obscureConfirmPassword = true.obs;
  final areaCode = "+86".obs;
  final enabled = false.obs;
  final submitting = false.obs;
  final _touchedFields = <RegistrationField>{}.obs;
  bool _closed = false;
  Worker? _areaCodeWorker;
  final loginController = Get.find<LoginLogic>();
  String? get email => loginController.operateType == LoginType.email
      ? phoneCtrl.text.trim()
      : null;
  String? get phone => (loginController.operateType == LoginType.phone ||
          loginController.operateType == LoginType.account)
      ? phoneCtrl.text.trim()
      : null;

  String? errorFor(RegistrationField field) {
    if (!_touchedFields.contains(field)) return null;
    return switch (field) {
      RegistrationField.account => _accountError(),
      RegistrationField.code => AuthFormRules.verificationCode(
          verificationCodeCtrl.text,
          sixDigits: true),
      RegistrationField.password =>
        RegisterPasswordRules.validate(pwdCtrl.text),
      RegistrationField.confirmation =>
        AuthFormRules.confirmPassword(pwdAgainCtrl.text, pwdCtrl.text),
      RegistrationField.invitation => AuthFormRules.invitationCode(
          invitationCode,
          isRequired: needInvitationCodeRegister),
      RegistrationField.nickname => null,
    };
  }

  void touchField(RegistrationField field) {
    if (_closed || isClosed) return;
    _touchedFields.add(field);
  }

  @override
  void onClose() {
    _closed = true;
    _areaCodeWorker?.dispose();
    phoneCtrl.dispose();
    verificationCodeCtrl.dispose();
    pwdCtrl.dispose();
    pwdAgainCtrl.dispose();
    invitationCodeCtrl.dispose();
    phoneFocus.dispose();
    codeFocus.dispose();
    pwdFocus.dispose();
    pwdAgainFocus.dispose();
    super.onClose();
  }

  @override
  void onInit() {
    phoneCtrl.addListener(_onChanged);
    verificationCodeCtrl.addListener(_onChanged);
    pwdCtrl.addListener(_onChanged);
    pwdAgainCtrl.addListener(_onChanged);
    invitationCodeCtrl.addListener(_onChanged);
    _areaCodeWorker = ever(areaCode, (_) => _onChanged());
    super.onInit();
  }

  void _onChanged() {
    if (_closed || isClosed) return;
    _touchedFields.refresh();
    enabled.value = _accountError() == null &&
        AuthFormRules.verificationCode(verificationCodeCtrl.text,
                sixDigits: true) ==
            null &&
        RegisterPasswordRules.valid(pwdCtrl.text) &&
        pwdAgainCtrl.text == pwdCtrl.text &&
        AuthFormRules.invitationCode(invitationCode,
                isRequired: needInvitationCodeRegister) ==
            null;
  }

  bool get needInvitationCodeRegister =>
      /*null != appLogic.clientConfigMap['needInvitationCodeRegister'] && appLogic.clientConfigMap['needInvitationCodeRegister'] != '0'*/ false;

  String? get invitationCode =>
      IMUtils.emptyStrToNull(invitationCodeCtrl.text.trim());

  void openCountryCodePicker() async {
    String? code = await IMViews.showCountryCodePicker();
    if (!_closed && !isClosed && code != null) areaCode.value = code;
  }

  Future<bool> requestVerificationCode() async {
    if (_closed || isClosed || submitting.value || !_checkingInput()) {
      return false;
    }
    submitting.value = true;
    try {
      return await requestAccountVerificationCode(
        areaCode: areaCode.value,
        phoneNumber: phone,
        email: email,
        usedFor: 1,
        invitationCode: invitationCode,
      );
    } finally {
      if (!_closed && !isClosed) submitting.value = false;
    }
  }

  String? _accountError() => loginController.operateType == LoginType.email
      ? AuthFormRules.email(email)
      : AuthFormRules.phone(phone, areaCode.value);

  bool _checkingInput({bool includeCredentials = false}) {
    _touchedFields.addAll([
      RegistrationField.account,
      RegistrationField.invitation,
      if (includeCredentials) ...[
        RegistrationField.code,
        RegistrationField.password,
        RegistrationField.confirmation,
      ],
    ]);
    final error = _accountError() ??
        AuthFormRules.invitationCode(invitationCode,
            isRequired: needInvitationCodeRegister) ??
        (includeCredentials
            ? AuthFormRules.verificationCode(verificationCodeCtrl.text,
                    sixDigits: true) ??
                RegisterPasswordRules.validate(pwdCtrl.text) ??
                AuthFormRules.confirmPassword(pwdAgainCtrl.text, pwdCtrl.text)
            : null);
    return error == null;
  }

  Future<void> next() async {
    if (_closed || isClosed || submitting.value) return;
    if (!_checkingInput(includeCredentials: true)) return;
    final requestedAreaCode = areaCode.value;
    final requestedPhone = phone;
    final requestedEmail = email;
    final requestedInvitation = invitationCode;
    final requestedCode = verificationCodeCtrl.text.trim();
    final requestedPassword = pwdCtrl.text;
    final session = RegistrationSession(
      imLogic: Get.find<IMController>(),
      isActive: () => !_closed && !isClosed,
    );
    submitting.value = true;
    try {
      await verifyCredentials(
        areaCode: requestedAreaCode,
        phoneNumber: requestedPhone,
        email: requestedEmail,
        verificationCode: requestedCode,
        invitationCode: requestedInvitation,
      );
      if (!session.isCurrent) return;
      AppNavigator.startSetPassword(
        profileDraft: profileDraft,
        areaCode: requestedAreaCode,
        phoneNumber: requestedPhone,
        email: requestedEmail,
        usedFor: 1,
        verificationCode: requestedCode,
        invitationCode: requestedInvitation,
        password: requestedPassword,
      );
    } catch (error) {
      if (session.isCurrent) {
        IMViews.showToast(
            HttpUtil.errorMessage(error, path: Urls.checkVerificationCode));
      }
    } finally {
      if (!_closed && !isClosed) submitting.value = false;
    }
  }

  Future<void> verifyCredentials({
    required String areaCode,
    String? phoneNumber,
    String? email,
    required String verificationCode,
    String? invitationCode,
  }) async {
    await Apis.checkVerificationCode(
      areaCode: areaCode,
      phoneNumber: phoneNumber,
      email: email,
      verificationCode: verificationCode,
      invitationCode: invitationCode,
      usedFor: 1,
      showErrorToast: false,
    );
  }
}
