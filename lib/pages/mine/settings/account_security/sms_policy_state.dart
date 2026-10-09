import 'package:flutter/material.dart';

import '../settings_service.dart';
import '../widgets/settings_widgets.dart';

/// Each sensitive form loads current server policy. A stale profile or failed
/// read never grants exemption; the server checks again when applying changes.
mixin SmsPolicyState<T extends StatefulWidget> on State<T> {
  SettingsService get securityService;

  bool _policyLoading = true;
  bool _policyReady = false;
  bool _smsExempt = false;
  int _policyRequest = 0;

  bool get smsPolicyReady => _policyReady && !_policyLoading;
  bool get smsExempt => _policyReady && _smsExempt;

  @override
  void initState() {
    super.initState();
    refreshSmsPolicy();
  }

  Future<bool> refreshSmsPolicy() async {
    final request = ++_policyRequest;
    setState(() => _policyLoading = true);
    try {
      await securityService.refreshSecurity();
      if (!mounted || request != _policyRequest) return false;
      setState(() {
        _smsExempt = securityService.securitySmsExempt;
        _policyReady = true;
        _policyLoading = false;
      });
      return true;
    } catch (_) {
      if (!mounted || request != _policyRequest) return false;
      setState(() {
        _smsExempt = false;
        _policyReady = false;
        _policyLoading = false;
      });
      return false;
    }
  }

  Widget smsPolicyNotice(BuildContext context) {
    if (_policyLoading) return const LinearProgressIndicator();
    if (_policyReady) return const SizedBox.shrink();
    return TextButton(
      onPressed: refreshSmsPolicy,
      child: Text(settingsText(context,
          zh: '安全设置加载失败，点击重试',
          en: 'Could not load security settings. Tap to retry.')),
    );
  }
}
