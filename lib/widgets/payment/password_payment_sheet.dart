import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';

import 'payment_sheet_tokens.dart';
import 'payment_strings.dart';
import 'trade_password_keypad.dart';
import 'trade_password_pin_cells.dart';

enum PasswordPaymentState { enteringPassword, processing, success }

typedef PaymentSummaryBuilder = Widget Function(
    BuildContext context, VoidCallback? changePaymentMethod);

/// A business adapter can provide actionable text without exposing raw errors.
class PasswordPaymentException implements Exception {
  const PasswordPaymentException(this.message);
  final String message;
}

class PaymentSheetKeys {
  const PaymentSheetKeys({
    this.sheet = const ValueKey('payment-sheet'),
    this.password = const ValueKey('payment-password'),
    this.confirm = const ValueKey('payment-confirm'),
    this.cancel = const ValueKey('payment-cancel'),
    this.keypad = const ValueKey('payment-keypad'),
  });
  final Key sheet, password, confirm, cancel, keypad;
}

/// Uses the existing Material bottom-sheet route. Cancellation is explicit so
/// a drag or scrim tap can never remove a request that is already in flight.
Future<T?> showPasswordPaymentSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) =>
    showModalBottomSheet<T>(
      context: context,
      builder: builder,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppTokens.surface(
          dark: Theme.of(context).brightness == Brightness.dark),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(PaymentSheetTokens.radius))),
    );

/// Owns one payment attempt at a time. The business callback owns its durable
/// idempotency key, authorization/account checks and authoritative result.
/// A refresh callback failing after payment succeeds never reopens payment.
class PasswordPaymentSheet<T> extends StatefulWidget {
  const PasswordPaymentSheet({
    super.key,
    required this.title,
    this.summary,
    this.summaryBuilder,
    this.onChangePaymentMethod,
    this.canChangePaymentMethod,
    required this.onPay,
    this.errorMessage,
    this.onError,
    this.onSuccess,
    this.keys = const PaymentSheetKeys(),
    this.successDisplayDuration = PaymentSheetTokens.successDisplay,
  }) : assert(summary != null || summaryBuilder != null);
  final String title;
  final Widget? summary;
  final PaymentSummaryBuilder? summaryBuilder;

  /// Returns true only when the reviewed payment details actually changed.
  /// Selection is serialized with password input and payment submission.
  final Future<bool> Function()? onChangePaymentMethod;

  /// Business owners can lock an unresolved original transaction on retry.
  final bool Function()? canChangePaymentMethod;
  final Future<T> Function(String password) onPay;
  final String Function(Object error)? errorMessage;
  final ValueChanged<String>? onError;
  final FutureOr<void> Function(T result)? onSuccess;
  final PaymentSheetKeys keys;
  final Duration successDisplayDuration;

  @override
  State<PasswordPaymentSheet<T>> createState() =>
      _PasswordPaymentSheetState<T>();
}

class _PasswordPaymentSheetState<T> extends State<PasswordPaymentSheet<T>> {
  final _pin = TextEditingController();
  final _focus = FocusNode();
  PasswordPaymentState _state = PasswordPaymentState.enteringPassword;
  String? _error;
  Timer? _closeTimer;
  bool _closing = false;
  bool _changingPaymentMethod = false;
  bool get _passwordState => _state == PasswordPaymentState.enteringPassword;
  bool get _entering => _passwordState && !_closing && !_changingPaymentMethod;
  bool get _canChangePaymentMethod =>
      _entering &&
      widget.onChangePaymentMethod != null &&
      (widget.canChangePaymentMethod?.call() ?? true);
  bool get _canHandleResult =>
      mounted && !_closing && ModalRoute.of(context)?.isActive != false;

  @override
  void initState() {
    super.initState();
    _pin.addListener(_changed);
  }

