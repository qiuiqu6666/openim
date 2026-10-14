import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/platform_config_service.dart';
import 'package:openim/pages/mine/settings/update/android/android_update_controller.dart';
import 'package:openim/pages/mine/settings/update/android/android_update_package.dart';
import 'package:openim/pages/mine/settings/update/android/android_update_platform.dart';

PlatformConfig release(
        {String minimum = '3.0.1+2',
        int ratio = 100,
        String hash = '',
        int build = 3,
        String? link,
        bool metadata = true}) =>
    PlatformConfig({
      'android': {
        'latestVersion': '3.0.1+$build',
        'minVersion': minimum,
        'grayRatio': ratio,
        'downloadLink': link ?? 'https://example.com/app.apk',
        if (metadata) ...{
          'packageSha256': hash.isEmpty ? List.filled(64, 'a').join() : hash,
          'packageSize': '1024',
          'versionCode': build,
        },
      },
    });

class FakePlatform implements AndroidUpdatePlatform {
  String state = 'missing';
  String? key;
  int downloads = 0,
      verifications = 0,
      installations = 0,
      clears = 0,
      permissions = 0;
  bool verifyFails = false, allowed = true;
  Completer<void>? verification;
  @override
  Future<void> enqueue(AndroidUpdatePackage package) async {
    if (key != package.key || state == 'missing') {
      downloads++;
      key = package.key;
      state = 'downloading';
    }
  }

  @override
  Future<AndroidDownloadStatus> status() async =>
      AndroidDownloadStatus(state, bytes: 512, total: 1024);
  @override
  Future<void> verify(AndroidUpdatePackage package) async {
    verifications++;
    if (verification != null) await verification!.future;
    if (verifyFails) throw StateError('invalid signature');
  }

  @override
  Future<void> clear() async {
    clears++;
    state = 'missing';
    key = null;
  }

  @override
  Future<bool> canInstall() async => allowed;
  @override
  Future<void> requestPermission() async {
    permissions++;
  }

  @override
  Future<void> install(AndroidUpdatePackage package) async {
    installations++;
  }
}

