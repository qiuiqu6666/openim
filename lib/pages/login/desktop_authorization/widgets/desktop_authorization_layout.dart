import 'package:openim_common/localization.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Measurements and original artwork from reference-99chat's desktop layouts.
class DesktopAuthorizationLayout extends StatelessWidget {
  const DesktopAuthorizationLayout(
      {super.key,
      required this.title,
      required this.onClose,
      this.detail,
      this.action,
      this.onAction,
      this.loading = false,
      this.busy = false,
      this.loggedIn = false});
  final String title;
  final Widget? detail;
  final String? action;
  final VoidCallback onClose;
  final VoidCallback? onAction;
  final bool loading, busy, loggedIn;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppTokens.background(dark: dark),
      body: SafeArea(
          child: Column(children: [
        Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
                tooltip: AppCopy.text('关闭'),
                onPressed: busy ? null : onClose,
                icon: const Icon(Icons.close, size: 26),
                color: AppTokens.accent)),
        Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    child: Column(children: [
                    SizedBox(height: loggedIn ? 36 : 56),
                    Image.asset(
                        'lib/pages/login/desktop_authorization/assets/${loggedIn ? 'jingyin' : 'diann'}.png',
                        width: loggedIn ? 280 : 260,
                        excludeFromSemantics: true),
                    SizedBox(height: loggedIn ? 24 : 28),
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: loggedIn ? 18 : 24,
                                fontWeight: loggedIn
                                    ? FontWeight.w600
                                    : FontWeight.w700,
                                height: 1.35,
                                color: AppTokens.textPrimary(dark: dark)))),
                    if (detail != null)
                      Padding(
                          padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
                          child: detail!),
                  ]))),
        if (!loading && action != null)
          Padding(
              padding: EdgeInsets.fromLTRB(loggedIn ? 24 : 32, 8,
                  loggedIn ? 24 : 32, loggedIn ? 36 : 56),
              child: SizedBox(
                width: loggedIn ? 188 : double.infinity,
                height: 48,
                child: FilledButton(
                    onPressed: busy ? null : onAction,
                    style: FilledButton.styleFrom(
                        backgroundColor: loggedIn
                            ? const Color(0xFF7A96B8)
                            : AppTokens.accent,
                        foregroundColor: AppTokens.onAccent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(loggedIn ? 8 : 10))),
                    child: busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: AppTokens.onAccent))
                        : Text(action!,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600))),
              )),
      ])),
    );
  }
}