  void _changed() {
    if (!_entering || !mounted) return;
    if (_pin.text.length == 6) {
      unawaited(_pay());
    } else {
      setState(() => _error = null);
    }
  }

  Future<void> _changePaymentMethod() async {
    if (!_canChangePaymentMethod ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    setState(() => _changingPaymentMethod = true);
    _focus.unfocus();
    try {
      final changed = await widget.onChangePaymentMethod!();
      if (!_canHandleResult) return;
      if (changed) {
        _pin.clear();
        _error = null;
      }
    } catch (error) {
      if (!_canHandleResult) return;
      _error = _message(error);
      await _notifyError(_error!);
    } finally {
      if (_canHandleResult) {
        setState(() => _changingPaymentMethod = false);
        _focus.requestFocus();
      }
    }
  }

  Future<void> _pay() async {
    if (!mounted ||
        !_entering ||
        ModalRoute.of(context)?.isCurrent == false ||
        !RegExp(r'^\d{6}$').hasMatch(_pin.text)) {
      return;
    }
    final password = _pin.text;
    // Lock synchronously, before even a synchronously completed request or
    // another paste/semantic action can start a second attempt.
    setState(() {
      _state = PasswordPaymentState.processing;
      _error = null;
    });
    _focus.unfocus();
    late final T result;
    try {
      result = await widget.onPay(password);
    } catch (error) {
      if (!_canHandleResult) return;
      final message = _message(error);
      _pin.clear();
      setState(() {
        _state = PasswordPaymentState.enteringPassword;
        _error = message;
      });
      _focus.requestFocus();
      await _notifyError(message);
      return;
    }
    if (!_canHandleResult) return;
    setState(() => _state = PasswordPaymentState.success);
    _closeTimer =
        Timer(widget.successDisplayDuration, () => _closeSuccess(result));
    // Start the refresh immediately, but slow reads cannot keep a completed
    // payment open indefinitely. A refresh failure never authorizes replay.
    try {
      await widget.onSuccess?.call(result);
    } catch (_) {
      // Business refresh owners can retry their reads independently.
    }
  }

  String _message(Object error) {
    try {
      final message = widget.errorMessage?.call(error) ??
          (error is PasswordPaymentException ? error.message : null);
      if (message != null && message.trim().isNotEmpty) return message;
    } catch (_) {}
    return paymentText(context,
        zh: '支付失败，请重试', en: 'Payment failed. Please retry.');
  }

  Future<void> _notifyError(String message) async {
    try {
      if (widget.onError != null) {
        widget.onError!(message);
      } else {
        await IMViews.showToast(message);
      }
    } catch (_) {
      // The reserved inline error remains readable when there is no app toast
      // host (e.g. a standalone widget or a temporarily removed overlay).
    }
  }

  void _closeSuccess(T result) {
    if (!mounted || _closing) return;
    _closing = true;
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    if (route?.isCurrent == true) {
      navigator.pop<T>(result);
    } else if (route != null && route.isActive) {
      // Do not pop a newer route placed above this sheet during a refresh.
      navigator.removeRoute(route, result);
    }
  }

  void _cancel() {
    if (!_entering) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  void _digit(String digit) {
    if (!_entering || _pin.text.length >= 6) return;
    final value = '${_pin.text}$digit';
    _pin.value = TextEditingValue(
        text: value, selection: TextSelection.collapsed(offset: value.length));
  }

  void _delete() {
    if (!_entering || _pin.text.isEmpty) return;
    final value = _pin.text.substring(0, _pin.text.length - 1);
    _pin.value = TextEditingValue(
        text: value, selection: TextSelection.collapsed(offset: value.length));
  }

  @override
  void dispose() {
    _closing = true;
    _closeTimer?.cancel();
    _pin.removeListener(_changed);
    _pin.dispose();
    _focus.dispose();
    super.dispose();
  }

  Widget _paymentStatus(Color secondary) => Center(
        key: ValueKey('pay-state-${_state.name}'),
        child: Semantics(
          liveRegion: true,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_state == PasswordPaymentState.processing)
              LoadingView.indicator(
                  size: PaymentSheetTokens.indicatorSize,
                  color: AppTokens.accent,
                  style: LoadingIndicatorStyle.ring)
            else
              TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : PaymentSheetTokens.successAnimation,
                  builder: (_, value, child) => Opacity(
                      opacity: value,
                      child: Transform.scale(
                          scale: .8 + value * .2, child: child)),
                  child: const Icon(Icons.check_rounded,
                      color: AppTokens.success,
                      size: PaymentSheetTokens.successSize)),
            const SizedBox(height: PaymentSheetTokens.statusGap),
            Text(
                _state == PasswordPaymentState.processing
                    ? paymentText(context,
                        zh: '支付处理中…', en: 'Processing payment…')
                    : paymentText(context,
                        zh: '支付成功', en: 'Payment successful'),
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: secondary, fontSize: AppTokens.captionFontSize)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = AppTokens.textPrimary(dark: dark);
    final secondary = AppTokens.textSecondary(dark: dark);
    final viewport = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final upper = viewport.height * .96;
    final maxHeight =
        (viewport.height * (.88 + math.max(0.0, textScale - 1) * .05))
            .clamp(math.min(480.0, upper), upper)
            .toDouble();
    final bottom = MediaQuery.paddingOf(context).bottom;
    return PopScope<T>(
      canPop: _entering || _closing,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _closing = true;
          _closeTimer?.cancel();
        }
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
            key: widget.keys.sheet,
            decoration: BoxDecoration(
                color: AppTokens.surface(dark: dark),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(PaymentSheetTokens.radius))),
            child: SafeArea(
                top: false,
                bottom: false,
                child: Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(
                            maxWidth: PaymentSheetTokens.maxWidth),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          const SizedBox(height: 7),
                          Container(
                              width: PaymentSheetTokens.handleWidth,
                              height: PaymentSheetTokens.handleHeight,
                              decoration: BoxDecoration(
                                  color: AppTokens.border(dark: dark),
                                  borderRadius:
                                      BorderRadius.circular(AppTokens.rPill))),
                          Padding(
                              padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
                              child: SizedBox(
                                  height: 28,
                                  child: Stack(children: [
                                    Align(
                                        alignment: Alignment.centerRight,
                                        child: InkWell(
                                            key: widget.keys.cancel,
                                            onTap: _entering ? _cancel : null,
                                            borderRadius: BorderRadius.circular(
                                                PaymentSheetTokens.radius),
                                            child: Padding(
                                                padding: const EdgeInsets.all(
                                                    AppTokens.s2),
                                                child: Icon(Icons.close_rounded,
                                                    size: 19.5,
                                                    color: _entering
                                                        ? secondary
                                                        : AppTokens.border(
                                                            dark: dark))))),
                                    Center(
                                        child: Text(widget.title,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium!
                                                .copyWith(
                                                    fontSize: PaymentSheetTokens
                                                        .titleFont,
                                                    color: secondary,
                                                    fontWeight:
                                                        FontWeight.w500))),
                                  ]))),
                          Flexible(
                              child: SingleChildScrollView(
                                  physics: const ClampingScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(
                                      AppTokens.s5,
                                      AppTokens.s3,
                                      AppTokens.s5,
                                      0),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        AbsorbPointer(
                                            absorbing: !_entering,
                                            child: widget.summaryBuilder?.call(
                                                    context,
                                                    _canChangePaymentMethod
                                                        ? () => unawaited(
                                                            _changePaymentMethod())
                                                        : null) ??
                                                widget.summary!),
                                        SizedBox(
                                            key: const ValueKey(
                                                'payment-password-region'),
                                            height: PaymentSheetTokens.cellSize,
                                            child: Semantics(
                                                key: widget.keys.confirm,
                                                label: paymentText(context,
                                                    zh: '六位支付密码',
                                                    en:
                                                        'Six-digit payment password'),
                                                value: paymentText(context,
                                                    zh:
                                                        '已输入 ${_passwordState ? _pin.text.length : 6} 位，共 6 位',
                                                    en:
                                                        '${_passwordState ? _pin.text.length : 6} of 6 digits entered'),
                                                enabled: _entering,
                                                customSemanticsActions:
                                                    _entering
                                                        ? {
                                                            CustomSemanticsAction(
                                                                label: paymentText(
                                                                    context,
                                                                    zh: '支付',
                                                                    en: 'Pay')): () =>
                                                                unawaited(
                                                                    _pay())
                                                          }
                                                        : null,
                                                child: Stack(
                                                    alignment: Alignment.center,
                                                    children: [
                                                      TextField(
                                                          key: widget
                                                              .keys.password,
                                                          controller: _pin,
                                                          focusNode: _focus,
                                                          enabled: _entering,
                                                          readOnly: !_entering,
                                                          autofocus: true,
                                                          obscureText: true,
                                                          showCursor: false,
                                                          enableSuggestions:
                                                              false,
                                                          enableIMEPersonalizedLearning:
                                                              false,
                                                          autocorrect: false,
                                                          keyboardType:
                                                              TextInputType
                                                                  .none,
                                                          textAlign:
                                                              TextAlign.center,
                                                          textAlignVertical:
                                                              TextAlignVertical
                                                                  .center,
                                                          maxLength: 6,
                                                          style: TextStyle(
                                                              fontSize: 16,
                                                              color: text
                                                                  .withValues(
                                                                      alpha:
                                                                          0)),
                                                          inputFormatters: [
                                                            FilteringTextInputFormatter
                                                                .digitsOnly,
                                                            LengthLimitingTextInputFormatter(
                                                                6)
                                                          ],
                                                          decoration: const InputDecoration(
                                                              isCollapsed: true,
                                                              border:
                                                                  InputBorder
                                                                      .none,
                                                              disabledBorder:
                                                                  InputBorder
                                                                      .none,
                                                              counterText: ''),
                                                          onSubmitted: (_) =>
                                                              unawaited(
                                                                  _pay())),
                                                      ExcludeSemantics(
                                                          child: IgnorePointer(
                                                              child: TradePasswordPinCells(
                                                                  length: _passwordState
                                                                      ? _pin
                                                                          .text
                                                                          .length
                                                                      : 6,
                                                                  hasError:
                                                                      _error !=
                                                                          null,
                                                                  showEmptyDots:
                                                                      false,
                                                                  walletPayStyle:
                                                                      true))),
                                                    ]))),
                                        SizedBox(
                                            height: PaymentSheetTokens
                                                .feedbackHeight,
                                            child: _error == null
                                                ? null
                                                : Center(
                                                    child: Semantics(
                                                        liveRegion: true,
                                                        child: Text(_error!,
                                                            key: const ValueKey(
                                                                'payment-error'),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                                fontSize: 11,
                                                                color: AppTokens
                                                                    .paymentError(
                                                                        dark:
                                                                            dark)))))),
                                      ]))),
                          SizedBox(
                              key: const ValueKey('payment-keypad-region'),
                              height: PaymentSheetTokens.keypadHeight + bottom,
                              child: Padding(
                                  padding: EdgeInsets.only(bottom: bottom),
                                  child: _passwordState
                                      ? KeyedSubtree(
                                          key: const ValueKey(
                                              'pay-state-enteringPassword'),
                                          child: TradePasswordKeyPad(
                                              key: widget.keys.keypad,
                                              walletPayStyle: true,
                                              enabled: _entering,
                                              onDigit: _digit,
                                              onDelete: _delete))
                                      : _paymentStatus(secondary))),
                        ]))))),
      ),
    );
  }
}