void main() {
  late FakePlatform native;
  late PlatformConfig config;
  late AndroidUpdateController c;
  late DateTime clock;
  var installed = '3.0.1+1';
  var offline = false;
  var requests = 0;
  setUp(() {
    native = FakePlatform();
    config = release();
    clock = DateTime(2026);
    offline = false;
    requests = 0;
    installed = '3.0.1+1';
    c = AndroidUpdateController(
        platform: native,
        bucket: 50,
        installedVersion: () async => installed,
        now: () => clock,
        fetch: () async {
          requests++;
          if (offline) throw StateError('offline');
          return config;
        });
  });
  tearDown(() => c.dispose());
  Future<void> complete() async {
    await c.tick();
    native.state = 'complete';
    await c.tick();
  }

  test(
      'mandatory release ignores gray ratio but does not become ready while downloading',
      () async {
    config = release(ratio: 0);
    await c.tick();
    expect(c.force, true);
    expect(c.ready, false);
    expect(c.phase, AndroidUpdatePhase.downloading);
    expect(native.downloads, 1);
  });
  test('ordinary release outside rollout does not download', () async {
    config = release(minimum: '', ratio: 20);
    await c.tick();
    expect(native.downloads, 0);
    expect(c.ready, false);
  });
  test('verification must finish before ready and rechecks policy', () async {
    await c.tick();
    native.state = 'complete';
    native.verification = Completer<void>();
    final pending = c.tick();
    await Future<void>.delayed(Duration.zero);
    expect(c.phase, AndroidUpdatePhase.verifying);
    expect(c.ready, false);
    native.verification!.complete();
    await pending;
    expect(c.ready, true);
    expect(requests, 2);
  });
  test('signature or checksum failure clears APK and leaves app usable',
      () async {
    native.verifyFails = true;
    await complete();
    expect(c.phase, AndroidUpdatePhase.retry);
    expect(c.ready, false);
    expect(native.state, 'missing');
    expect(native.installations, 0);
  });
  test('failed checks back off, never become ready, and manual retry recovers',
      () async {
    offline = true;
    await c.tick();
    await c.tick();
    expect(requests, 1);
    expect(c.ready, false);
    clock = clock.add(const Duration(seconds: 31));
    await c.tick();
    expect(requests, 2);
    offline = false;
    await c.tick(refresh: true);
    expect(c.phase, AndroidUpdatePhase.downloading);
  });
  test('download failure retries without presenting a mandatory dialog',
      () async {
    await c.tick();
    native.state = 'failed';
    await c.tick();
    expect(c.ready, false);
    expect(native.downloads, 1);
    clock = clock.add(const Duration(seconds: 31));
    await c.tick();
    expect(native.downloads, 2);
    expect(c.phase, AndroidUpdatePhase.downloading);
  });
  test('withdrawn release during verification never prompts', () async {
    await c.tick();
    native.state = 'complete';
    config = release(minimum: '', ratio: 0);
    await c.tick();
    expect(c.ready, false);
    expect(c.package, null);
  });
  test(
      'changed package during verification starts replacement instead of old prompt',
      () async {
    await c.tick();
    native.state = 'complete';
    config = release(build: 4);
    await c.tick();
    expect(c.ready, false);
    expect(c.package!.release.versionCode, 4);
    expect(native.downloads, 2);
  });
  test('lowered minimum turns a ready mandatory release into optional',
      () async {
    await complete();
    config = release(minimum: '');
    await c.tick(refresh: true);
    expect(c.ready, true);
    expect(c.force, false);
    expect(native.downloads, 1);
  });
  test('cancelled installer retains APK and can install again', () async {
    await complete();
    final key = c.package!.key;
    expect(await c.install(key), true);
    expect(c.ready, true);
    expect(await c.install(key), true);
    expect(native.installations, 2);
    expect(native.downloads, 1);
  });
  test('permission return can resume install and still rechecks withdrawal',
      () async {
    await complete();
    final key = c.package!.key;
    native.allowed = false;
    expect(await c.install(key), false);
    expect(native.permissions, 1);
    native.allowed = true;
    config = release(minimum: '', ratio: 0);
    expect(await c.install(key), false);
    expect(native.installations, 0);
  });
  test('actual installed version completes update and clears cache', () async {
    await complete();
    installed = '3.0.1+3';
    await c.tick(refresh: true);
    expect(c.phase, AndroidUpdatePhase.idle);
    expect(c.package, null);
    expect(native.state, 'missing');
  });
  test('process restart adopts completed native task without another download',
      () async {
    final pkg = AndroidUpdatePackage(config.android);
    native.key = pkg.key;
    native.state = 'complete';
    await c.tick();
    expect(c.ready, true);
    expect(native.downloads, 0);
    expect(native.verifications, 1);
  });
  test('incomplete manifest and non HTTPS links never download or block',
      () async {
    config = release(metadata: false);
    await c.tick();
    expect(c.phase, AndroidUpdatePhase.retry);
    expect(native.downloads, 0);
    config = release(link: 'http://example.com/app.apk');
    await c.tick(refresh: true);
    expect(c.ready, false);
    expect(native.downloads, 0);
  });
  test('concurrent entry checks share request and download', () async {
    await Future.wait([c.tick(), c.tick(), c.tick()]);
    expect(requests, 1);
    expect(native.downloads, 1);
  });
  test('string protobuf size is supported and inconsistent build is rejected',
      () {
    final pkg = AndroidUpdatePackage(config.android);
    expect(pkg.release.packageSize, 1024);
    expect(pkg.valid, true);
    final bad = PlatformRelease({
      'latestVersion': '3.0.1+8',
      'versionCode': 9,
      'packageSha256': List.filled(64, 'b').join(),
      'packageSize': 1024,
      'downloadLink': 'https://example.com/app.apk'
    });
    expect(AndroidUpdatePackage(bad).valid, false);
  });
}
