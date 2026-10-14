import 'package:flutter/foundation.dart';
import '../../../../../services/platform_config_service.dart';
import 'android_update_package.dart';
import 'android_update_platform.dart';

enum AndroidUpdatePhase {
  idle,
  checking,
  downloading,
  verifying,
  ready,
  external,
  retry
}

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
  PlatformRelease? externalRelease;
  bool force = false;
  int bytes = 0, total = 0;
  String fallbackURL = '';
  String? _verifiedKey;
  DateTime _nextCheck = DateTime.fromMillisecondsSinceEpoch(0);
  int _failures = 0;
  Future<void>? _pending;
  bool _disposed = false;
  bool get ready => phase == AndroidUpdatePhase.ready && package != null;
  bool get external =>
      phase == AndroidUpdatePhase.external && externalRelease != null;
  bool get promptReady => ready || external;
  bool get retrying => _failures > 0;
  PlatformRelease? get promptRelease =>
      external ? externalRelease : package?.release;
  String? get promptKey => external
      ? 'external:${externalRelease!.latest}:${externalRelease!.minimum}:${externalRelease!.downloadURL}'
      : package?.key;
  void _publish() {
    if (!_disposed) notifyListeners();
  }

  Future<void> restoreRequiredWebsite(PlatformRelease release) async {
    if (release.downloadLink.isNotEmpty ||
        release.minimum.isEmpty ||
        compareAppVersions(await installedVersion(), release.minimum) >= 0) {
      return;
    }
    externalRelease = release;
    force = true;
    phase = AndroidUpdatePhase.external;
  }

  Future<void> tick({bool refresh = false}) {
    final pending = _pending;
    if (pending != null) {
      return refresh ? pending.then((_) => tick(refresh: true)) : pending;
    }
    return _pending = _tick(refresh).whenComplete(() => _pending = null);
  }

  Future<void> _policy() async {
    final config = await fetch();
    final installed = await installedVersion();
    final release = config.android;
    fallbackURL = release.downloadURL;
    final mandatory = release.minimum.isNotEmpty &&
        compareAppVersions(installed, release.minimum) < 0;
    final candidate = AndroidUpdatePackage(release);
    final currentBuild = int.tryParse(installed.split('+').last) ?? 0;
    final offered = mandatory ||
        (compareAppVersions(installed, release.latest) < 0 &&
            bucket < release.grayRatio);
    if (offered && release.downloadLink.isEmpty) {
      // A confirmed legacy minimum remains enforced even if its website is
      // missing or a later refresh fails. Opening a browser never satisfies it.
      externalRelease = release;
      package = null;
      _verifiedKey = null;
      force = mandatory;
      phase = AndroidUpdatePhase.external;
      await platform.clear();
      _nextCheck = now().add(const Duration(minutes: 15));
      _failures = 0;
      return;
    }
    externalRelease = null;
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
    _failures = 0;
  }

  Future<void> _tick(bool refresh) async {
    if (_disposed) return;
    if (!refresh &&
        (phase == AndroidUpdatePhase.retry || retrying) &&
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
        _verifiedKey = null;
        phase = AndroidUpdatePhase.downloading;
      }
      _failures = 0;
    } catch (_) {
      phase = externalRelease != null && force
          ? AndroidUpdatePhase.external
          : AndroidUpdatePhase.retry;
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
    try {
      await platform.install(package!);
    } catch (_) {
      // An installer/verification failure must not leave an unusable APK as
      // a permanent mandatory gate. Keep the transfer, reverify on retry.
      _verifiedKey = null;
      phase = AndroidUpdatePhase.retry;
      _nextCheck = now().add(const Duration(seconds: 30));
      _publish();
      rethrow;
    }
    return true;
  }

  Future<void> openExternal(Future<bool> Function(Uri) open) async {
    await tick(refresh: true);
    if (!external) return; // Policy withdrawn, installed, or switched to APK.
    if (retrying) throw StateError('Update configuration unavailable');
    final uri = Uri.tryParse(externalRelease!.downloadURL);
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        !await open(uri)) {
      throw StateError('Update website unavailable');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
