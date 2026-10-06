import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../core/controller/im_controller.dart';
import '../../mine/settings/openim_profile_service.dart';
import '../../mine/settings/pages/trade_password_page.dart';
import '../../mine/settings/settings_service.dart';
import '../host/wallet_i18n.dart';
import '../host/wallet_navigation.dart';
import '../order/wallet_order_events.dart';
import '../widgets/wallet_tip.dart';

/// Checks both wallet entry points before changing the selected main tab.
/// Each attempt belongs to its originating route, tab and login session.
class WalletEntryCoordinator {
  WalletEntryCoordinator({
    SettingsService Function()? settingsFactory,
    String Function()? sessionKey,
  })  : _settingsFactory = settingsFactory ?? _settings,
        _sessionKey = sessionKey ?? _currentSession;

  final SettingsService Function() _settingsFactory;
  final String Function() _sessionKey;
  int _revision = 0;
  int? _pending;
  bool _disposed = false;

  static SettingsService _settings() {
    final controller = Get.find<IMController>();
    if (controller.isClosed || (DataSp.chatToken ?? '').isEmpty) {
      throw StateError('No active login session');
    }
    return OpenIMProfileService(controller);
  }

  static String _currentSession() =>
      '${WalletOrderEvents.currentAccountKey}:${DataSp.chatToken ?? ''}';

  /// Cancel pending navigation when a different tab is selected. This does
  /// not cancel password saves already owned by the settings page.
  void cancel() {
    _revision++;
    _pending = null;
  }

  void dispose() {
    _disposed = true;
    cancel();
  }

  Future<bool> enter(
    BuildContext context, {
    required bool Function() isActive,
    required VoidCallback onAllowed,
  }) async {
    if (_disposed || _pending != null || !context.mounted || !isActive()) {
      return false;
    }
    final request = ++_revision;
    final owner = _sessionKey();
    _pending = request;

    bool ownsSession() =>
        !_disposed &&
        request == _revision &&
        context.mounted &&
        isActive() &&
        _sessionKey() == owner;

    bool current() =>
        ownsSession() &&
        ModalRoute.of(context)?.isCurrent != false &&
        (WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed);

    try {
      if (!current()) return false;
      final settings = _WalletEntrySettings(_settingsFactory(), ownsSession);
      var ready = await settings.hasTradePassword();
      if (!context.mounted || !current()) return false;
      if (!ready) {
        final saved = await openWalletPage<bool>(
          context,
          TradePasswordPage(service: settings),
        );
        // The parent route must have resumed before reading status or opening
        // the wallet. A canceled setup never continues into the wallet.
        await WidgetsBinding.instance.endOfFrame;
        if (saved != true || !context.mounted || !current()) return false;
        ready = await settings.hasTradePassword();
        if (!context.mounted || !current()) return false;
        if (!ready) {
          WalletTip.show(context, _notSet(context));
          return false;
        }
      }
      onAllowed();
      return true;
    } catch (error) {
      if (context.mounted && current()) {
        WalletTip.show(
          context,
          HttpUtil.errorMessage(error,
              path: '/chat/fund/pay-password', fallback: _checkFailed(context)),
        );
      }
      return false;
    } finally {
      if (_pending == request) _pending = null;
    }
  }

  static String _checkFailed(BuildContext context) => AppI18n.of(context).t(
        zhHans: '无法确认支付密码状态，请稍后重试',
        zhHant: '無法確認支付密碼狀態，請稍後重試',
        en: 'Could not check your payment password. Please try again.',
        ja: '支払いパスワードの状態を確認できません。再度お試しください。',
        ko: '결제 비밀번호 상태를 확인할 수 없습니다. 다시 시도해 주세요.',
      );

  static String _notSet(BuildContext context) => AppI18n.of(context).t(
        zhHans: '支付密码尚未生效，请重新设置后再试',
        zhHant: '支付密碼尚未生效，請重新設定後再試',
        en: 'Your payment password is not set yet. Please set it and retry.',
        ja: '支払いパスワードが設定されていません。設定してから再度お試しください。',
        ko: '결제 비밀번호가 아직 설정되지 않았습니다. 설정 후 다시 시도해 주세요.',
      );
}

/// The existing settings page can stay mounted over Home. Bind its reads and
/// writes to the originating session rather than whichever token is current
/// when a user finishes entering the PIN.
class _WalletEntrySettings extends StubSettingsService {
  _WalletEntrySettings(this._delegate, this._isOwner);

  final SettingsService _delegate;
  final bool Function() _isOwner;

  void _requireOwner() {
    if (!_isOwner()) throw StateError('Wallet entry session ended');
  }

  @override
  bool get isSecurityBackendAvailable => _delegate.isSecurityBackendAvailable;

  @override
  Future<bool> hasTradePassword() async {
    _requireOwner();
    final ready = await _delegate.hasTradePassword();
    _requireOwner();
    return ready;
  }

  @override
  Future<void> setTradePassword(String password) async {
    _requireOwner();
    await _delegate.setTradePassword(password);
    _requireOwner();
  }
}
