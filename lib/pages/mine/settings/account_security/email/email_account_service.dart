import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../../../../../core/controller/im_controller.dart';
import '../../../../../services/auth_credentials/auth_credentials_store.dart';
import '../../verification_code_result.dart';

abstract class EmailAccountService {
  Future<String> load();
  Future<VerificationCodeResult> send(
      String email, String purpose, String captcha);
  Future<void> save({
    required bool changing,
    required String email,
    required String code,
    required String oldCode,
    required String password,
  });
  bool get isCurrent;
}

class OpenIMEmailAccountService implements EmailAccountService {
  OpenIMEmailAccountService()
      : _user = OpenIM.iMManager.userID,
        _token = DataSp.chatToken;
  final String _user;
  final String? _token;
  String _loadedEmail = '';

  @override
  bool get isCurrent =>
      _user.isNotEmpty &&
      _token?.isNotEmpty == true &&
      OpenIM.iMManager.userID == _user &&
      DataSp.chatToken == _token;

  void _check() {
    if (!isCurrent) throw StateError('Account session changed');
  }

  @override
  Future<String> load() async {
    _check();
    final info = await Apis.queryMyFullInfo();
    _check();
    if (info == null) throw StateError('Account information unavailable');
    return _loadedEmail = info.email ?? '';
  }

  Future<dynamic> _post(String route, Map<String, dynamic> body) async {
    _check();
    final result = await HttpUtil.post(
        '${Config.appAuthUrl}/account/email/$route',
        data: body,
        options: Apis.chatTokenOptions,
        showErrorToast: false);
    _check();
    return result;
  }

  @override
  Future<VerificationCodeResult> send(
          String email, String purpose, String captcha) async =>
      VerificationCodeResult.fromJson(await _post('code/send', {
        'email': email.trim().toLowerCase(),
        'purpose': purpose,
        'captchaVerifyParam': captcha,
      }));

  @override
  Future<void> save({
    required bool changing,
    required String email,
    required String code,
    required String oldCode,
    required String password,
  }) async {
    final normalized = email.trim().toLowerCase();
    await _post(changing ? 'change' : 'bind', {
      'email': normalized,
      'verifyCode': code.trim(),
      if (changing) 'oldVerifyCode': oldCode.trim(),
      if (!changing) ...{
        'password': IMUtils.generateMD5(password),
      },
    });
    if (Get.isRegistered<IMController>()) {
      Get.find<IMController>()
          .userInfo
          .update((info) => info?.email = normalized);
    }
    try {
      await AuthCredentialsStore.instance.renameEmail(
          previousEmail: _loadedEmail,
          email: normalized,
          isCurrent: () => isCurrent);
      if (isCurrent) {
        final previous = DataSp.getLoginAccount();
        if (previous is Map &&
            ((previous['email'] ?? previous['phoneNumber']) as String?)
                    ?.toLowerCase() ==
                _loadedEmail.toLowerCase() &&
            _loadedEmail.isNotEmpty) {
          await DataSp.putLoginAccount({
            ...Map<String, dynamic>.from(previous),
            'email': normalized,
            'phoneNumber': normalized,
            'loginType': 1,
          });
        }
      }
    } catch (error) {
      // The server commit remains successful if local secure storage is unavailable.
      Logger.print('Email credential refresh failed: ${error.runtimeType}');
    }
    _loadedEmail = normalized;
  }
}
