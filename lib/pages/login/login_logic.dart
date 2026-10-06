import 'package:openim/pages/mine/settings/widgets/account_code_request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/controller/im_controller.dart';
import '../../core/session/sdk_session_queue.dart';
import '../../routes/app_navigator.dart';
import '../../services/auth_credentials/auth_credentials_store.dart';
import '../../widgets/auth/auth_form_rules.dart';
import '../../widgets/auth/auth_copy.dart';
import 'device_verification/data/password_device_login_attempt.dart';
import 'device_verification/device_verification_flow.dart';
import 'validation/login_form_feedback.dart';

enum LoginType {
  phone(0),
  email(1),
  account(2);

  final int rawValue;

  const LoginType(this.rawValue);

  static LoginType fromRawValue(int rawValue) {
    return values.firstWhere((e) => e.rawValue == rawValue);
  }
}

extension LoginTypeExt on LoginType {
  String get name {
    switch (this) {
      case LoginType.phone:
        return StrRes.phoneNumber;
      case LoginType.email:
        return StrRes.email;
      case LoginType.account:
        return StrRes.account;
    }
  }

  String get hintText {
    switch (this) {
      case LoginType.phone:
        return StrRes.plsEnterPhoneNumber;
      case LoginType.email:
        return StrRes.plsEnterEmail;
      case LoginType.account:
        return StrRes.plsEnterAccount;
    }
  }

  String get exclusiveName {
    switch (this) {
      case LoginType.phone:
        return StrRes.email;
      case LoginType.email:
        return StrRes.phoneNumber;
      case LoginType.account:
        return StrRes.account;
    }
  }
}

class LoginLogic extends GetxController with GetTickerProviderStateMixin {
  LoginLogic({
    AuthCredentialsStore? credentialsStore,
    DeviceCaptchaPresenter? deviceCaptchaPresenter,
  })  : _credentialsStore = credentialsStore ?? AuthCredentialsStore.instance,
        _deviceCaptchaPresenter = deviceCaptchaPresenter;

  final AuthCredentialsStore _credentialsStore;
  final DeviceCaptchaPresenter? _deviceCaptchaPresenter;
  DeviceVerificationFlow? _deviceFlow;
  final _feedback = LoginFormFeedback();
  String? get accountError =>
      _feedback.touched(LoginFormField.account) ? _accountError() : null;
  String? get passwordError =>
      isPasswordLogin.value && _feedback.touched(LoginFormField.password)
          ? AuthFormRules.loginPassword(pwdCtrl.text)
          : null;
  String? get codeError =>
      !isPasswordLogin.value && _feedback.touched(LoginFormField.code)
          ? AuthFormRules.verificationCode(verificationCodeCtrl.text,
              sixDigits: true)
          : null;
  String? get formError {
    final error = _feedback.failure.value;
    if (error == null) return null;
    return error is SdkSessionBusy
        ? authText('上一登录会话仍在清理，请稍后重试',
            'The previous session is still closing. Please try again shortly.')
        : HttpUtil.errorMessage(error,
            path: _feedback.failurePath ?? Urls.login);
  }

  final imLogic = Get.find<IMController>();
  final phoneCtrl = TextEditingController();
  final pwdCtrl = TextEditingController();
  final verificationCodeCtrl = TextEditingController();
  final obscureText = true.obs;
  final enabled = false.obs;
  final submitting = false.obs;
  final areaCode = "+86".obs;
  final isPasswordLogin = true.obs;
  final rememberPassword = true.obs;
  final versionInfo = ''.obs;
  final displayVersion = '3.8.3'.obs;
  final loginType = LoginType.phone.obs;
  String? get email =>
      loginType.value == LoginType.email ? phoneCtrl.text.trim() : null;
  String? get phone =>
      loginType.value == LoginType.phone ? phoneCtrl.text.trim() : null;
  String? get account => loginType.value == LoginType.account
      ? phoneCtrl.text.trim().replaceFirst(RegExp(r'^@+'), '').trim()
      : null;
  LoginType operateType = LoginType.phone;
  bool _loggingIn = false;
  bool _closed = false;
  int _loginAttempt = 0;
  int _inputRevision = 0;
  int _rememberRevision = 0;
  bool _restoringCredentials = false;
  (String, String, String, String, bool) _lastInput = ('', '', '', '+86', true);

  bool _activeLogin(int attempt) =>
      !_closed && !isClosed && attempt == _loginAttempt;

