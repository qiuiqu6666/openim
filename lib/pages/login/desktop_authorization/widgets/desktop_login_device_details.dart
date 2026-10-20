import 'package:openim_common/localization.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Confirmation hierarchy from the user-supplied mobile reference.
class DesktopLoginDeviceDetails extends StatelessWidget {
  const DesktopLoginDeviceDetails(
      {super.key,
      required this.deviceName,
      required this.platform,
      required this.code,
      this.region = ''});
  final String deviceName, platform, code, region;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final secondary = AppTokens.textSecondary(dark: dark);
    final label =
        deviceName.contains(platform) ? deviceName : '$deviceName · $platform';
    return Column(children: [
      Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 16,
              color: AppTokens.textPrimary(dark: dark).withValues(alpha: .8))),
      if (region.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 6),
            child:
                Text(region, style: TextStyle(fontSize: 13, color: secondary))),
      if (code.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 28, bottom: 20),
            child: Semantics(
                label: AppCopy.format('核对码 {#0}', [code]),
                excludeSemantics: true,
                child: Container(
                  constraints:
                      const BoxConstraints(minHeight: 66, maxWidth: 240),
                  width: double.infinity,
                  alignment: Alignment.center,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                      color:
                          AppTokens.accent.withValues(alpha: dark ? .12 : .035),
                      borderRadius: BorderRadius.circular(14)),
                  child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(code,
                          style: const TextStyle(
                              fontSize: 40,
                              letterSpacing: 4,
                              fontWeight: FontWeight.w600,
                              color: AppTokens.accent))),
                ))),
      const SizedBox(height: 2),
      Text(AppCopy.text('请核对电脑上的数字，仅登录你本人正在使用的设备'),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 16,
              color: AppTokens.textPrimary(dark: dark).withValues(alpha: .8))),
    ]);
  }
}
