import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../verification_code_result.dart';
import 'aliyun_captcha_dialog.dart';

bool _sending = false;

/// Shared by login, registration and password recovery. The modal owns loading
/// and errors so an outer loading overlay cannot block the slider.
Future<bool> requestAccountVerificationCode(
    {String? areaCode,
    String? phoneNumber,
    String? email,
    required int usedFor,
    String? invitationCode}) async {
  final context = Get.context;
  if (context == null || !context.mounted || _sending) return false;
  _sending = true;
  try {
    final result = await showAliyunCaptcha(context, (param) async {
      final data = await HttpUtil.post(Urls.getVerificationCode,
          showErrorToast: false,
          data: {
            'areaCode': areaCode,
            'phoneNumber': phoneNumber,
            'email': email,
            'usedFor': usedFor,
            'invitationCode': invitationCode,
            'captchaVerifyParam': param
          });
      return VerificationCodeResult.fromJson(data);
    });
    if (result?.sent == true) IMViews.showToast(StrRes.sentSuccessfully);
    return result?.sent == true;
  } finally {
    _sending = false;
  }
}
