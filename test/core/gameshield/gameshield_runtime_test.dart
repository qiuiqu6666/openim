import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gameshield_bridge/gameshield_bridge.dart';
import 'package:openim/core/gameshield/gameshield_failure.dart';
import 'package:openim/core/gameshield/gameshield_runtime.dart';
import 'package:openim/core/gameshield/gameshield_settings.dart';
import 'package:openim/core/server_nodes/node_endpoint.dart';
import 'package:openim/core/server_nodes/startup_node_selection.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

const settings = GameShieldSettings(
    enabled: true,
    licenseToken: 'GS2.test-credential',
    auth: GameShieldRule('auth'),
    imApi: GameShieldRule('api'),
    imWs: GameShieldRule('ws'),
    customerService: GameShieldRule('customer'));
const endpoints = [
  GameShieldEndpoint(
      appId: 'auth',
      groupName: 'chat',
      host: '127.0.0.1',
      port: 20008,
      protocol: 'tcp'),
  GameShieldEndpoint(
      appId: 'api',
      groupName: 'im',
      host: '127.0.0.1',
      port: 20002,
      protocol: 'TCP'),
  GameShieldEndpoint(
      appId: 'ws',
      groupName: 'im',
      host: '127.0.0.1',
      port: 20001,
      protocol: 'tcp'),
  GameShieldEndpoint(
      appId: 'customer',
      groupName: '客服服务1',
      host: '127.0.0.1',
      port: 28815,
      protocol: 'tcp'),
];

class Native implements GameShieldPlatform {
  int starts = 0, stops = 0;
  Completer<void>? gate;
  Object? failure;
  GameShieldSnapshot result = const GameShieldSnapshot(
      ready: true,
      sdkVersion: '60.1.10',
      activeTunnels: 0,
      endpoints: endpoints);
  @override
  Future<GameShieldSnapshot> start(String token) async {
    starts++;
    expect(token, settings.licenseToken);
    await gate?.future;
    if (failure case final error?) throw error;
    return result;
  }

  @override
  Future<GameShieldSnapshot> status() async => result;
  @override
  Future<void> stop() async {
    stops++;
  }
}

