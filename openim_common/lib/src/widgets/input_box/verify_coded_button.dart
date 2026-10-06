import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../extension/custom_ext.dart';
import '../../res/app_tokens.dart';
import '../../res/strings.dart';
import '../../res/styles.dart';

class VerifyCodedButton extends StatefulWidget {
  final int seconds;
  final Future<bool> Function()? onTapCallback;
  final bool themed;
  final bool enabled;
  final bool autoStart;

  const VerifyCodedButton({
    super.key,
    this.seconds = 60,
    required this.onTapCallback,
    this.themed = false,
    this.enabled = true,
    this.autoStart = false,
  }) : assert(seconds >= 0);

  @override
  State<VerifyCodedButton> createState() => _VerifyCodedButtonState();
}

class _VerifyCodedButtonState extends State<VerifyCodedButton> {
  Timer? _timer;
  int _remainingSeconds = 0;
  bool _loading = false;
  bool _hasSent = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) _startCountdown();
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  void _startCountdown() {
    _cancel();
    _hasSent = true;
    _remainingSeconds = widget.seconds;
    if (_remainingSeconds == 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _remainingSeconds--;
      });
      if (_remainingSeconds == 0) {
        _cancel();
      }
    });
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _sendCode() async {
    if (!_isEnabled) return;
    final callback = widget.onTapCallback!;
    setState(() => _loading = true);
    try {
      final sent = await callback();
      if (!mounted) return;
      if (sent) _startCountdown();
    } catch (_) {
      // The request callback owns error feedback; a failure remains retryable.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _isEnabled =>
      widget.enabled &&
      widget.onTapCallback != null &&
      !_loading &&
      _remainingSeconds == 0;

  @override
  Widget build(BuildContext context) {
    if (!widget.themed) {
      return (_remainingSeconds > 0
              ? '${_remainingSeconds}S'
              : StrRes.sendVerificationCode)
          .toText
        ..style = Styles.ts_0089FF_17sp
        ..onTap = _isEnabled ? _sendCode : null;
    }
    final theme = Theme.of(context);
    final chinese =
        (Get.locale ?? Localizations.localeOf(context)).languageCode == 'zh';
    final label = _loading
        ? (chinese ? '发送中' : 'Sending')
        : _remainingSeconds > 0
            ? '${_remainingSeconds}s'
            : _hasSent
                ? (chinese ? '重新获取' : 'Resend')
                : (chinese ? '获取验证码' : 'Send code');
    return TextButton(
      onPressed: _isEnabled ? _sendCode : null,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
        foregroundColor: theme.colorScheme.primary,
        disabledForegroundColor: theme.colorScheme.onSurfaceVariant,
        textStyle: theme.textTheme.labelLarge?.copyWith(
          fontSize: AppTokens.captionFontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
      child: _loading
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: AppTokens.s5,
                  height: AppTokens.s5,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: AppTokens.s3),
                Text(label),
              ],
            )
          : Text(label),
    );
  }
}
