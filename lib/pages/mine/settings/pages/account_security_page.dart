import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
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
}) =>
    platformSupported && deviceSupported;

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
  late String _phone;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _tradePasswordSet = widget.tradePasswordSet;
    _phone = widget.phoneNumber;
    widget.store.setBiometricPay(DataSp.isEnabledBiometricPay());
    _ready = !widget.service.isSecurityBackendAvailable;
    _reload();
  }

  Future<void> _reload() async {
    if (!widget.service.isSecurityBackendAvailable) return;
    setState(() {
      _ready = false;
    });
    try {
      await widget.service.refreshSecurity();
      final ready = await widget.service.hasTradePassword();
      if (mounted) {
        setState(() {
          _ready = true;
          _phone = widget.service.securityPhone;
          _tradePasswordSet = ready;
        });
      }
    } catch (error) {
      if (mounted) {
        showSettingsError(
            context,
            error,
            settingsText(context,
                zh: '安全信息加载失败，请重试',
                en: 'Could not load security settings. Retry.'));
      }
    }
  }

  Future<void> _openPhone() async {
    final result = await openSettingsPage<bool>(
        context,
        ChangePhonePage(
            service: widget.service,
            isBound: _phone.isNotEmpty,
            currentPhone: _phone),
        activityPage: 'account_security');
    if (result == true && mounted) await _reload();
  }

  Future<bool> _openTradePassword(BuildContext context) async {
    if (!_ready) return false;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/pay_password'),
        builder: (_) => _tradePasswordSet
            ? ChangeTradePasswordPage(
                service: widget.service,
                phoneNumber: _phone,
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
                  title:
                      settingsText(context, zh: '修改密码', en: 'Change Password'),
                  onTap: !_ready
                      ? null
                      : () => openSettingsPage(
                            context,
                            ChangePasswordPage(
                              service: widget.service,
                              phoneNumber: _phone,
                            ),
                          ),
                ),
                SettingsCell(
                  title:
                      settingsText(context, zh: '支付密码', en: 'Payment Password'),
                  onTap: !_ready ? null : () => _openTradePassword(context),
                ),
                _BiometricSettingsEntry(
                  store: widget.store,
                  paymentPasswordReady: _ready && _tradePasswordSet,
                  onSetupPaymentPassword: () => _openTradePassword(context),
                ),
                SettingsCell(
                  title: _phone.trim().isEmpty
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
                  onTap: !_ready ? null : _openPhone,
                ),
                SettingsCell(
                  title: settingsText(context, zh: '登录设备', en: 'Login Devices'),
                  showDivider: false,
                  onTap: () => openSettingsPage(
                    context,
                    LoginDevicesPage(service: widget.service),
                    activityPage: 'login_devices',
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
  State<_BiometricSettingsEntry> createState() =>
      _BiometricSettingsEntryState();
}

class _BiometricSettingsEntryState extends State<_BiometricSettingsEntry> {
  final _auth = LocalAuthentication();
  late final String _accountID;
  bool _supported = false;
  String _label = '';

  @override
  void initState() {
    super.initState();
    _accountID = OpenIM.iMManager.userID;
    final cached = DataSp.getBiometricSettings(_accountID);
    _supported = _platformSupported && (cached?['supported'] as bool? ?? true);
    _label = cached?['mode'] as String? ?? '';
    _load();
  }

  Future<void> _load() async {
    if (!_platformSupported) return;
    var supported = false;
    var types = <BiometricType>[];

    try {
      supported = await _auth.isDeviceSupported();
    } catch (_) {
      // A temporary plugin failure must not replace a saved capability.
      return;
    }
    try {
      types = await _auth.getAvailableBiometrics();
    } catch (_) {
      // Keep the last known label when enumeration temporarily fails.
      return;
    }

    if (!mounted) return;
    final hasFace = types.contains(BiometricType.face);
    final hasFingerprint = types.contains(BiometricType.fingerprint) ||
        types.contains(BiometricType.strong) ||
        types.contains(BiometricType.weak);
    // Persist for the next visit without inserting/removing a visible row.
    // Capture the owner before awaits so an account switch cannot redirect writes.
    await DataSp.putBiometricSettings(_accountID, {
      'supported': supported,
      'mode': hasFace && hasFingerprint
          ? 'both'
          : hasFace
              ? 'face'
              : hasFingerprint
                  ? 'fingerprint'
                  : '',
    });
  }

  bool get _platformSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Widget build(BuildContext context) {
    if (!_supported) return const SizedBox.shrink();
    return SettingsCell(
      title: _label == 'both'
          ? settingsText(context, zh: '面容/指纹支付', en: 'Biometric Pay')
          : _label == 'face' ||
                  (_label.isEmpty &&
                      defaultTargetPlatform == TargetPlatform.iOS)
              ? settingsText(context, zh: '面容支付', en: 'Face ID Pay')
              : settingsText(context, zh: '指纹支付', en: 'Fingerprint Pay'),
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
