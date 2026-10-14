import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/openim_live.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../../../services/platform_config_service.dart';
import '../platform_update_dialog.dart';
import '../../widgets/settings_widgets.dart';
import 'android_update_controller.dart';
import 'android_update_platform.dart';

/// App-lifetime owner, independent of login/home route replacement and accounts.
class AndroidUpdateRuntime with WidgetsBindingObserver {
  AndroidUpdateRuntime._();
  static final instance = AndroidUpdateRuntime._();
  AndroidUpdateController? controller;
  final revision = ValueNotifier<int>(0);
  final _dismiss = ValueNotifier<int>(0);
  SharedPreferences? _prefs;
  Future<void>? _initializing;
  Timer? _poll;
  bool _showing = false;
  String? _dialogSignature, _pendingPermission;
  DateTime _lastRefresh = DateTime.fromMillisecondsSinceEpoch(0);
  bool get blocksNavigation =>
      _showing && controller?.ready == true && controller!.force;
  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool get _calling =>
      OpenIMLiveClient().isBusy ||
      PackageBridge.rtcBridge?.hasConnection == true;

  Future<void> start({bool manual = false}) async {
    try {
      await (_initializing ??= _initialize());
    } catch (_) {
      _initializing = null;
      return;
    }
    if (manual) {
      await _prefs!.remove('android_update_snooze_key');
      await controller!.tick(refresh: true);
    } else {
      await controller!.tick();
    }
    _changed();
  }

  Future<void> _initialize() async {
    _prefs = await SharedPreferences.getInstance();
    var id = _prefs!.getString('platform_update_install_id');
    if (id == null) {
      id = const Uuid().v4();
      await _prefs!.setString('platform_update_install_id', id);
    }
    controller = AndroidUpdateController(
      platform: NativeAndroidUpdatePlatform(),
      fetch: () => PlatformConfigService.fetch(),
      installedVersion: () async {
        final info = await PackageInfo.fromPlatform();
        return '${info.version}+${info.buildNumber}';
      },
      bucket: id.codeUnits.fold<int>(0, (sum, c) => (sum * 31 + c) % 100),
    )..addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_foreground) return;
      final refresh = _showing &&
          DateTime.now().difference(_lastRefresh) > const Duration(minutes: 1);
      if (refresh) _lastRefresh = DateTime.now();
      unawaited(controller!.tick(refresh: refresh));
      _changed(); // A call may have ended since the package became ready.
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_resume());
  }

  Future<void> _resume() async {
    await controller?.tick(refresh: true);
    final key = _pendingPermission;
    _pendingPermission = null;
    if (key != null &&
        !_calling &&
        controller?.ready == true &&
        controller!.package!.key == key &&
        await controller!.platform.canInstall()) {
      try {
        await controller!.install(key);
      } catch (_) {/* Retry button stays available. */}
    }
    _changed();
  }

  void _changed() {
    revision.value++;
    final c = controller;
    if (c == null) return;
    final signature = c.ready ? '${c.package!.key}:${c.force}' : null;
    if (_showing && signature != _dialogSignature) {
      _dialogSignature = null;
      _dismiss.value++;
    }
    if (!c.ready || _showing || !_foreground || _calling) return;
    final until = _prefs!.getInt('android_update_snooze_until') ?? 0;
    if (!c.force &&
        _prefs!.getString('android_update_snooze_key') == c.package!.key &&
        DateTime.now().millisecondsSinceEpoch < until) {
      return;
    }
    final context = Get.key.currentState?.overlay?.context;
    if (context == null || !context.mounted) return;
    _showing = true;
    _dialogSignature = signature;
    _lastRefresh = DateTime.now();
    unawaited(_present(context, signature!));
  }

  Future<void> _present(BuildContext context, String signature) async {
    final c = controller!;
    final target = c.package!;
    try {
      await showPlatformUpdateDialog(
        context,
        title: settingsText(context, zh: '新版本已准备好', en: 'Update Ready'),
        message: target.release.changelog.isNotEmpty
            ? target.release.changelog
            : settingsText(context,
                zh: 'v${target.release.latest} 已下载完成，安装后即可使用。',
                en: 'Version ${target.release.latest} is downloaded and ready to install.'),
        force: c.force,
        keepOpenOnSuccess: true,
        dismissSignal: _dismiss,
        actionLabel: settingsText(context, zh: '立即安装', en: 'Install Now'),
        failureMessage: settingsText(context,
            zh: '安装未完成，请允许安装应用后重试。',
            en: 'Installation did not complete. Allow app installation and retry.'),
        onUpdate: () async {
          if (_calling) throw StateError('Call in progress');
          // Set before opening Settings so a quick lifecycle transition cannot
          // lose the pending permission continuation.
          _pendingPermission = target.key;
          try {
            final launched = await c.install(target.key);
            if (launched || !c.ready || c.package?.key != target.key) {
              _pendingPermission = null;
            }
          } catch (_) {
            _pendingPermission = null;
            rethrow;
          }
        },
      );
      if (_dialogSignature == signature && !c.force) {
        await _prefs!.setString('android_update_snooze_key', target.key);
        await _prefs!.setInt(
            'android_update_snooze_until',
            DateTime.now()
                .add(const Duration(hours: 24))
                .millisecondsSinceEpoch);
      }
    } finally {
      _showing = false;
      _dialogSignature = null;
      revision.value++;
    }
  }

  String statusText(BuildContext context) {
    final c = controller;
    if (c == null) return '';
    return switch (c.phase) {
      AndroidUpdatePhase.downloading => settingsText(context,
          zh: c.total > 0
              ? '后台下载 ${(c.bytes * 100 / c.total).clamp(0, 100).floor()}%'
              : '正在后台下载',
          en: c.total > 0
              ? 'Downloading ${(c.bytes * 100 / c.total).clamp(0, 100).floor()}%'
              : 'Downloading'),
      AndroidUpdatePhase.verifying =>
        settingsText(context, zh: '正在校验安装包', en: 'Verifying update'),
      AndroidUpdatePhase.ready =>
        settingsText(context, zh: '已下载，点击安装', en: 'Ready to install'),
      AndroidUpdatePhase.retry => settingsText(context,
          zh: '更新暂不可用，点击重试', en: 'Update unavailable. Tap to retry'),
      _ => '',
    };
  }

  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    controller?.removeListener(_changed);
    controller?.dispose();
  }
}
