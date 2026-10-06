import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../services/fund_api.dart';
import '../../widgets/fund_page_colors.dart';
import '../data/fund_security_api.dart';
import '../data/fund_security_models.dart';
import '../data/fund_security_request.dart';
import 'fund_security_feedback.dart';
import 'fund_security_tokens.dart';

class FundSecuritySheetFailure {
  const FundSecuritySheetFailure(this.error);
  final Object error;
}

/// Native numeric keyboard entry for this transaction's SMS, separate from PIN.
class FundSecurityCodeSheet extends StatefulWidget {
  const FundSecurityCodeSheet({
    super.key,
    required this.request,
    required this.security,
    required this.phoneMasked,
    required this.isCurrent,
    this.now = DateTime.now,
  });
  final FundSecurityRequest request;
  final FundWithdrawalSecurityApi security;
  final String phoneMasked;
  final bool Function() isCurrent;
  final DateTime Function() now;

  @override
  State<FundSecurityCodeSheet> createState() => _FundSecurityCodeSheetState();
}

class _FundSecurityCodeSheetState extends State<FundSecurityCodeSheet> {
  final _code = TextEditingController();
  FundSecurityChallenge? _challenge;
  Timer? _timer;
  DateTime? _resendAt;
  bool _sending = false, _closing = false;
  String? _error;

  bool get _active => mounted && !_closing && widget.isCurrent();
  int get _remaining => _resendAt == null
      ? 0
      : math.max(0,
          (_resendAt!.difference(widget.now()).inMilliseconds / 1000).ceil());
  bool get _expired =>
      _challenge != null &&
      widget.now().millisecondsSinceEpoch >= _challenge!.expiresAt;
  bool get _canConfirm =>
      _active &&
      !_sending &&
      !_expired &&
      _challenge != null &&
      RegExp(r'^\d{6}$').hasMatch(_code.text);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(FundSecurityTokens.tick, (_) {
      if (!mounted || _closing) return;
      if (!widget.isCurrent()) {
        _finish();
      } else {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_active) unawaited(_send());
    });
  }

  void _finish([Object? result]) {
    if (!mounted || _closing) return;
    _closing = true;
    _code.clear();
    _challenge = null;
    _timer?.cancel();
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    if (route != null && !route.isCurrent) {
      // A different page may have covered this sheet after an account change.
      // Remove only our route; never pop that unrelated page.
      navigator.removeRoute(route, result);
    } else {
      navigator.pop(result);
    }
  }

  Future<void> _send() async {
    if (!_active || _sending || _remaining > 0) return;
    setState(() {
      _sending = true;
      _error = null;
      _challenge = null;
      _code.clear();
    });
    try {
      final result = await widget.security.send(widget.request);
      if (!_active) return;
      setState(() {
        _challenge = result;
        _resendAt =
            widget.now().add(Duration(seconds: result.retryAfterSeconds));
        if (_expired) _error = '验证码已过期，请重新获取';
      });
    } catch (error) {
      if (!_active) return;
      if (error is FundApiException &&
          {20076, 20079, 20038}.contains(error.code)) {
        _finish(FundSecuritySheetFailure(error));
        return;
      }
      setState(() {
        _error = fundSecurityErrorMessage(error);
        if (error is FundApiException && error.code == 20080) {
          _resendAt = widget.now().add(const Duration(seconds: 60));
        }
      });
    } finally {
      if (_active) setState(() => _sending = false);
    }
  }

  void _confirm() {
    if (!_canConfirm) return;
    _finish(FundSecurityProof(
        challengeID: _challenge!.challengeID,
        code: _code.text,
        expiresAt: _challenge!.expiresAt));
  }

  @override
  void dispose() {
    _closing = true;
    _timer?.cancel();
    _challenge = null;
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = FundPageColors.of(context);
    final phone = _challenge?.phoneMasked ?? widget.phoneMasked;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final error = _error ?? (_expired ? '验证码已过期，请重新获取' : null);
    final sendLabel = _sending
        ? '发送中'
        : _remaining > 0
            ? '${_remaining}s 后重发'
            : _challenge == null
                ? '获取验证码'
                : '重新发送';
    return SafeArea(
      key: const ValueKey('fund-security-sheet'),
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: FundSecurityTokens.maxWidth),
              child: Padding(
                padding: const EdgeInsets.all(AppTokens.s7),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    Expanded(
                        child: Text('短信验证',
                            style: TextStyle(
                                color: colors.text,
                                fontSize: FundSecurityTokens.titleFont,
                                fontWeight: FontWeight.w600))),
                    IconButton(
                        key: const ValueKey('fund-security-cancel'),
                        tooltip: '取消本次验证',
                        onPressed: _finish,
                        color: colors.subText,
                        icon: const Icon(Icons.close_rounded)),
                  ]),
                  const SizedBox(height: AppTokens.s4),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Text('验证码发送至 $phone，仅用于本次交易',
                          style: TextStyle(
                              color: colors.text,
                              fontSize: FundSecurityTokens.bodyFont))),
                  const SizedBox(height: AppTokens.s7),
                  TextField(
                    key: const ValueKey('fund-security-code'),
                    controller: _code,
                    enabled: !_sending && _challenge != null && !_expired,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6)
                    ],
                    style: TextStyle(
                        color: colors.text,
                        fontSize: FundSecurityTokens.codeFont,
                        letterSpacing: FundSecurityTokens.codeLetterSpacing),
                    cursorColor: colors.inputCursor,
                    decoration: InputDecoration(
                        hintText: '输入6位短信验证码',
                        hintStyle: TextStyle(
                            color: colors.inputHint,
                            fontSize: FundSecurityTokens.bodyFont,
                            letterSpacing: 0),
                        filled: true,
                        fillColor: colors.inputFill,
                        contentPadding: const EdgeInsets.all(AppTokens.s5),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppTokens.rMd),
                            borderSide: BorderSide.none)),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _confirm(),
                  ),
                  Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                          key: const ValueKey('fund-security-resend'),
                          onPressed:
                              !_sending && _remaining == 0 ? _send : null,
                          style: TextButton.styleFrom(
                              foregroundColor: colors.blue,
                              minimumSize: const Size(
                                  FundSecurityTokens.targetMinSize,
                                  FundSecurityTokens.targetMinSize)),
                          child: Text(sendLabel))),
                  if (error != null)
                    Padding(
                        padding: const EdgeInsets.only(bottom: AppTokens.s5),
                        child: Semantics(
                            liveRegion: true,
                            child: Text(error,
                                key: const ValueKey('fund-security-error'),
                                style: TextStyle(
                                    color: AppTokens.paymentError(
                                        dark: colors.dark),
                                    fontSize: FundSecurityTokens.bodyFont)))),
                  SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                          key: const ValueKey('fund-security-confirm'),
                          onPressed: _canConfirm ? _confirm : null,
                          style: FilledButton.styleFrom(
                              backgroundColor: colors.blue,
                              foregroundColor: AppTokens.onAccent,
                              disabledBackgroundColor: colors.disabledButton,
                              disabledForegroundColor: colors.subText,
                              minimumSize: const Size.fromHeight(
                                  FundSecurityTokens.targetMinSize)),
                          child: const Text('继续支付'))),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
