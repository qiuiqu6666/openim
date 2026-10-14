import 'package:flutter/foundation.dart';
import '../../../../../services/platform_config_service.dart';
import 'android_update_package.dart';
import 'android_update_platform.dart';

enum AndroidUpdatePhase { idle, checking, downloading, verifying, ready, retry }

/// Process-wide coordinator. A successful network request is not proof of a
/// successful install. Only installed version and a verified APK govern state.
class AndroidUpdateController extends ChangeNotifier {
  AndroidUpdateController(
      {required this.platform,
      required this.fetch,
      required this.installedVersion,
      required this.bucket,
      DateTime Function()? now})
      : now = now ?? DateTime.now;
  final AndroidUpdatePlatform platform;
  final Future<PlatformConfig> Function() fetch;
  final Future<String> Function() installedVersion;
  final int bucket;
  final DateTime Function() now;
  AndroidUpdatePhase phase = AndroidUpdatePhase.idle;
  AndroidUpdatePackage? package;
  bool force = false;
  int bytes = 0, total = 0;
  String? _verifiedKey;
  DateTime _nextCheck = DateTime.fromMillisecondsSinceEpoch(0);
  int _failures = 0;
  Future<void>? _pending;
  bool _disposed = false;
  bool get ready => phase == AndroidUpdatePhase.ready && package != null;
  void _publish() {
    if (!_disposed) notifyListeners();
  }

  Future<void> tick({bool refresh = false}) =>
      _pending ??= _tick(refresh).whenComplete(() => _pending = null);

  Future<void> _policy() async {
    final config = await fetch();
    final installed = await installedVersion();
    final release = config.android;
    final mandatory = release.minimum.isNotEmpty &&
        compareAppVersions(installed, release.minimum) < 0;
    final candidate = AndroidUpdatePackage(release);
    final currentBuild = int.tryParse(installed.split('+').last) ?? 0;
    final offered = compareAppVersions(installed, release.latest) < 0 &&
        (mandatory || bucket < release.grayRatio);
    if (offered && !candidate.valid) {
      await platform.clear();
      package = null;
      _verifiedKey = null;
      force = false;
      throw StateError('Incomplete APK metadata');
    }
    final eligible = candidate.valid &&
        release.versionCode > currentBuild &&
        compareAppVersions(installed, release.latest) < 0 &&
        (mandatory || bucket < release.grayRatio);
    if (!eligible) {
      await platform.clear();
      package = null;
      _verifiedKey = null;
      force = false;
      phase = AndroidUpdatePhase.idle;
    } else {
      if (package?.key != candidate.key) {
        _verifiedKey = null;
        phase = AndroidUpdatePhase.downloading;
      }
      package = candidate;
      force = mandatory;
      await platform.enqueue(candidate);
    }
    _nextCheck = now().add(const Duration(minutes: 15));
  }

  Future<void> _tick(bool refresh) async {
    if (_disposed) return;
    if (!refresh &&
        phase == AndroidUpdatePhase.retry &&
        now().isBefore(_nextCheck)) {
      return;
    }
    try {
      if (refresh || !now().isBefore(_nextCheck)) await _policy();
      final target = package;
      if (target == null) {
        _failures = 0;
        _publish();
        return;
      }
      final status = await platform.status();
      bytes = status.bytes;
      total = status.total;
      if (status.state == 'failed' || status.state == 'missing') {
        await platform.clear();
        _verifiedKey = null;
        throw StateError('download unavailable');
      }
      if (status.state == 'complete') {
        if (_verifiedKey != target.key) {
          phase = AndroidUpdatePhase.verifying;
          _publish();
          try {
            await platform.verify(target);
          } catch (_) {
            await platform.clear();
            rethrow;
          }
          // Re-read policy after downloading. Withdrawn or replaced releases
          // must not present a stale mandatory prompt.
          await _policy();
          if (package?.key != target.key) {
            _publish();
            return;
          }
          _verifiedKey = target.key;
        }
        phase = AndroidUpdatePhase.ready;
      } else {
        phase = AndroidUpdatePhase.downloading;
      }
      _failures = 0;
    } catch (_) {
      phase = AndroidUpdatePhase.retry;
      _failures = (_failures + 1).clamp(1, 6);
      _nextCheck = now()
          .add(Duration(seconds: (30 * (1 << (_failures - 1))).clamp(30, 900)));
    }
    _publish();
  }

  /// Revalidate policy and APK on every install attempt, including return from
  /// Android's permission screen. A cancelled installer keeps the cached APK.
  Future<bool> install(String expectedKey) async {
    if (_pending != null) await _pending;
    await tick(refresh: true);
    if (!ready || package!.key != expectedKey) return false;
    if (!await platform.canInstall()) {
      await platform.requestPermission();
      return false;
    }
    await platform.install(package!);
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
