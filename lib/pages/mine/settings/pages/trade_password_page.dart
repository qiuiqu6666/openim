import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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
  static const double _upperScale = 0.75;
  static const double _lowerScale = 0.6;

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
    if (_input.length != 6 || _submitting) return;
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
    if (!widget.service.isBackendAvailable) {
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
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _input = '';
        _error = settingsText(
          context,
          zh: '设置失败，请稍后重试',
          en: 'Failed to set the password. Please try again later.',
        );
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
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final statusText = _submitting
        ? settingsText(context, zh: '正在提交...', en: 'Submitting...')
        : (_error.isEmpty ? '' : _error);
    final subText = AppTokens.textSecondary(dark: dark);
    final statusColor = _error.isEmpty ? subText : settingsDanger(dark);
    final u = _upperScale;
    final k = _lowerScale;

    return SettingsScaffold(
      title: settingsText(context, zh: '设置交易密码', en: 'Set Transaction Password'),
      onLeadingPressed: _onBack,
      disableLeading: _submitting,
      bottom: Padding(
        padding: EdgeInsets.fromLTRB(
          (32 * k).w,
          (8 * k).h,
          (32 * k).w,
          (16 * k).h + bottomInset,
        ),
        child: _TradePasswordKeyPad(
          key: const ValueKey('trade-password-keypad'),
          enabled: !_submitting,
          onDigit: _onDigit,
          onDelete: _onDelete,
          scale: k,
        ),
      ),
      children: [
        SettingsGroup(
          children: [
            SizedBox(height: (28 * u).h),
            _PlatformLogo(scale: u),
            SizedBox(height: (32 * u).h),
            Text(
              _stepHint(context),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: (15 * u).sp,
                fontWeight: FontWeight.w400,
                color: subText,
                height: 1.3,
              ),
            ),
            SizedBox(height: (48 * u).h),
            _TradePasswordPinDots(
              key: const ValueKey('trade-password-pin-dots'),
              length: _input.length,
              hasError: _error.isNotEmpty,
              dotSize: (14 * u).w,
              spacing: (20 * u).w,
            ),
            SizedBox(height: (20 * u).h),
            SizedBox(
              height: (22 * u).h,
              child: Center(
                child: Text(
                  statusText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: (13 * u).sp,
                    color: statusColor,
                  ),
                ),
              ),
            ),
            if (_step == _SetupStep.confirm)
              TextButton(
                onPressed: _submitting
                    ? null
                    : () {
                        setState(() {
                          _step = _SetupStep.create;
                          _input = '';
                          _firstPin = null;
                          _error = '';
                        });
                      },
                child: Text(
                  settingsText(context, zh: '重新设置密码', en: 'Reset Password'),
                  style: TextStyle(
                    fontSize: (14 * u).sp,
                    color: AppTokens.accent,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _PlatformLogo extends StatelessWidget {
  const _PlatformLogo({this.scale = 1});
  final double scale;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final size = (88 * scale).w;
    final radius = (20 * scale).r;
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          'assets/images/im_new_logo_99chat.jpg',
          package: 'openim_common',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Image.asset(
            'assets/images/platform_99_fallback.webp',
            package: 'openim_common',
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: settingsSurfaceAlt(dark),
                borderRadius: BorderRadius.circular(radius),
              ),
              child: Icon(
                Icons.account_balance_wallet_rounded,
                size: (44 * scale).sp,
                color: AppTokens.textSecondary(dark: dark),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TradePasswordPinDots extends StatelessWidget {
  const _TradePasswordPinDots({
    super.key,
    required this.length,
    this.pinLength = 6,
    this.hasError = false,
    this.dotSize,
    this.spacing,
  });

  final int length;
  final int pinLength;
  final bool hasError;
  final double? dotSize;
  final double? spacing;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final size = dotSize ?? 14.w;
    final gap = spacing ?? 18.w;
    final emptyColor = dark ? AppTokens.borderDark : const Color(0xFFE3E3E3);
    final filledColor = hasError
        ? settingsDanger(dark)
        : AppTokens.textPrimary(dark: dark);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(pinLength, (i) {
        final filled = length > i;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: gap / 2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? filledColor : emptyColor,
            ),
          ),
        );
      }),
    );
  }
}

class _TradePasswordKeyPad extends StatelessWidget {
  const _TradePasswordKeyPad({
    super.key,
    required this.enabled,
    required this.onDigit,
    required this.onDelete,
    this.scale = 1,
  });

  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final double scale;

  static const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', 'del'];

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final keyBg = dark ? const Color(0xFF2A2D33) : const Color(0xFFE0E0E0);
    final s = scale;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: keys.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisExtent: (72 * s).h,
        mainAxisSpacing: (16 * s).h,
        crossAxisSpacing: (20 * s).w,
      ),
      itemBuilder: (_, i) {
        final key = keys[i];
        if (key.isEmpty) return const SizedBox.shrink();
        final isDelete = key == 'del';
        return _KeyButton(
          key: ValueKey('trade-password-key-$key'),
          enabled: enabled,
          scale: s,
          backgroundColor: keyBg,
          label: isDelete ? null : key,
          icon: isDelete ? Icons.backspace_outlined : null,
          onTap: isDelete
              ? () {
                  HapticFeedback.selectionClick();
                  onDelete();
                }
              : () {
                  HapticFeedback.selectionClick();
                  onDigit(key);
                },
        );
      },
    );
  }
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({
    super.key,
    required this.enabled,
    required this.onTap,
    required this.scale,
    required this.backgroundColor,
    this.label,
    this.icon,
  });

  final bool enabled;
  final VoidCallback onTap;
  final double scale;
  final Color backgroundColor;
  final String? label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final radius = (16 * scale).r;
    final contentColor = enabled
        ? AppTokens.textPrimary(dark: dark)
        : AppTokens.textSecondary(dark: dark);
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          alignment: Alignment.center,
          child: icon != null
              ? Icon(icon, size: (32 * scale).sp, color: contentColor)
              : Text(
                  label ?? '',
                  style: TextStyle(
                    fontSize: (34 * scale).sp,
                    fontWeight: FontWeight.w400,
                    color: contentColor,
                  ),
                ),
        ),
      ),
    );
  }
}
