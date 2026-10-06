import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../core/controller/im_controller.dart';
import '../../../routes/app_navigator.dart';
import '../../../widgets/auth/auth_form_rules.dart';
import '../../../widgets/auth/auth_copy.dart';
import '../profile/registration_avatar_service.dart';
import '../profile/registration_profile_draft.dart';
import '../rules/register_nickname_rules.dart';
import '../rules/register_password_rules.dart';
import '../rules/registration_field.dart';
import '../session/registration_session.dart';

typedef _RegistrationInput = ({
  String nickname,
  String password,
  String areaCode,
  String? phoneNumber,
  String? email,
  String verificationCode,
  String? invitationCode,
});

class SetPasswordLogic extends GetxController {
  SetPasswordLogic({RegistrationAvatarService? avatarService})
      : _avatarService = avatarService ?? const RegistrationAvatarService();

  final RegistrationAvatarService _avatarService;
  final imLogic = Get.find<IMController>();
  final nicknameCtrl = TextEditingController();
  final nicknameFocus = FocusNode();
  final pwdCtrl = TextEditingController();
  final pwdAgainCtrl = TextEditingController();
  final enabled = false.obs;
  final submitting = false.obs;
  final pickingAvatar = false.obs;
  final avatar = Rxn<RegistrationAvatar>();
  final avatarUploadFailed = false.obs;
  final accountCreated = false.obs;
  final nicknameError = RxnString();
  final _touchedFields = <RegistrationField>{}.obs;
  late final bool credentialPasswordProvided;
  String? phoneNumber;
  String? email;
  late String areaCode;
  late int usedFor;
  late String verificationCode;
  String? invitationCode;
  bool _registering = false;
  bool _registered = false;
  bool _closed = false;
  bool _sdkReady = false;
  _RegistrationInput? _submitted;
  LoginCertificate? _certificate;
  RegistrationSession? _session;
  RegistrationProfileDraft? _profileDraft;

  String get submitLabel => avatarUploadFailed.value
      ? authText('重试上传头像', 'Retry avatar upload')
      : accountCreated.value
          ? authText('继续完成注册', 'Continue registration')
          : authText('完成注册', 'Complete registration');

  String? _nicknameValidation() =>
      RegisterNicknameRules.validate(nicknameCtrl.text);

  String? errorFor(RegistrationField field) {
    if (!_touchedFields.contains(field)) return null;
    return switch (field) {
      RegistrationField.nickname => _nicknameValidation(),
      RegistrationField.password =>
        RegisterPasswordRules.validate(pwdCtrl.text),
      RegistrationField.confirmation =>
        AuthFormRules.confirmPassword(pwdAgainCtrl.text, pwdCtrl.text),
      _ => null,
    };
  }

  void touchField(RegistrationField field) {
    if (_closed || isClosed) return;
    _touchedFields.add(field);
    nicknameError.value = errorFor(RegistrationField.nickname);
  }

  @override
  void onClose() {
    _closed = true;
    nicknameCtrl.dispose();
    nicknameFocus.dispose();
    pwdCtrl.dispose();
    pwdAgainCtrl.dispose();
    super.onClose();
  }

  @override
  void onInit() {
    phoneNumber = Get.arguments['phoneNumber'];
    email = Get.arguments['email'];
    areaCode = Get.arguments['areaCode'];
    usedFor = Get.arguments['usedFor'];
    verificationCode = Get.arguments['verificationCode'];
    invitationCode = Get.arguments['invitationCode'];
    _profileDraft = Get.arguments['profileDraft'];
    nicknameCtrl.text = _profileDraft?.nickname ?? '';
    avatar.value = _profileDraft?.avatar;
    final password = Get.arguments['password'];
    credentialPasswordProvided = password is String && password.isNotEmpty;
    if (password is String) {
      pwdCtrl.text = password;
      pwdAgainCtrl.text = password;
    }
    nicknameCtrl.addListener(_onChanged);
    pwdCtrl.addListener(_onChanged);
    pwdAgainCtrl.addListener(_onChanged);
    _onChanged();
    super.onInit();
  }

  void _onChanged() {
    if (_closed || isClosed) return;
    final nickname = nicknameCtrl.text.trim();
    _profileDraft?.nickname = nicknameCtrl.text;
    _touchedFields.refresh();
    nicknameError.value = errorFor(RegistrationField.nickname);
    enabled.value = nickname.length >= 2 &&
        RegisterPasswordRules.valid(pwdCtrl.text) &&
        pwdAgainCtrl.text == pwdCtrl.text;
  }

  bool _checkingInput() {
    _touchedFields.addAll([
      RegistrationField.nickname,
      if (!credentialPasswordProvided) ...[
        RegistrationField.password,
        RegistrationField.confirmation,
      ],
    ]);
    nicknameError.value = errorFor(RegistrationField.nickname);
    final accountError = email != null
        ? AuthFormRules.email(email)
        : AuthFormRules.phone(phoneNumber, areaCode);
    final error = _nicknameValidation() ??
        accountError ??
        RegisterPasswordRules.validate(pwdCtrl.text) ??
        AuthFormRules.confirmPassword(pwdAgainCtrl.text, pwdCtrl.text) ??
        AuthFormRules.verificationCode(verificationCode, sixDigits: true);
    final hiddenFieldError = accountError ??
        AuthFormRules.verificationCode(verificationCode, sixDigits: true) ??
        (credentialPasswordProvided
            ? RegisterPasswordRules.validate(pwdCtrl.text) ??
                AuthFormRules.confirmPassword(pwdAgainCtrl.text, pwdCtrl.text)
            : null);
    if (error != null && hiddenFieldError != null) {
      IMViews.showToast(hiddenFieldError);
    }
    return error == null;
  }

