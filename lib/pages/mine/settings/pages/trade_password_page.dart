import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../settings_service.dart';
import '../widgets/settings_widgets.dart';
import '../widgets/trade_password_pin_cells.dart';
import '../widgets/trade_password_keypad.dart';

class TradePasswordPage extends StatefulWidget {
  const TradePasswordPage({
    super.key,
    this.service = const StubSettingsService(),
  });

  final SettingsService service;

  @override
  State<TradePasswordPage> createState() => _TradePasswordPageState();
}

enum _SetupStep { create, confirm }

class _TradePasswordPageState extends State<TradePasswordPage> {
  _SetupStep _step = _SetupStep.create;
  String _input = '';
  String? _firstPin;
  String _error = '';
  bool _submitting = false;

  String _stepHint(BuildContext context) => _step == _SetupStep.create
      ? settingsText(
          context,
          zh: '请输入交易密码',
          en: 'Enter your transaction password',
        )
      : settingsText(
          context,
          zh: '请再次输入交易密码',
          en: 'Enter your transaction password again',
        );

  void _onDigit(String digit) {
    if (_submitting || _input.length >= 6) return;
    setState(() {
      _input += digit;
      _error = '';
    });
    if (_input.length == 6) Future<void>.microtask(_onPinComplete);
  }

  void _onDelete() {
    if (_submitting || _input.isEmpty) return;
    setState(() {
      _input = _input.substring(0, _input.length - 1);
      _error = '';
    });
  }

  Future<void> _onPinComplete() async {
    if (!mounted || _input.length != 6 || _submitting) return;
    final pin = _input;
    if (_step == _SetupStep.create) {
      setState(() {
        _firstPin = pin;
        _input = '';
        _step = _SetupStep.confirm;
        _error = '';
      });
      return;
    }
    if (_firstPin != pin) {
      setState(() {
        _input = '';
        _error = settingsText(
          context,
          zh: '两次输入的密码不一致，请重新确认',
          en: 'The passwords do not match. Please try again.',
        );
      });
      return;
    }
    if (!widget.service.isSecurityBackendAvailable) {
      setState(() => _input = '');
      showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '交易密码', en: 'Transaction password'),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = '';
    });
    try {
      await widget.service.setTradePassword(pin);
      if (!mounted) return;
      showSettingsMessage(
        context,
        settingsText(context,
            zh: '支付密码设置成功', en: 'Payment password set successfully'),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _input = '';
        _error = settingsErrorMessage(context, error,
            fallback: settingsText(
              context,
              zh: '设置失败，请稍后重试',
              en: 'Failed to set the password. Please try again later.',
            ));
      });
    }
  }

  void _onBack() {
    if (_step == _SetupStep.confirm && !_submitting) {
      setState(() {
        _step = _SetupStep.create;
        _input = '';
        _firstPin = null;
        _error = '';
      });
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final statusText = _submitting
        ? settingsText(context, zh: '正在提交...', en: 'Submitting...')
        : _error;
    final secondary = AppTokens.textSecondary(dark: dark);
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final keypad = TradePasswordKeyPad(
      key: const ValueKey('trade-password-keypad'),
      enabled: !_submitting,
      onDigit: _onDigit,
      onDelete: _onDelete,
    );

    return SettingsScaffold(
      title:
          settingsText(context, zh: '设置交易密码', en: 'Set Transaction Password'),
      leading: IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        color: AppTokens.accent,
        onPressed: _submitting ? null : _onBack,
      ),
      onLeadingPressed: _onBack,
      disableLeading: _submitting,
      bottom: landscape ? null : keypad,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final content = Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: TradePasswordTokens.contentMaxWidth,
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          AppTokens.s8,
                          (constraints.maxHeight * 0.08).clamp(
                            AppTokens.s5,
                            AppTokens.s8,
                          ),
                          AppTokens.s8,
                          AppTokens.s5,
                        ),
                        child: Column(
                          children: [
                            const _PlatformLogo(),
                            const SizedBox(height: AppTokens.s7),
                            Text(
                              _stepHint(context),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: TradePasswordTokens.headingFontSize,
                                fontWeight: FontWeight.w600,
                                color: AppTokens.textPrimary(dark: dark),
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: AppTokens.s3),
                            Text(
                              settingsText(
                                context,
                                zh: '用于支付、转账、红包等资金操作',
                                en: 'For payments, transfers and red packets',
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: TradePasswordTokens.helperFontSize,
                                color: secondary,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: AppTokens.s7),
                            TradePasswordPinCells(
                              key: const ValueKey('trade-password-pin-dots'),
                              length: _input.length,
                              hasError: _error.isNotEmpty,
                            ),
                            if (statusText.isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: AppTokens.s4),
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    statusText,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize:
                                          TradePasswordTokens.helperFontSize,
                                      color: _error.isEmpty
                                          ? secondary
                                          : settingsDanger(dark),
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ),
                            if (_step == _SetupStep.confirm)
                              TextButton(
                                onPressed: _submitting ? null : _onBack,
                                child: Text(
                                  settingsText(
                                    context,
                                    zh: '重新设置密码',
                                    en: 'Reset Password',
                                  ),
                                  style: const TextStyle(
                                    fontSize:
                                        TradePasswordTokens.helperFontSize,
                                    color: AppTokens.accent,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.s7,
                  AppTokens.s3,
                  AppTokens.s7,
                  AppTokens.s5,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: TradePasswordTokens.securityIconSize,
                      color: secondary,
                    ),
                    const SizedBox(width: AppTokens.s3),
                    Flexible(
                      child: Text(
                        settingsText(
                          context,
                          zh: '资金安全保障中，请放心设置',
                          en: 'Set your password to protect your funds',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: TradePasswordTokens.securityFontSize,
                          color: secondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          return landscape
              ? Row(
                  children: [
                    Expanded(child: content),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: keypad,
                      ),
                    ),
                  ],
                )
              : content;
        },
      ),
      children: const [],
    );
  }
}

class _PlatformLogo extends StatelessWidget {
  const _PlatformLogo();

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(TradePasswordTokens.logoRadius),
        child: Image.asset(
          'assets/images/im_new_logo_99chat.jpg',
          package: 'openim_common',
          width: TradePasswordTokens.logoSize,
          height: TradePasswordTokens.logoSize,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
        ),
      );
}
