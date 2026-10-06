import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:local_auth/local_auth.dart';
import 'package:openim_common/openim_common.dart';
import 'package:permission_handler/permission_handler.dart';

import '../settings_draft_store.dart';
import '../widgets/settings_widgets.dart';

class BiometricPayPage extends StatefulWidget {
  const BiometricPayPage({
    super.key,
    required this.store,
    this.paymentPasswordReady = true,
    this.onSetupPaymentPassword,
    this.authentication,
  });

  final SettingsDraftStore store;
  final bool paymentPasswordReady;
  final Future<bool> Function()? onSetupPaymentPassword;
  final LocalAuthentication? authentication;

  @override
  State<BiometricPayPage> createState() => _BiometricPayPageState();
}

enum _BioMode { fingerprint, face, faceAndFingerprint, biometric }

class _BiometricPayPageState extends State<BiometricPayPage>
    with WidgetsBindingObserver {
  late final LocalAuthentication _auth;
  late final String _accountID;
  bool get _ownsAccount => OpenIM.iMManager.userID == _accountID;
  static const _accentGreen = AppTokens.biometricGreen;

  bool _loading = true;
  bool _busy = false;
  late bool _paymentPasswordReady;
  _BioMode _mode = _BioMode.fingerprint;

  bool get _usesFace =>
      _mode == _BioMode.face || _mode == _BioMode.faceAndFingerprint;

  @override
  void initState() {
    super.initState();
    _accountID = OpenIM.iMManager.userID;
    _auth = widget.authentication ?? LocalAuthentication();
    WidgetsBinding.instance.addObserver(this);
    _paymentPasswordReady = widget.paymentPasswordReady;
    _load();
  }

  Future<void> _load() async {
    if (!_ownsAccount) return;
    widget.store
        .setBiometricPay(DataSp.isEnabledBiometricPay(accountID: _accountID));
    try {
      final types = await _auth.getAvailableBiometrics();
      final hasFace = types.contains(BiometricType.face);
      final hasFingerprint = types.contains(BiometricType.fingerprint) ||
          types.contains(BiometricType.strong) ||
          types.contains(BiometricType.weak);
      if (!mounted) return;
      setState(() {
        _mode = hasFace && hasFingerprint
            ? _BioMode.faceAndFingerprint
            : hasFace
                ? _BioMode.face
                : hasFingerprint
                    ? _BioMode.fingerprint
                    : defaultTargetPlatform == TargetPlatform.iOS
                        ? _BioMode.face
                        : defaultTargetPlatform == TargetPlatform.android
                            ? _BioMode.fingerprint
                            : _BioMode.biometric;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mode = _BioMode.biometric;
        _loading = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_busy) _auth.stopAuthentication().catchError((_) => false);
    super.dispose();
  }

  String _pageTitle(BuildContext context) {
    switch (_mode) {
      case _BioMode.face:
        return settingsText(context, zh: '手机面容识别', en: 'Face ID for Payments');
      case _BioMode.faceAndFingerprint:
        return settingsText(context,
            zh: '手机面容/指纹识别', en: 'Biometrics for Payments');
      case _BioMode.biometric:
        return settingsText(context,
            zh: '手机生物识别', en: 'Biometrics for Payments');
      case _BioMode.fingerprint:
        return settingsText(context,
            zh: '手机指纹识别', en: 'Fingerprint for Payments');
    }
  }

  String _description(BuildContext context) {
    switch (_mode) {
      case _BioMode.face:
        return settingsText(context,
            zh: '开启后，支付时可验证面容，快速完成付款。',
            en: 'Once enabled, verify with Face ID to pay faster.');
      case _BioMode.faceAndFingerprint:
        return settingsText(context,
            zh: '开启后，支付时可验证面容或指纹，快速完成付款。',
            en: 'Once enabled, verify with face or fingerprint to pay faster.');
      case _BioMode.biometric:
        return settingsText(context,
            zh: '开启后，支付时可验证生物识别，快速完成付款。',
            en: 'Once enabled, verify with biometrics to pay faster.');
      case _BioMode.fingerprint:
        return settingsText(context,
            zh: '开启后，支付时可验证指纹，快速完成付款。',
            en: 'Once enabled, verify with fingerprint to pay faster.');
    }
  }

  String _actionLabel(BuildContext context) {
    if (widget.store.biometricPay) {
      return switch (_mode) {
        _BioMode.face => settingsText(context,
            zh: '关闭手机面容识别', en: 'Disable Face ID for payments'),
        _BioMode.faceAndFingerprint => settingsText(context,
            zh: '关闭手机面容/指纹识别', en: 'Disable biometrics for payments'),
        _BioMode.biometric => settingsText(context,
            zh: '关闭手机生物识别', en: 'Disable biometrics for payments'),
        _BioMode.fingerprint => settingsText(context,
            zh: '关闭手机指纹识别', en: 'Disable fingerprint for payments'),
      };
    }
    return switch (_mode) {
      _BioMode.face => settingsText(context,
          zh: '开启手机面容识别', en: 'Enable Face ID for payments'),
      _BioMode.faceAndFingerprint => settingsText(context,
          zh: '开启手机面容/指纹识别', en: 'Enable biometrics for payments'),
      _BioMode.biometric => settingsText(context,
          zh: '开启手机生物识别', en: 'Enable biometrics for payments'),
      _BioMode.fingerprint => settingsText(context,
          zh: '开启手机指纹识别', en: 'Enable fingerprint for payments'),
    };
  }

  Future<void> _onActionTap() async {
    if (_busy || _loading || !_ownsAccount) return;
    if (widget.store.biometricPay) {
      final ok = await showSettingsConfirm(
        context,
        title: _actionLabel(context),
        message: settingsText(
          context,
          zh: '关闭后，支付时需重新输入 6 位支付密码。',
          en: 'You will need to enter your 6-digit payment password again.',
        ),
        confirmText: settingsText(context, zh: '关闭', en: 'Disable'),
        destructive: true,
      );
      if (ok) {
        if (!mounted) return;
        setState(() => _busy = true);
        try {
          if (!_ownsAccount) return;
          final saved =
              await DataSp.setBiometricPay(false, accountID: _accountID);
          if (saved != true) {
            throw StateError('Could not save biometric preference');
          }
          if (!mounted || !_ownsAccount) return;
          widget.store.setBiometricPay(false);
          showSettingsMessage(
              context,
              settingsText(context,
                  zh: '生物识别支付已关闭', en: 'Biometric payments disabled'));
        } catch (error) {
          if (mounted) {
            showSettingsError(
                context,
                error,
                settingsText(context,
                    zh: '关闭失败，请稍后重试',
                    en: 'Could not disable biometric payments. Please retry.'));
          }
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      }
      return;
    }

    if (!_paymentPasswordReady) {
      IMViews.showToast(
        settingsText(
          context,
          zh: '请先设置支付密码',
          en: 'Please set a payment password first.',
        ),
      );
      final setup = widget.onSetupPaymentPassword;
      if (setup != null) {
        final ready = await setup();
        if (!mounted) return;
        _paymentPasswordReady = ready;
      }
      return;
    }

    setState(() => _busy = true);
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      final enrolled = await _auth.getAvailableBiometrics();
      if (!mounted) return;
      if (!supported || !canCheck) {
        showSettingsMessage(
          context,
          settingsText(
            context,
            zh: '当前设备不支持生物识别支付。',
            en: 'This device does not support biometric payments.',
          ),
        );
        return;
      }
      if (enrolled.isEmpty) {
        final goSettings = await showSettingsConfirm(
          context,
          title:
              settingsText(context, zh: '未设置生物识别', en: 'Biometric not set up'),
          message: settingsText(
            context,
            zh: '请先在系统「设置 → 安全」中录入指纹或面容，再返回开启快捷支付。',
            en: 'Add a fingerprint or face in Settings > Security, then return to enable quick pay.',
          ),
          confirmText: settingsText(context, zh: '去设置', en: 'Go to Settings'),
        );
        if (goSettings) {
          await openAppSettings();
        }
        return;
      }
      final authenticated = await _auth.authenticate(
        localizedReason: settingsText(
          context,
          zh: '验证身份以开启快捷支付',
          en: 'Verify your identity to enable quick pay',
        ),
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: false,
        ),
      );
      if (mounted && _ownsAccount && authenticated) {
        final saved = await DataSp.setBiometricPay(true, accountID: _accountID);
        if (saved != true) {
          throw StateError('Could not save biometric preference');
        }
        if (mounted && _ownsAccount) {
          widget.store.setBiometricPay(true);
          showSettingsMessage(
              context,
              settingsText(context,
                  zh: '生物识别支付已开启', en: 'Biometric payments enabled'));
        }
      } else if (mounted) {
        showSettingsMessage(
            context,
            settingsText(context,
                zh: '身份验证未通过，未开启生物识别支付',
                en: 'Authentication was not completed. Biometric payments remain disabled.'));
      }
    } on PlatformException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'NotEnrolled' => settingsText(context,
            zh: '请先在系统设置中录入指纹或面容',
            en: 'Enroll a fingerprint or face in device settings first.'),
        'PasscodeNotSet' => settingsText(context,
            zh: '请先设置手机锁屏密码，再开启生物识别', en: 'Set a device passcode first.'),
        'LockedOut' => settingsText(context,
            zh: '尝试次数过多，请稍后再试', en: 'Too many attempts. Try again later.'),
        'PermanentlyLockedOut' => settingsText(context,
            zh: '生物识别已锁定，请先用手机锁屏密码解锁后重试',
            en: 'Unlock your device with its passcode, then retry.'),
        'NotAvailable' => settingsText(context,
            zh: '生物识别暂不可用，请检查系统权限和设置',
            en: 'Biometrics unavailable. Check device permissions and settings.'),
        _ => settingsText(context,
            zh: '生物识别验证未完成，请重试',
            en: 'Biometric authentication was not completed. Please retry.'),
      };
      showSettingsMessage(context, message);
    } catch (_) {
      if (!mounted) return;
      showSettingsMessage(
        context,
        settingsText(context,
            zh: '生物识别验证失败，请稍后重试',
            en: 'Biometric verification failed. Try again later.'),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final bg = AppTokens.background(dark: dark);
    final text = AppTokens.textPrimary(dark: dark);
    final subText = AppTokens.textSecondary(dark: dark);
    final line = AppTokens.border(dark: dark);
    final overlay = AppSystemBars.styleFor(bg);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: bg,
        appBar: GlassAppBar(
          toolbarHeight: kToolbarHeight,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: bg,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: overlay,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: AppTokens.accent,
            onPressed: () =>
                Navigator.of(context).pop(widget.store.biometricPay),
          ),
        ),
        body: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : Column(
                children: [
                  const SizedBox(height: 36),
                  _BiometricHeroIcon(usesFace: _usesFace, color: _accentGreen),
                  const SizedBox(height: 28),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Text(
                      _pageTitle(context),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: text,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      _description(context),
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 14, color: subText, height: 1.55),
                    ),
                  ),
                  const SizedBox(height: 48),
                  Material(
                    color: AppTokens.surface(dark: dark),
                    child: InkWell(
                      onTap: _busy ? null : _onActionTap,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: line, width: 0.6),
                            bottom: BorderSide(color: line, width: 0.6),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _actionLabel(context),
                                style: TextStyle(
                                  fontSize: 16,
                                  color: text,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                            if (_busy)
                              SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CupertinoActivityIndicator(color: subText),
                              )
                            else ...[
                              Text(
                                widget.store.biometricPay
                                    ? settingsText(context,
                                        zh: '已开启', en: 'Enabled')
                                    : settingsText(context,
                                        zh: '未开启', en: 'Disabled'),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: widget.store.biometricPay
                                      ? _accentGreen
                                      : subText,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 20,
                                color: subText.withValues(alpha: 0.55),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _BiometricHeroIcon extends StatelessWidget {
  const _BiometricHeroIcon({required this.usesFace, required this.color});

  final bool usesFace;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (!usesFace) {
      return Icon(Icons.fingerprint_rounded, size: 88, color: color);
    }
    return SizedBox(
      width: 112,
      height: 112,
      child: CustomPaint(painter: _FaceIdBracketPainter(color: color)),
    );
  }
}

class _FaceIdBracketPainter extends CustomPainter {
  _FaceIdBracketPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bracket = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.055
      ..strokeCap = StrokeCap.round;

    final len = w * 0.22;
    final inset = w * 0.12;

    void corner(Offset origin, {required bool top, required bool left}) {
      final dx = left ? 1.0 : -1.0;
      final dy = top ? 1.0 : -1.0;
      final point = origin;
      canvas.drawLine(point, point + Offset(dx * len, 0), bracket);
      canvas.drawLine(point, point + Offset(0, dy * len), bracket);
    }

    corner(Offset(inset, inset), top: true, left: true);
    corner(Offset(w - inset, inset), top: true, left: false);
    corner(Offset(inset, h - inset), top: false, left: true);
    corner(Offset(w - inset, h - inset), top: false, left: false);

    final face = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final cx = w / 2;
    final cy = h / 2;
    canvas.drawCircle(Offset(cx - w * 0.11, cy - h * 0.04), w * 0.028, face);
    canvas.drawCircle(Offset(cx + w * 0.11, cy - h * 0.04), w * 0.028, face);

    final smile = Path()
      ..moveTo(cx - w * 0.14, cy + h * 0.08)
      ..quadraticBezierTo(
        cx,
        cy + h * 0.18,
        cx + w * 0.14,
        cy + h * 0.08,
      );
    canvas.drawPath(
      smile,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.045
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _FaceIdBracketPainter oldDelegate) =>
      oldDelegate.color != color;
}