Matcher failure(GameShieldFailureKind kind) =>
    isA<GameShieldFailure>().having((value) => value.kind, 'kind', kind);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Native native;
  late GameShieldRuntime runtime;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    Config.useRuntimeNetworkRoute(null);
    StartupNodeSelection.last = null;
    native = Native();
    runtime = GameShieldRuntime(
        settings: settings, platform: native, supportsPlatform: () => true);
  });
  tearDown(() {
    Config.useRuntimeNetworkRoute(null);
    StartupNodeSelection.last = null;
  });

  test('disabled preparation does not contact native SDK or change endpoints',
      () async {
    final disabled = GameShieldRuntime(
        platform: native, settings: const GameShieldSettings());
    await disabled.prepare();
    expect(native.starts, 0);
    expect(Config.imApiUrl, NodeEndpoint.direct.imApi);
  });
  test(
      'startup maps all four services without persisting local ports or credentials',
      () async {
    await DataSp.putServerConfig({'logLevel': '4'});
    final stored = Map.of(DataSp.getServerConfig()!);
    await runtime.prepare();
    expect(Config.appAuthUrl, 'http://127.0.0.1:20008');
    expect(Config.imApiUrl, 'http://127.0.0.1:20002');
    expect(Config.imWsUrl, 'ws://127.0.0.1:20001');
    expect(Config.customerServiceForwardUrl, 'http://127.0.0.1:28815');
    expect(DataSp.getServerConfig(), stored);
    expect(StartupNodeSelection.last!.selected.imWs, Config.imWsUrl);
    await runtime.prepare();
    expect(native.starts, 1);
    await runtime.close();
    expect(native.stops, 1);
    expect(Config.imApiUrl, NodeEndpoint.direct.imApi);
    expect(Config.customerServiceForwardUrl, isNull);
  });
  test(
      'concurrent preparations share one native start and publish no partial route',
      () async {
    native.gate = Completer<void>();
    final pending = runtime.prepare();
    expect(identical(pending, runtime.prepare()), isTrue);
    expect(native.starts, 1);
    expect(Config.imApiUrl, NodeEndpoint.direct.imApi);
    native.gate!.complete();
    await pending;
    expect(Config.imApiUrl, 'http://127.0.0.1:20002');
    await runtime.close();
  });
  test('incomplete settings fail before any native operation', () async {
    final invalid = GameShieldRuntime(
        settings: const GameShieldSettings(enabled: true),
        platform: native,
        supportsPlatform: () => true);
    await expectLater(invalid.prepare(),
        throwsA(failure(GameShieldFailureKind.configuration)));
    expect(native.starts, 0);
  });
  test('unsupported platforms do not try to initialize the mobile SDK',
      () async {
    final unsupported = GameShieldRuntime(
        settings: settings, platform: native, supportsPlatform: () => false);
    await expectLater(unsupported.prepare(),
        throwsA(failure(GameShieldFailureKind.unsupportedPlatform)));
    expect(native.starts, 0);
  });
  test(
      'missing customer service rule cannot silently leave support on direct transport',
      () async {
    final incomplete = GameShieldRuntime(
        settings: GameShieldSettings(
            enabled: true,
            licenseToken: settings.licenseToken,
            auth: settings.auth,
            imApi: settings.imApi,
            imWs: settings.imWs),
        platform: native,
        supportsPlatform: () => true);
    await expectLater(incomplete.prepare(),
        throwsA(failure(GameShieldFailureKind.configuration)));
    expect(native.starts, 0);
  });
  test(
      'custom customer service origin cannot borrow the production forwarding rule',
      () async {
    final custom = GameShieldRuntime(
        settings: GameShieldSettings(
            enabled: true,
            licenseToken: settings.licenseToken,
            auth: settings.auth,
            imApi: settings.imApi,
            imWs: settings.imWs,
            customerService: settings.customerService,
            customerServiceBaseUrl: 'https://support.example'),
        platform: native,
        supportsPlatform: () => true);
    await expectLater(custom.prepare(),
        throwsA(failure(GameShieldFailureKind.configuration)));
    expect(native.starts, 0);
  });
  test('custom deployment cannot inherit production protection rules',
      () async {
    await DataSp.putServerConfig({'authUrl': 'https://custom.example/chat'});
    await expectLater(runtime.prepare(),
        throwsA(failure(GameShieldFailureKind.configuration)));
    expect(native.starts, 0);
    expect(Config.appAuthUrl, 'https://custom.example/chat');
  });
  test('missing native SDK is explicit and never installs a forwarding route',
      () async {
    native.failure = PlatformException(code: 'SDK_UNAVAILABLE');
    await expectLater(runtime.prepare(),
        throwsA(failure(GameShieldFailureKind.unavailableSdk)));
    expect(native.stops, 1);
    expect(Config.imApiUrl, NodeEndpoint.direct.imApi);
    expect(StartupNodeSelection.last, isNull);
  });
  test('native failure cannot expose a token and retry cleans up then restarts',
      () async {
    native.failure =
        PlatformException(code: 'AUTH_FAILED', message: settings.licenseToken);
    Object? caught;
    try {
      await runtime.prepare();
    } catch (error) {
      caught = error;
    }
    expect(caught, failure(GameShieldFailureKind.startFailed));
    expect(caught.toString(), isNot(contains(settings.licenseToken)));
    expect(native.stops, 1);
    native.failure = null;
    await runtime.prepare();
    expect(native.starts, 2);
    await runtime.close();
  });
  test('startup deadline stops a slow native start and reports failure',
      () async {
    native.gate = Completer<void>();
    final slow = GameShieldRuntime(
        settings: settings,
        platform: native,
        supportsPlatform: () => true,
        startupTimeout: const Duration(milliseconds: 5));
    await expectLater(
        slow.prepare(), throwsA(failure(GameShieldFailureKind.startFailed)));
    expect(native.stops, 1);
    expect(Config.imApiUrl, NodeEndpoint.direct.imApi);
    native.gate!.complete();
    await slow.close();
  });
  for (final bad in [
    'notReady',
    'wrongVersion',
    'missingRule',
    'duplicateRule',
    'remoteHost',
    'udp'
  ]) {
    test('rejects $bad snapshot and closes native client', () async {
      var list = endpoints.toList();
      if (bad == 'missingRule') list.removeLast();
      if (bad == 'duplicateRule') list.add(endpoints.last);
      if (bad == 'remoteHost' || bad == 'udp') {
        list[0] = GameShieldEndpoint(
            appId: 'auth',
            groupName: 'chat',
            host: bad == 'remoteHost' ? '192.168.1.1' : '127.0.0.1',
            port: 20008,
            protocol: bad == 'udp' ? 'udp' : 'tcp');
      }
      native.result = GameShieldSnapshot(
          ready: bad != 'notReady',
          sdkVersion: bad == 'wrongVersion' ? '0.0' : '60.1.10',
          activeTunnels: 0,
          endpoints: list);
      await expectLater(runtime.prepare(),
          throwsA(failure(GameShieldFailureKind.invalidEndpoints)));
      expect(native.stops, 1);
      expect(Config.imApiUrl, NodeEndpoint.direct.imApi);
    });
  }
}