  FocusNode? accountFocus = FocusNode();
  FocusNode? pwdFocus = FocusNode();

  late TabController tabController;

  Future<void> _initData() async {
    _restoringCredentials = true;
    var map = DataSp.getLoginAccount();
    if (map is Map) {
      String? phoneNumber = map["phoneNumber"];
      String? areaCode = map["areaCode"];

      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        phoneCtrl.text = phoneNumber;
      }
      if (areaCode != null && areaCode.isNotEmpty) {
        this.areaCode.value = areaCode;
      }
    }

    updatePasswordAccountType();
    _restoringCredentials = false;
    final inputRevision = _inputRevision;
    final rememberRevision = _rememberRevision;
    try {
      final credentials = await _credentialsStore.load();
      if (_closed || isClosed) return;
      if (_rememberRevision == rememberRevision) {
        rememberPassword.value = credentials.rememberPassword;
      }
      if (_inputRevision != inputRevision) return;
      _restoringCredentials = true;
      if (credentials.account.isNotEmpty) {
        areaCode.value = credentials.areaCode;
        // Preserve the user-ID meaning of an otherwise phone/email-shaped ID.
        final markedAccount =
            credentials.loginType == LoginType.account.rawValue &&
                (credentials.account.contains('@') ||
                    AuthFormRules.phone(
                            credentials.account, credentials.areaCode) ==
                        null);
        phoneCtrl.text =
            markedAccount ? '@${credentials.account}' : credentials.account;
        if (rememberPassword.value && credentials.password != null) {
          pwdCtrl.text = credentials.password!;
        }
      }
      _onChanged();
    } catch (_) {
      Logger.print('Remembered credentials could not be loaded');
    } finally {
      _restoringCredentials = false;
    }
  }

  @override
  void onClose() {
    _closed = true;
    ++_loginAttempt;
    _deviceFlow?.cancel();
    _deviceFlow = null;
    phoneCtrl.dispose();
    pwdCtrl.dispose();
    verificationCodeCtrl.dispose();
    tabController.dispose();
    accountFocus?.dispose();
    pwdFocus?.dispose();
    super.onClose();
  }

  @override
  void onInit() {
    tabController = TabController(length: 3, vsync: this);
    phoneCtrl.addListener(_onChanged);
    pwdCtrl.addListener(_onChanged);
    verificationCodeCtrl.addListener(_onChanged);
    _initData();
    super.onInit();
  }

  @override
  void onReady() {
    super.onReady();
    getPackageInfo();
  }

  void _onChanged() {
    if (_closed || isClosed) return;
    // Controllers also notify for selection and IME composing changes. These
    // must not cancel an in-flight restore of the same account's password.
    final input = (
      phoneCtrl.text,
      pwdCtrl.text,
      verificationCodeCtrl.text,
      areaCode.value,
      isPasswordLogin.value,
    );
    final edited = !_restoringCredentials && input != _lastInput;
    _lastInput = input;
    if (edited) {
      ++_inputRevision;
      _deviceFlow?.cancel();
    }
    updatePasswordAccountType();
    enabled.value = phoneCtrl.text.trim().isNotEmpty &&
        (isPasswordLogin.value
            ? pwdCtrl.text.trim().isNotEmpty
            : verificationCodeCtrl.text.trim().isNotEmpty);
    _refreshFeedback(edited: edited);
  }

  void _refreshFeedback({bool edited = false}) =>
      _feedback.refresh(edited: edited);

  void accountFocusChanged(bool hasFocus) =>
      _fieldFocusChanged(LoginFormField.account, hasFocus);

  void passwordFocusChanged(bool hasFocus) =>
      _fieldFocusChanged(LoginFormField.password, hasFocus);

  void codeFocusChanged(bool hasFocus) =>
      _fieldFocusChanged(LoginFormField.code, hasFocus);

  void _fieldFocusChanged(LoginFormField field, bool hasFocus) {
    if (_closed || isClosed) return;
    _feedback.focusChanged(field, hasFocus);
  }

  void updatePasswordAccountType() {
    if (_closed || isClosed) return;
    final value = phoneCtrl.text.trim();
    final type = !isPasswordLogin.value
        ? LoginType.phone
        : value.startsWith('@')
            ? LoginType.account
            : value.contains('@')
                ? LoginType.email
                : RegExp(r'^\d+$').hasMatch(value) &&
                        AuthFormRules.phone(value, areaCode.value) == null
                    ? LoginType.phone
                    : LoginType.account;
    loginType.value = type;
    operateType = type;
    tabController.index = type.rawValue;
  }

  Future<void> toggleRememberPassword(bool remember) async {
    if (_closed || isClosed) return;
    ++_rememberRevision;
    rememberPassword.value = remember;
    try {
      await _credentialsStore.setRememberPassword(remember);
    } catch (_) {
      Logger.print('Remember-password preference could not be saved');
    }
  }

  Future<void> login() async {
    if (_closed || isClosed || _loggingIn || !_checkingInput()) return;
    _loggingIn = true;
    submitting.value = true;
    final attempt = ++_loginAttempt;
    DataSp.putLoginType(loginType.value.rawValue);
    try {
      if (!_activeLogin(attempt)) return;
      final success = await _login(attempt);
      if (success && _activeLogin(attempt)) {
        Get.find<CacheController>().resetCache();
        AppNavigator.startMain();
      }
    } finally {
      _loggingIn = false;
      if (!_closed && !isClosed) submitting.value = false;
    }
  }

  String? _accountError() => switch (loginType.value) {
        LoginType.phone => AuthFormRules.phone(phone, areaCode.value),
        LoginType.email => AuthFormRules.email(email),
        LoginType.account => AuthFormRules.account(account),
      };

  bool _checkingInput({bool accountOnly = false}) {
    updatePasswordAccountType();
    return _feedback.validate(
      account: _accountError(),
      password: AuthFormRules.loginPassword(pwdCtrl.text),
      code: AuthFormRules.verificationCode(verificationCodeCtrl.text,
          sixDigits: true),
      passwordLogin: isPasswordLogin.value,
      accountOnly: accountOnly,
    );
  }

  Future<bool> _login(int attempt) async {
    PasswordDeviceLoginAttempt? passwordAttempt;
    var deviceVerified = false;
    var ownerAccount = DataSp.userID;
    var ownerToken = DataSp.chatToken;
    var ownerIMToken = DataSp.imToken;
    final requestInputRevision = _inputRevision;
    bool ownsRequest() =>
        _activeLogin(attempt) &&
        requestInputRevision == _inputRevision &&
        ownerAccount == DataSp.userID &&
        ownerToken == DataSp.chatToken &&
        ownerIMToken == DataSp.imToken;
    bool ownsFeedback() =>
        ownsRequest() && requestInputRevision == _inputRevision;
    try {
      if (!_checkingInput()) return false;
      final password = IMUtils.emptyStrToNull(pwdCtrl.text);
      final code = IMUtils.emptyStrToNull(verificationCodeCtrl.text);
      final passwordLogin = isPasswordLogin.value;
      final requestedAccount =
          account ?? email ?? phone ?? phoneCtrl.text.trim();
      final requestedAreaCode = areaCode.value;
      final requestedType = loginType.value;
      final loginAccount = {
        'areaCode': areaCode.value,
        'phoneNumber': phoneCtrl.text,
        'loginType': loginType.value.rawValue,
      };
      LoginCertificate? data;
      if (passwordLogin) {
        passwordAttempt = await PasswordDeviceLoginAttempt.prepare(
          areaCode: requestedAreaCode,
          phoneNumber: phone,
          account: account,
          email: email,
          password: password!,
        );
        if (!ownsRequest()) return false;
        try {
          data = await passwordAttempt.submit(isCurrent: ownsRequest);
        } catch (error) {
          if (deviceLoginErrorCode(error) != 20081) rethrow;
          if (!ownsFeedback()) return false;
          final context = Get.context;
          if (context == null || !context.mounted) return false;
          final flow = DeviceVerificationFlow(
            attempt: passwordAttempt,
            phoneNumber:
                requestedType == LoginType.phone ? requestedAccount : '',
            areaCode: requestedAreaCode,
            isCurrent: ownsFeedback,
            captchaPresenter: _deviceCaptchaPresenter,
          );
          _deviceFlow = flow;
          try {
            data = await flow.run(context);
          } finally {
            if (identical(_deviceFlow, flow)) _deviceFlow = null;
          }
          if (data == null || !ownsFeedback()) return false;
          deviceVerified = true;
        }
      } else {
        data = await Apis.login(
          isCurrent: ownsRequest,
          showErrorToast: false,
          areaCode: requestedAreaCode,
          phoneNumber: phone,
          account: account,
          email: email,
          verificationCode: code,
        );
      }
      if (!ownsRequest()) return false;
      ownerAccount = data.userID;
      ownerToken = data.chatToken;
      ownerIMToken = data.imToken;
      await DataSp.putLoginCertificate(data);
      if (!ownsRequest()) return false;
      await DataSp.putLoginAccount(loginAccount);
      if (!ownsRequest()) return false;
      Logger.print('Login credentials received');
      await imLogic.login(data.userID, data.imToken);
      if (!ownsRequest() ||
          DataSp.userID != data.userID ||
          DataSp.imToken != data.imToken) {
        return false;
      }
      Logger.print('im login success');
      final authenticated = data;
      PushController.login(
        authenticated.userID,
        onTokenRefresh: (token) {
          if (OpenIM.iMManager.userID != authenticated.userID ||
              DataSp.imToken != authenticated.imToken) {
            return;
          }
          OpenIM.iMManager.updateFcmToken(
              fcmToken: token,
              expireTime: DateTime.now()
                  .add(Duration(days: 90))
                  .millisecondsSinceEpoch);
        },
      );
      Logger.print('push login success');
      try {
        await _credentialsStore.saveSuccessful(
          account: requestedAccount,
          areaCode: requestedAreaCode,
          loginType: requestedType.rawValue,
          password: passwordLogin && !deviceVerified ? password : null,
          rememberPassword: !deviceVerified && rememberPassword.value,
          isCurrent: ownsRequest,
        );
      } catch (_) {
        Logger.print('Remembered credentials could not be saved');
      }
      if (!ownsRequest()) return false;
      if (deviceVerified) {
        pwdCtrl.clear();
        verificationCodeCtrl.clear();
      }
      return true;
    } catch (e) {
      Logger.print('Login failed');
      if (ownsFeedback()) {
        _feedback.recordFailure(e, Urls.login);
      }
    } finally {
      passwordAttempt?.close();
    }
    return false;
  }

  void togglePasswordType() {
    if (_closed || isClosed) return;
    _feedback.reset();
    isPasswordLogin.value = !isPasswordLogin.value;
    _onChanged();
  }

  void selectLoginType(LoginType type) {
    if (_closed || isClosed) return;
    _feedback.reset();
    loginType.value = type;
    operateType = type;
    tabController.index = type.rawValue;
    if (type == LoginType.account) isPasswordLogin.value = true;
    phoneCtrl.clear();
    pwdCtrl.clear();
    verificationCodeCtrl.clear();
    _onChanged();
  }

  void toggleLoginType() {
    selectLoginType(
        loginType.value == LoginType.phone ? LoginType.email : LoginType.phone);
  }

  Future<bool> getVerificationCode() async {
    if (_closed || isClosed) return false;
    final error = AuthFormRules.phone(phoneCtrl.text, areaCode.value);
    if (!_feedback.validate(
      account: error,
      password: AuthFormRules.loginPassword(pwdCtrl.text),
      code: AuthFormRules.verificationCode(verificationCodeCtrl.text,
          sixDigits: true),
      passwordLogin: isPasswordLogin.value,
      accountOnly: true,
    )) {
      return false;
    }
    final revision = _inputRevision;
    try {
      return await sendVerificationCode();
    } catch (error) {
      if (!_closed && !isClosed && revision == _inputRevision) {
        _feedback.recordFailure(error, Urls.getVerificationCode);
      }
      return false;
    }
  }

  Future<bool> sendVerificationCode() => requestAccountVerificationCode(
        areaCode: areaCode.value,
        phoneNumber: phoneCtrl.text.trim(),
        usedFor: 3,
      );

  void openCountryCodePicker() async {
    String? code = await IMViews.showCountryCodePicker();
    if (!_closed && !isClosed && code != null) {
      areaCode.value = code;
      _onChanged();
    }
  }

  void registerNow() {
    operateType = LoginType.phone;
    AppNavigator.startRegister();
  }

  void forgetPassword() {
    operateType = LoginType.phone;
    AppNavigator.startForgetPassword();
  }

  void getPackageInfo() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    if (_closed) return;
    final version = packageInfo.version;
    final appName = packageInfo.appName;
    final buildNumber = packageInfo.buildNumber;
    displayVersion.value = version;

    versionInfo.value = '$appName $version+$buildNumber SDK: ${OpenIM.version}';
  }
}
