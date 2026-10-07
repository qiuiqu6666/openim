import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/controller/im_controller.dart';
import '../../mine/settings/openim_profile_service.dart';
import '../../mine/settings/pages/trade_password_page.dart';
import '../../mine/settings/settings_service.dart';
import '../host/wallet_navigation.dart';
import '../widgets/wallet_tip.dart';

SettingsService _walletSettings(SettingsService? service) {
  if (service != null) return service;
  if (!Get.isRegistered<IMController>()) {
    throw StateError('登录状态已失效，请重新登录');
  }
  return OpenIMProfileService(Get.find<IMController>());
}

Future<void> openWalletPaymentPassword(BuildContext context,
    {SettingsService? service}) async {
  try {
    final settings = _walletSettings(service);
    await openWalletPage<void>(
      context,
      TradePasswordPage(service: settings),
      activityPage: 'pay_password',
    );
  } catch (_) {
    if (context.mounted) WalletTip.show(context, '无法打开支付密码设置，请重新登录后重试');
  }
}

/// Setting a PIN is a separate flow. Re-read its status after returning and
/// check route/account ownership before any draft or payment is created.
Future<bool> ensureWalletPaymentPassword(BuildContext context,
    {SettingsService? service, required bool Function() isActive}) async {
  if (!isActive()) return false;
  final settings = _walletSettings(service);
  var hasPassword = await settings.hasTradePassword();
  if (!context.mounted || !isActive()) return false;
  if (!hasPassword) {
    WalletTip.show(context, '请先设置支付密码');
    await openWalletPaymentPassword(context, service: settings);
    if (!context.mounted || !isActive()) return false;
    hasPassword = await settings.hasTradePassword();
  }
  return context.mounted && isActive() && hasPassword;
}
