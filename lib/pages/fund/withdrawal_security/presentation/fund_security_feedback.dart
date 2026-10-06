import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/controller/im_controller.dart';
import '../../../../services/fund_api.dart';
import '../../../home/home_logic.dart';
import '../../../mine/settings/openim_profile_service.dart';
import '../../../mine/settings/pages/change_phone_page.dart';
import '../../widgets/fund_page_colors.dart';

String fundSecurityErrorMessage(Object error) {
  if (error is FundApiException) {
    return switch (error.code) {
      20076 => '手机号或密码变更后需等待24小时，请重新检查允许转出时间',
      20077 => '本次交易需要短信验证，请获取验证码后再试',
      20078 => '本次验证码错误或已失效，请重新获取验证码',
      20079 => '当前登录设备无法确认，请重新登录后再试',
      20080 => '短信发送过于频繁，请稍后再试',
      20038 => '请先绑定手机号，再进行本次交易短信验证',
      _ => '安全验证失败，请稍后重试（错误码：${error.code}）',
    };
  }
  return '安全验证信息获取失败，请稍后重试';
}

enum _Recovery { bindPhone, signIn }

Future<void> showFundSecurityFailure(BuildContext context, Object error,
    {required bool Function() isCurrent}) async {
  if (!context.mounted || !isCurrent()) return;
  final code = error is FundApiException ? error.code : null;
  final colors = FundPageColors.of(context);
  final recovery = await showDialog<_Recovery>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: colors.card,
      title: Text('交易安全验证', style: TextStyle(color: colors.text)),
      content: Text(fundSecurityErrorMessage(error),
          style: TextStyle(color: colors.text)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('知道了'),
        ),
        if (code == 20038 && Get.isRegistered<IMController>())
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_Recovery.bindPhone),
            child: const Text('绑定手机号'),
          ),
        if (code == 20079 && Get.isRegistered<HomeLogic>())
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(_Recovery.signIn),
            child: const Text('重新登录'),
          ),
      ],
    ),
  );
  if (!context.mounted || !isCurrent()) return;
  if (recovery == _Recovery.bindPhone && Get.isRegistered<IMController>()) {
    await Navigator.of(context).push<bool>(MaterialPageRoute(
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
