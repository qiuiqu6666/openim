import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/openim_live.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../services/platform_config_service.dart';
import '../platform_update_dialog.dart';
import '../../widgets/settings_widgets.dart';
import 'android_update_controller.dart';
import 'android_update_platform.dart';

/// App-lifetime owner, independent of login/home route replacement and accounts.
class AndroidUpdateRuntime with WidgetsBindingObserver {
  AndroidUpdateRuntime._();
  @visibleForTesting
  AndroidUpdateRuntime.test(
      {required AndroidUpdateController coordinator,
      required SharedPreferences preferences,
      required bool Function() foreground,
      required bool Function() calling,
      required BuildContext? Function() context,
      Future<bool> Function(Uri)? openURL,
      Stream<List<ConnectivityResult>>? networkChanges}) {
    controller = coordinator;
    _prefs = preferences;
    _foregroundOverride = foreground;
    _callingOverride = calling;
    _contextOverride = context;
    _openURLOverride = openURL;
    _initializing = Future.value();
    coordinator.addListener(_changed);
    if (networkChanges != null) _listenForNetwork(networkChanges);
  }
  static final instance = AndroidUpdateRuntime._();
  AndroidUpdateController? controller;
  final revision = ValueNotifier<int>(0);
  final _dismiss = ValueNotifier<int>(0);
  SharedPreferences? _prefs;
  Future<void>? _initializing;
  Timer? _poll;
  StreamSubscription<List<ConnectivityResult>>? _network;
  bool? _networkOnline;
  String? _savedRequiredWebsite;
  Future<void> _savingPolicy = Future.value();
  bool _showing = false;
  bool _visible = false;
  String? _dialogSignature, _pendingPermission;
  DateTime _lastRefresh = DateTime.fromMillisecondsSinceEpoch(0);
  bool Function()? _foregroundOverride, _callingOverride;
  BuildContext? Function()? _contextOverride;
  Future<bool> Function(Uri)? _openURLOverride;
  bool get blocksNavigation =>
      _visible && controller?.promptReady == true && controller!.force;
  bool get _foreground =>
      _foregroundOverride?.call() ??
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);
  bool get _calling =>
      _callingOverride?.call() ??
      (OpenIMLiveClient().isBusy ||
          PackageBridge.rtcBridge?.hasConnection == true);

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
    );
    _savedRequiredWebsite =
        _prefs!.getString('android_update_required_website');
    if (_savedRequiredWebsite != null) {
      try {
        await controller!.restoreRequiredWebsite(PlatformRelease(
            Map<String, dynamic>.from(
                jsonDecode(_savedRequiredWebsite!) as Map)));
      } catch (_) {/* A malformed cache must not replace the server policy. */}
    }
    controller!.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    _listenForNetwork(Connectivity().onConnectivityChanged);
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      // Let recoverable failures retry while this process is still scheduled
      // in the background. DownloadManager owns the actual background transfer.
      if (!_foreground && controller!.phase != AndroidUpdatePhase.retry) return;
      final refresh = _showing &&
          DateTime.now().difference(_lastRefresh) > const Duration(minutes: 1);
      if (refresh) _lastRefresh = DateTime.now();
      unawaited(controller!.tick(refresh: refresh));
    });
  }

  void _listenForNetwork(Stream<List<ConnectivityResult>> changes) {
    _network = changes.listen((results) {
      final online = results.any((value) => value != ConnectivityResult.none);
      final recovered = online && _networkOnline != true;
      _networkOnline = online;
      // Connectivity is a retry hint, not proof of internet access. The normal
      // backoff still applies if the request fails on a captive/broken network.
      if (recovered &&
          (controller?.phase == AndroidUpdatePhase.retry ||
              controller?.retrying == true)) {
        unawaited(controller!.tick(refresh: true));
      }
    }, onError: (Object _) {
      // The periodic retry remains available if the connectivity stream fails.
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
    try {
      if (key != null &&
          !_calling &&
          controller?.ready == true &&
          controller!.package!.key == key &&
          await controller!.platform.canInstall()) {
        await controller!.install(key);
      }
    } catch (_) {/* Retry button stays available. */}
    _changed();
  }

  void _changed() {
    revision.value++;
    final c = controller;
    if (c == null) return;
    final legacy = c.externalRelease;
    final saved = legacy != null && c.force
        ? jsonEncode({
            'latestVersion': legacy.latest,
            'minVersion': legacy.minimum,
            'downloadURL': legacy.downloadURL,
            'changelog': legacy.changelog,
          })
        : null;
    if (saved != _savedRequiredWebsite) {
      _savedRequiredWebsite = saved;
      _savingPolicy = _savingPolicy.then((_) async {
        if (saved == null) {
          await _prefs!.remove('android_update_required_website');
        } else {
          await _prefs!.setString('android_update_required_website', saved);
        }
      }).catchError((Object _) {});
    }
    final signature = c.promptReady ? '${c.promptKey}:${c.force}' : null;
    if (_showing && signature != _dialogSignature) {
      _dialogSignature = null;
      _dismiss.value++;
    }
    if (!c.promptReady || _showing || !_foreground || _calling) return;
    final until = _prefs!.getInt('android_update_snooze_until') ?? 0;
    if (!c.force &&
        _prefs!.getString('android_update_snooze_key') == c.promptKey &&
        DateTime.now().millisecondsSinceEpoch < until) {
      return;
    }
    final context = _contextOverride != null
        ? _contextOverride!()
        : Get.key.currentState?.overlay?.context;
    if (context == null || !context.mounted) return;
    _showing = true;
    _dialogSignature = signature;
    _lastRefresh = DateTime.now();
    unawaited(_present(context, signature!));
  }

  Future<void> _present(BuildContext context, String signature) async {
    final c = controller!;
    final key = c.promptKey!;
    try {
      // This also covers a cached APK waiting through a background period or
      // an active call. Do not display yesterday's policy on foreground entry.
      await c.tick(refresh: true);
      if (!c.promptReady ||
          '${c.promptKey}:${c.force}' != signature ||
          !_foreground ||
          _calling ||
          !context.mounted) {
        return;
      }
      _visible = true;
      final release = c.promptRelease!;
      final external = c.external;
      await showPlatformUpdateDialog(
        context,
        title: external
            ? settingsText(context,
                zh: '发现新版本',
                en: c.force ? 'Update Required' : 'Update Available')
            : settingsText(context, zh: '新版本已准备好', en: 'Update Ready'),
        message: release.changelog.isNotEmpty
            ? release.changelog
            : external
                ? settingsText(context,
                    zh: c.force ? '当前版本必须更新，请下载并安装新版本后继续使用。' : '发现新版本，是否前往下载？',
                    en: c.force
                        ? 'Please download and install the required update to continue.'
                        : 'A new version is available. Open the download page?')
                : settingsText(context,
                    zh: 'v${release.latest} 已下载完成，安装后即可使用。',
                    en: 'Version ${release.latest} is downloaded and ready to install.'),
        force: c.force,
        keepOpenOnSuccess: !external || c.force,
        dismissSignal: _dismiss,
        actionLabel: external
            ? settingsText(context, zh: '立即更新', en: 'Update Now')
            : settingsText(context, zh: '立即安装', en: 'Install Now'),
        failureMessage: external
            ? settingsText(context,
                zh: '获取或打开更新失败，请检查网络后点击立即更新重试。',
                en:
                    'Unable to fetch or open the update. Check your connection and try again.')
            : settingsText(context,
                zh: '安装未完成，请允许安装应用后重试。',
                en: 'Installation did not complete. Allow app installation and retry.'),
        onUpdate: () async {
          if (_calling) throw StateError('Call in progress');
          if (external) {
            await c.openExternal(_openURLOverride ??
                (uri) => launchUrl(uri, mode: LaunchMode.externalApplication));
            return;
          }
          // Set before opening Settings so a quick lifecycle transition cannot
          // lose the pending permission continuation.
          _pendingPermission = key;
          try {
            final launched = await c.install(key);
            if (launched || !c.ready || c.package?.key != key) {
              _pendingPermission = null;
            }
          } catch (_) {
            _pendingPermission = null;
            rethrow;
          }
        },
      );
      if (_dialogSignature == signature && !c.force) {
        await _prefs!.setString('android_update_snooze_key', key);
        await _prefs!.setInt(
            'android_update_snooze_until',
            DateTime.now()
                .add(const Duration(hours: 24))
                .millisecondsSinceEpoch);
      }
    } finally {
      _showing = false;
      _visible = false;
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
      AndroidUpdatePhase.external =>
        settingsText(context, zh: '发现新版本，点击更新', en: 'Update available'),
      AndroidUpdatePhase.retry => settingsText(context,
          zh: '正在自动恢复更新', en: 'Retrying update automatically'),
      _ => '',
    };
  }

  bool get hasFallback {
    final uri = Uri.tryParse(controller?.fallbackURL ?? '');
    return controller?.phase == AndroidUpdatePhase.retry &&
        uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty;
  }

  Future<bool> openFallback() async {
    if (!hasFallback) return false;
    try {
      return await launchUrl(Uri.parse(controller!.fallbackURL),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _poll?.cancel();
    unawaited(_network?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    controller?.removeListener(_changed);
    controller?.dispose();
  }
}
