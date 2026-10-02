import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../widgets/settings_widgets.dart';

/// 99chat signed-in devices page with the backend intentionally left empty.
/// No fake device data is created; the page renders 99chat's real empty state.
class LoginDevicesPage extends StatelessWidget {
  const LoginDevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final background = AppTokens.background(dark: dark);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: AppTokens.accent,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          settingsText(context, zh: '登录设备', en: 'Signed-in Devices'),
          style: TextStyle(
            color: AppTokens.textPrimary(dark: dark),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SettingsEmptyState(
                icon: Icons.devices_other_rounded,
                title: settingsText(
                  context,
                  zh: '暂无登录设备',
                  en: 'No signed-in devices',
                ),
                imageWidth: 160,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
