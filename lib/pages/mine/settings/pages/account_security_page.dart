import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:openim_common/openim_common.dart';

import '../settings_draft_store.dart';
import '../settings_navigation.dart';
import '../settings_service.dart';
import '../widgets/settings_widgets.dart';
import 'biometric_pay_page.dart';
import 'change_password_page.dart';
import 'change_phone_page.dart';
import 'change_trade_password_page.dart';
import 'login_devices_page.dart';
import 'trade_password_page.dart';


bool shouldShowBiometricSettingsEntry({
  required bool platformSupported,
  required bool deviceSupported,
}) => platformSupported && deviceSupported;

class AccountSecurityPage extends StatefulWidget {
  const AccountSecurityPage({
    super.key,
    required this.store,
    required this.service,
    this.phoneNumber = '',
    this.tradePasswordSet = false,
  });

  final SettingsDraftStore store;
  final SettingsService service;
  final String phoneNumber;
  final bool tradePasswordSet;

  @override
  State<AccountSecurityPage> createState() => _AccountSecurityPageState();
}

class _AccountSecurityPageState extends State<AccountSecurityPage> {
  late bool _tradePasswordSet;

  @override
  void initState() {
    super.initState();
    _tradePasswordSet = widget.tradePasswordSet;
  }

  Future<bool> _openTradePassword(BuildContext context) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _tradePasswordSet
            ? ChangeTradePasswordPage(
                service: widget.service,
                phoneNumber: widget.phoneNumber,
              )
            : TradePasswordPage(service: widget.service),
      ),
    );
    if (result == true && mounted && !_tradePasswordSet) {
      setState(() => _tradePasswordSet = true);
    }
    return _tradePasswordSet;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) => SettingsScaffold(
          title: settingsText(context, zh: '账号安全', en: 'Account Security'),
          children: [
            SettingsGroup(
              children: [
                SettingsCell(
                  title: settingsText(context, zh: '修改密码', en: 'Change Password'),
                  onTap: () => openSettingsPage(
                    context,
                    ChangePasswordPage(
                      service: widget.service,
                      phoneNumber: widget.phoneNumber,
                    ),
                  ),
                ),
                SettingsCell(
                  title: settingsText(context, zh: '支付密码', en: 'Payment Password'),
                  onTap: () => _openTradePassword(context),
                ),
                _BiometricSettingsEntry(
                  store: widget.store,
                  paymentPasswordReady: _tradePasswordSet,
                  onSetupPaymentPassword: () => _openTradePassword(context),
                ),
                SettingsCell(
                  title: widget.phoneNumber.trim().isEmpty
                      ? settingsText(
                          context,
                          zh: '绑定手机号码',
                          en: 'Link Phone Number',
                        )
                      : settingsText(
                          context,
                          zh: '修改手机号码',
                          en: 'Change Phone Number',
                        ),
                  onTap: () => openSettingsPage(
                    context,
                    ChangePhonePage(
                      service: widget.service,
                      isBound: widget.phoneNumber.trim().isNotEmpty,
                      currentPhone: widget.phoneNumber,
                    ),
                  ),
                ),
                SettingsCell(
                  title: settingsText(context, zh: '登录设备', en: 'Login Devices'),
                  showDivider: false,
                  onTap: () => openSettingsPage(
                    context,
                    const LoginDevicesPage(),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _BiometricSettingsEntry extends StatefulWidget {
  const _BiometricSettingsEntry({
    required this.store,
    required this.paymentPasswordReady,
    required this.onSetupPaymentPassword,
  });

  final SettingsDraftStore store;
  final bool paymentPasswordReady;
  final Future<bool> Function() onSetupPaymentPassword;

  @override
  State<_BiometricSettingsEntry> createState() => _BiometricSettingsEntryState();
}

class _BiometricSettingsEntryState extends State<_BiometricSettingsEntry> {
  final _auth = LocalAuthentication();
  bool _loading = true;
  bool _supported = false;
  String _label = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final platformSupported = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    var supported = false;
    var types = <BiometricType>[];

    try {
      supported = await _auth.isDeviceSupported();
    } catch (_) {}
    try {
      types = await _auth.getAvailableBiometrics();
    } catch (_) {}

    if (!mounted) return;
    final hasFace = types.contains(BiometricType.face);
    final hasFingerprint = types.contains(BiometricType.fingerprint) ||
        types.contains(BiometricType.strong) ||
        types.contains(BiometricType.weak);
    final enabled = DataSp.isEnabledBiometric() ?? false;
    widget.store.setBiometricPay(enabled);
    setState(() {
      _supported = shouldShowBiometricSettingsEntry(
        platformSupported: platformSupported,
        deviceSupported: supported,
      );
      _label = hasFace && hasFingerprint
          ? settingsText(context, zh: '面容/指纹支付', en: 'Biometric Pay')
          : hasFace
              ? settingsText(context, zh: '面容支付', en: 'Face ID Pay')
              : hasFingerprint
                  ? settingsText(context, zh: '指纹支付', en: 'Fingerprint Pay')
                  : defaultTargetPlatform == TargetPlatform.iOS
                      ? settingsText(context, zh: '面容支付', en: 'Face ID Pay')
                      : defaultTargetPlatform == TargetPlatform.android
                          ? settingsText(context, zh: '指纹支付', en: 'Fingerprint Pay')
                          : settingsText(context, zh: '生物识别支付', en: 'Biometric Pay');
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || !_supported) return const SizedBox.shrink();
    return SettingsCell(
      title: _label.isEmpty
          ? settingsText(context, zh: '指纹支付', en: 'Fingerprint Pay')
          : _label,
      value: widget.store.biometricPay
          ? settingsText(context, zh: '已开启', en: 'Enabled')
          : settingsText(context, zh: '未开启', en: 'Disabled'),
      onTap: () => openSettingsPage(
        context,
        BiometricPayPage(
          store: widget.store,
          paymentPasswordReady: widget.paymentPasswordReady,
          onSetupPaymentPassword: widget.onSetupPaymentPassword,
        ),
      ),
    );
  }
}
