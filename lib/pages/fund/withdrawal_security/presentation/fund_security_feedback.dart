import 'package:openim_common/localization.dart';
import 'package:openim/routes/swipe_back/app_page_route.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../core/controller/im_controller.dart';
import '../../../../services/fund_api.dart';
import '../../../home/home_logic.dart';
import '../../../mine/settings/openim_profile_service.dart';
import '../../../mine/settings/pages/change_phone_page.dart';

String fundSecurityErrorMessage(Object error) {
  if (error is FundApiException) {
    return switch (error.code) {
      20076 => AppCopy.text('手机号或密码变更后需等待2小时，请重新检查允许转出时间'),
      20077 => AppCopy.text('本次交易需要短信验证，请获取验证码后再试'),
      20078 => AppCopy.text('本次验证码错误或已失效，请重新获取验证码'),
      20079 => AppCopy.text('当前登录设备无法确认，请重新登录后再试'),
      20080 => AppCopy.text('短信发送过于频繁，请稍后再试'),
      20038 => AppCopy.text('请先绑定手机号，再进行本次交易短信验证'),
      _ => AppCopy.format('安全验证失败，请稍后重试（错误码：{#0}）', [error.code]),
    };
  }
  return AppCopy.text('安全验证信息获取失败，请稍后重试');
}

enum _Recovery { bindPhone, signIn }

Future<void> showFundSecurityFailure(BuildContext context, Object error,
    {required bool Function() isCurrent}) async {
  if (!context.mounted || !isCurrent()) return;
  final code = error is FundApiException ? error.code : null;
  final recovery = await showAppAlert<_Recovery?>(
    context,
    barrierDismissible: true,
    title: AppCopy.text('交易安全验证'),
    message: fundSecurityErrorMessage(error),
    actions: [
      const AppAction('知道了', null),
      if (code == 20038 && Get.isRegistered<IMController>())
        AppAction(AppCopy.text('绑定手机号'), _Recovery.bindPhone),
      if (code == 20079 && Get.isRegistered<HomeLogic>())
        AppAction(AppCopy.text('重新登录'), _Recovery.signIn),
    ],
  );
  if (!context.mounted || !isCurrent()) return;
  if (recovery == _Recovery.bindPhone && Get.isRegistered<IMController>()) {
    await Navigator.of(context).push<bool>(AppMaterialPageRoute(
        builder: (_) => ChangePhonePage(
            service: OpenIMProfileService(Get.find<IMController>()))));
  } else if (recovery == _Recovery.signIn && Get.isRegistered<HomeLogic>()) {
    await Get.find<HomeLogic>().endSession();
  }
}

String fundSecurityAllowedTime(int milliseconds) {
  final time = DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true)
      .add(const Duration(hours: 8));
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}:${two(time.second)}（UTC+8）';
}
