import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';

import '../settings_service.dart';
import '../widgets/settings_widgets.dart';

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
    final keypad = _TradePasswordKeyPad(
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
                            _TradePasswordPinCells(
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

class _TradePasswordPinCells extends StatelessWidget {
  const _TradePasswordPinCells({
    super.key,
    required this.length,
    required this.hasError,
  });

  final int length;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final border =
        hasError ? settingsDanger(dark) : AppTokens.border(dark: dark);
    return Semantics(
      label: settingsText(context, zh: '六位交易密码', en: 'Six-digit password'),
      value: settingsText(
        context,
        zh: '已输入 $length 位，共 6 位',
        en: '$length of 6 digits entered',
      ),
      liveRegion: true,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellSize =
              ((constraints.maxWidth - TradePasswordTokens.cellGap * 5) / 6)
                  .clamp(0.0, TradePasswordTokens.cellMaxSize);
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 6; i++) ...[
                if (i > 0) const SizedBox(width: TradePasswordTokens.cellGap),
                AnimatedContainer(
                  key: ValueKey('trade-password-cell-$i'),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : TradePasswordTokens.inputAnimation,
                  width: cellSize,
                  height: cellSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTokens.rSm),
                    border: Border.all(color: border),
                  ),
                  child: Container(
                    key: ValueKey('trade-password-dot-$i'),
                    width: TradePasswordTokens.dotSize,
                    height: TradePasswordTokens.dotSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: length > i
                          ? AppTokens.textPrimary(dark: dark)
                          : AppTokens.border(dark: dark),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TradePasswordKeyPad extends StatelessWidget {
  const _TradePasswordKeyPad({
    super.key,
    required this.enabled,
    required this.onDigit,
    required this.onDelete,
  });

  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;

  static const keys = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '',
    '0',
    'del'
  ];

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final keyHeight = (MediaQuery.sizeOf(context).height *
            TradePasswordTokens.keyHeightScreenRatio)
        .clamp(
      TradePasswordTokens.keyMinHeight,
      TradePasswordTokens.keyMaxHeight,
    );
    return ColoredBox(
      color: AppTokens.surfaceAlt(dark: dark),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: TradePasswordTokens.contentMaxWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.s3),
            child: GridView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: keys.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisExtent: keyHeight,
                mainAxisSpacing: AppTokens.s3,
                crossAxisSpacing: AppTokens.s3,
              ),
              itemBuilder: (_, i) {
                final key = keys[i];
                final isDelete = key == 'del';
                final keyBackground = isDelete || key.isEmpty
                    ? AppTokens.border(dark: dark)
                    : AppTokens.surface(dark: dark);
                if (key.isEmpty) {
                  return ExcludeSemantics(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: keyBackground,
                        borderRadius: BorderRadius.circular(AppTokens.rSm),
                      ),
                    ),
                  );
                }
                final label = isDelete
                    ? settingsText(context, zh: '删除一位', en: 'Delete digit')
                    : key;
                final color = enabled
                    ? AppTokens.textPrimary(dark: dark)
                    : AppTokens.textSecondary(dark: dark);
                void activate() {
                  HapticFeedback.selectionClick();
                  isDelete ? onDelete() : onDigit(key);
                }

                return Semantics(
                  button: true,
                  enabled: enabled,
                  label: label,
                  onTap: enabled ? activate : null,
                  excludeSemantics: true,
                  child: Material(
                    key: ValueKey('trade-password-key-$key'),
                    color: keyBackground,
                    borderRadius: BorderRadius.circular(AppTokens.rSm),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: enabled ? activate : null,
                      child: Center(
                        child: isDelete
                            ? Icon(
                                Icons.backspace_outlined,
                                size: TradePasswordTokens.deleteIconSize,
                                color: color,
                              )
                            : Text(
                                key,
                                style: TextStyle(
                                  fontSize: TradePasswordTokens.digitFontSize,
                                  fontWeight: FontWeight.w400,
                                  color: color,
                                  height: 1,
                                ),
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