  Future<void> nextStep() async {
    await register();
  }

  Future<void> register() async {
    if (_closed ||
        isClosed ||
        _registering ||
        pickingAvatar.value ||
        (!_registered && !_checkingInput())) {
      return;
    }
    final session = _registered
        ? _session!
        : RegistrationSession(
            imLogic: imLogic,
            isActive: () => !_closed && !isClosed,
          );
    if (!session.isCurrent) return;
    _session = session;
    final input = _submitted ??
        (
          nickname: nicknameCtrl.text.trim(),
          password: pwdCtrl.text,
          areaCode: areaCode,
          phoneNumber: phoneNumber,
          email: email,
          verificationCode: verificationCode,
          invitationCode: invitationCode,
        );
    final selectedAvatar = avatar.value;
    _registering = true;
    submitting.value = true;
    avatarUploadFailed.value = false;
    var failurePath = Urls.register;
    var uploadingAvatar = false;
    try {
      final loggedIn =
          await LoadingView.singleton.wrap<bool>(asyncFunction: () async {
        if (!session.isCurrent) return false;
        if (!_registered) {
          _certificate = await registerAccount(
            nickname: input.nickname,
            areaCode: input.areaCode,
            phoneNumber: input.phoneNumber,
            email: input.email,
            password: input.password,
            verificationCode: input.verificationCode,
            invitationCode: input.invitationCode,
          );
          _registered = true;
          _submitted = input;
          if (!session.isCurrent) return false;
          accountCreated.value = true;
        }
        if (!session.isCurrent) return false;
        if (!_sdkReady) {
          failurePath = Urls.login;
          if (!_hasLoginCredentials(_certificate!)) {
            final registeredUserID = _certificate!.userID;
            final certificate = await loginRegisteredAccount(
              password: input.password,
              areaCode: input.areaCode,
              phoneNumber: input.phoneNumber,
              email: input.email,
              isCurrent: () => session.isCurrent,
            );
            if (!session.isCurrent) return false;
            if (!_hasLoginCredentials(certificate) ||
                (registeredUserID.isNotEmpty &&
                    certificate.userID != registeredUserID)) {
              throw const FormatException(
                  'Invalid registration login credentials');
            }
            _certificate = certificate;
          }
          final ready = await session.finish(
            _certificate!,
            areaCode: input.areaCode,
            phoneNumber: input.phoneNumber,
            email: input.email,
          );
          if (!ready || !session.isCurrent) return false;
          _sdkReady = true;
        }
        if (selectedAvatar != null) {
          uploadingAvatar = true;
          bool ownsAvatar() =>
              session.isCurrent &&
              OpenIM.iMManager.userID == _certificate!.userID;
          final url = await _avatarService.upload(
            selectedAvatar,
            userID: _certificate!.userID,
            isCurrent: ownsAvatar,
          );
          if (!ownsAvatar()) return false;
          if (url == null) {
            throw const FormatException('Missing registration avatar URL');
          }
          imLogic.userInfo.update((user) => user?.faceURL = url);
          uploadingAvatar = false;
        }
        return session.isCurrent;
      });
      if (!session.isCurrent) return;
      if (loggedIn) {
        AppNavigator.startMain();
      }
    } catch (error) {
      if (session.isCurrent) {
        if (uploadingAvatar) {
          avatarUploadFailed.value = true;
          IMViews.showToast(authText('账号已注册，头像上传失败，请重试',
              'Account registered. Avatar upload failed. Please try again.'));
        } else {
          final message = HttpUtil.errorMessage(error, path: failurePath);
          IMViews.showToast(_registered
              ? authText('账号已注册，请重试以继续完成：$message',
                  'Account registered. Please retry to finish: $message')
              : message);
        }
      }
    } finally {
      _registering = false;
      if (!_closed && !isClosed) submitting.value = false;
    }
  }

  static bool _hasLoginCredentials(LoginCertificate certificate) =>
      certificate.userID.isNotEmpty &&
      IMUtils.emptyStrToNull(certificate.chatToken) != null &&
      IMUtils.emptyStrToNull(certificate.imToken) != null;

  Future<LoginCertificate> registerAccount({
    required String nickname,
    required String password,
    required String areaCode,
    required String verificationCode,
    String? phoneNumber,
    String? email,
    String? invitationCode,
  }) =>
      Apis.register(
        nickname: nickname,
        password: password,
        areaCode: areaCode,
        verificationCode: verificationCode,
        phoneNumber: phoneNumber,
        email: email,
        invitationCode: invitationCode,
        showErrorToast: false,
      );

  Future<LoginCertificate> loginRegisteredAccount({
    required String password,
    required String areaCode,
    required bool Function() isCurrent,
    String? phoneNumber,
    String? email,
  }) =>
      Apis.login(
        password: password,
        areaCode: areaCode,
        phoneNumber: phoneNumber,
        email: email,
        isCurrent: isCurrent,
        showErrorToast: false,
      );

  Future<void> pickAvatar() async {
    if (_closed || isClosed || submitting.value || pickingAvatar.value) return;
    final owner = (DataSp.userID, DataSp.chatToken, DataSp.imToken);
    bool ownsSelection() =>
        !_closed &&
        !isClosed &&
        (DataSp.userID, DataSp.chatToken, DataSp.imToken) == owner;
    pickingAvatar.value = true;
    try {
      final selected = await _avatarService.pick();
      if (ownsSelection() && selected != null) {
        avatar.value = selected;
        _profileDraft?.avatar = selected;
      }
    } catch (_) {
      if (ownsSelection()) {
        IMViews.showToast(
            authText('无法选择头像，请重试', 'Could not select avatar. Try again.'));
      }
    } finally {
      if (!_closed && !isClosed) pickingAvatar.value = false;
    }
  }
}
