import 'dart:async';
import 'package:flutter/material.dart';
import 'auth_copy.dart';
import 'auth_reference_tokens.dart';

class AuthFieldLabel extends StatelessWidget {
  const AuthFieldLabel(
    this.text, {
    super.key,
    this.style,
    this.padding =
        const EdgeInsets.only(bottom: AuthReferenceTokens.labelGap, left: 2),
  });
  final String text;
  final TextStyle? style;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Text(text, style: style ?? AuthReferenceTokens.label),
      );
}

class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton(
      {super.key,
      required this.text,
      this.loadingText,
      this.loading = false,
      this.pill = false,
      this.disabledForegroundColor = AuthReferenceTokens.ink400,
      this.textStyle,
      this.onPressed});
  final String text;
  final String? loadingText;
  final bool loading;
  final bool pill;
  final Color disabledForegroundColor;
  final TextStyle? textStyle;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AuthReferenceTokens.brand500,
            disabledBackgroundColor: AuthReferenceTokens.ink100,
            foregroundColor: Colors.white,
            disabledForegroundColor: disabledForegroundColor,
            minimumSize: const Size(0, AuthReferenceTokens.fieldHeight),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AuthReferenceTokens.rLg)),
            textStyle: (textStyle ?? AuthReferenceTokens.button).copyWith(
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily),
          ),
          onPressed: loading || onPressed == null
              ? null
              : () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  onPressed?.call();
                },
          child: loading
              ? Semantics(
                  label: loadingText ?? text,
                  child: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.white)))
              : Text(text, textAlign: TextAlign.center),
        ),
      );
}

class AuthCountryCode extends StatelessWidget {
  const AuthCountryCode({super.key, required this.code, required this.onTap});
  final String code;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: authText('选择国家或地区', 'Choose country or region'),
        child: InkWell(
            onTap: onTap,
            child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(code,
                      style: const TextStyle(
                          fontSize: AuthReferenceTokens.inputFontSize,
                          color: AuthReferenceTokens.link,
                          fontWeight: FontWeight.w600,
                          height: 1.2)),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down_rounded,
                      size: 18, color: AuthReferenceTokens.ink400),
                ]))),
      );
}

/// Starts a cooldown only after the existing server verification succeeds.
class AuthCodeAction extends StatefulWidget {
  const AuthCodeAction({super.key, required this.onSend, this.enabled = true});
  final Future<bool> Function() onSend;
  final bool enabled;
  @override
  State<AuthCodeAction> createState() => _AuthCodeActionState();
}

class _AuthCodeActionState extends State<AuthCodeAction> {
  Timer? _timer;
  int _remaining = 0;
  bool _sending = false;
  Future<void> _send() async {
    if (_sending || _remaining > 0 || !widget.enabled) return;
    setState(() => _sending = true);
    try {
      final sent = await widget.onSend();
      if (!mounted || !sent) return;
      setState(() => _remaining = 60);
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _remaining--);
        if (_remaining == 0) timer.cancel();
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextButton(
        style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 48),
            foregroundColor: AuthReferenceTokens.link,
            textStyle: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily:
                    Theme.of(context).textTheme.bodyMedium?.fontFamily)),
        onPressed:
            widget.enabled && !_sending && _remaining == 0 ? _send : null,
        child: _sending
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Text(
                _remaining > 0
                    ? '${_remaining}s'
                    : authText('获取验证码', 'Get code'),
                textAlign: TextAlign.center),
      );
}

class AuthVersionFooter extends StatelessWidget {
  const AuthVersionFooter({super.key, this.version = '3.8.3'});
  final String version;
  @override
  Widget build(BuildContext context) => Text('Version $version',
      textAlign: TextAlign.center, style: AuthReferenceTokens.caption);
}
