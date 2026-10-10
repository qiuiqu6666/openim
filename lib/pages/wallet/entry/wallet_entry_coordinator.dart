import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../core/controller/im_controller.dart';
import '../../../services/fund/diagnostics/wallet_load_log.dart';
import '../../mine/settings/openim_profile_service.dart';
import '../../mine/settings/pages/trade_password_page.dart';
import '../../mine/settings/settings_service.dart';
import '../host/wallet_i18n.dart';
import '../host/wallet_navigation.dart';
import '../order/wallet_order_events.dart';

enum WalletEntryPhase { idle, checking, needsPassword, ready, failed }

/// The wallet tab opens immediately; only a verified session reveals its body.
class WalletEntryCoordinator extends ChangeNotifier {
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
  WalletEntryPhase _phase = WalletEntryPhase.idle;
  String? _message;
  String? _owner;
  int _contentEpoch = 0;
  WalletLoadLog? _trace;

  WalletEntryPhase get phase => _phase;
  String? get message => _message;
  int get contentEpoch => _contentEpoch;
  bool get isReady =>
      _phase == WalletEntryPhase.ready && _owner == _sessionKey();

  void _publish(WalletEntryPhase phase, [String? message]) {
    if (_disposed) return;
    _phase = phase;
    _message = message;
    _trace?.event('phase', {'phase': phase.name});
    notifyListeners();
  }

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
    _trace?.finish('cancelled', {'phase': _phase.name, 'disposed': _disposed});
    _trace = null;
    _revision++;
    _pending = null;
    _publish(WalletEntryPhase.idle);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancel();
    super.dispose();
  }

  Future<bool> enter(
    BuildContext context, {
    required bool Function() isActive,
    required VoidCallback onAllowed,
  }) async {
    if (_disposed || _pending != null || !context.mounted || !isActive()) {
      WalletLoadLog.note('entry', 'skipped', {
        'phase': _phase.name,
        'disposed': _disposed,
        'pending': _pending != null,
        'mounted': context.mounted,
        'active': !_disposed && context.mounted && isActive(),
      });
      return false;
    }
    final request = ++_revision;
    final owner = _sessionKey();
    if (_owner != owner) _contentEpoch++;
    _owner = owner;
    _pending = request;
    final trace = _trace = WalletLoadLog.start('entry',
        details: {'request': request, 'contentEpoch': _contentEpoch},
        watchPending: true);
    _publish(WalletEntryPhase.checking);

    bool ownsSession() =>
        !_disposed &&
        request == _revision &&
        context.mounted &&
        isActive() &&
        _sessionKey() == owner;

    bool current() {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      final valid = ownsSession() &&
          ModalRoute.of(context)?.isCurrent != false &&
          (lifecycle == null || lifecycle == AppLifecycleState.resumed);
      if (!valid) {
        trace?.event('ignored', {
          'disposed': _disposed,
          'requestCurrent': request == _revision,
          'mounted': context.mounted,
          'active': context.mounted && isActive(),
          'sessionCurrent': _sessionKey() == owner,
          'routeCurrent':
              context.mounted ? ModalRoute.of(context)?.isCurrent : null,
          'lifecycle': lifecycle?.name,
        });
      }
      return valid;
    }

    try {
      if (!current()) return false;
      final settings = _WalletEntrySettings(_settingsFactory(), ownsSession);
      trace?.event('password_check_start');
      var ready = await settings.hasTradePassword();
      trace?.event('password_check_result', {'passwordSet': ready});
      if (!context.mounted || !current()) return false;
      if (!ready) {
        _publish(WalletEntryPhase.needsPassword, _notSet(context));
        trace?.event('password_setup_open');
        final saved = await openWalletPage<bool>(
          context,
          TradePasswordPage(service: settings),
          activityPage: 'pay_password',
        );
        trace?.event('password_setup_closed', {'saved': saved == true});
        // Wait for the parent route to resume before checking again.
        await WidgetsBinding.instance.endOfFrame;
        if (saved != true || !context.mounted || !current()) return false;
        _publish(WalletEntryPhase.checking);
        trace?.event('password_recheck_start');
        ready = await settings.hasTradePassword();
        trace?.event('password_check_result', {'passwordSet': ready});
        if (!context.mounted || !current()) return false;
        if (!ready) {
          _publish(WalletEntryPhase.needsPassword, _notSet(context));
          return false;
        }
      }
      _publish(WalletEntryPhase.ready);
      onAllowed();
      return true;
    } catch (error) {
      trace?.error(error);
      if (context.mounted && current()) {
        _publish(
          WalletEntryPhase.failed,
          HttpUtil.errorMessage(error,
              path: '/chat/fund/pay-password', fallback: _checkFailed(context)),
        );
      }
      return false;
    } finally {
      if (_pending == request) {
        _pending = null;
        // A response rejected while covered/backgrounded must not leave an
        // endless skeleton when the user returns. Retrying starts a new check.
        if (context.mounted && _phase == WalletEntryPhase.checking) {
          _publish(WalletEntryPhase.failed, _checkFailed(context));
        }
      }
      trace?.finish('end', {'phase': _phase.name, 'disposed': _disposed});
      if (identical(_trace, trace)) _trace = null;
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
