import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../verification_code_result.dart';
import 'aliyun_captcha_dialog.dart';
import 'settings_widgets.dart';

/// A shared verification and resend lifecycle for account security pages.
class VerificationCodeFlow extends ChangeNotifier {
  VerificationCodeFlow(
      {this.verify = showAliyunCaptcha, DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final Future<VerificationCodeResult?> Function(
      BuildContext, Future<VerificationCodeResult> Function(String)) verify;
  final DateTime Function() _now;
  DateTime? _until;
  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;
  int get remaining => _until == null
      ? 0
      : math.max(0, (_until!.difference(_now()).inMilliseconds / 1000).ceil());
  bool get canSend => !_disposed && !_busy && remaining == 0;
  String label(BuildContext context) => remaining > 0
      ? settingsText(context,
          zh: '${remaining}s 后重发', en: 'Resend in ${remaining}s')
      : _busy
          ? settingsText(context, zh: '验证/发送中', en: 'Verifying/sending')
          : settingsText(context, zh: '获取验证码', en: 'Get Code');
  Future<bool> send(BuildContext context,
      Future<VerificationCodeResult> Function(String) request) async {
    if (!canSend) return false;
    _busy = true;
    notifyListeners();
    try {
      final result = await verify(context, (param) async {
        if (_disposed || !context.mounted) {
          throw StateError('Verification was cancelled');
        }
        final result = await request(param);
        if (result.sent && !_disposed && context.mounted) {
          _until = _now().add(Duration(seconds: result.retryAfter));
          _timer?.cancel();
          _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (remaining == 0) timer.cancel();
            if (!_disposed) notifyListeners();
          });
          notifyListeners();
        }
        return result;
      });
      return !_disposed && context.mounted && result?.sent == true;
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
