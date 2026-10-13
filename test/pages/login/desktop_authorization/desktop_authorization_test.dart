import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/pages/login/desktop_authorization/data/desktop_authorization_service.dart';
import 'package:openim/pages/login/desktop_authorization/data/desktop_devices.dart';
import 'package:openim/pages/login/desktop_authorization/desktop_login_confirm_page.dart';
import 'package:openim/pages/login/desktop_authorization/widgets/desktop_authorization_layout.dart';

class _Service implements DesktopAuthorizationService {
  int confirms = 0;
  DesktopAuthorizationState state = DesktopAuthorizationState.scanned;
  DesktopAuthorization get value => DesktopAuthorization(
      deviceName: '我的电脑',
      platform: 'Windows',
      code: '482 619',
      region: '新加坡',
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      state: state);
  @override
  Future<DesktopAuthorization> scan(String id) async => value;
  @override
  Future<DesktopAuthorization> confirm(String id,
      {String verificationCode = ''}) async {
    confirms++;
    state = DesktopAuthorizationState.approved;
    return value;
  }

  @override
  Future<DesktopAuthorization> status(String id) async => value;
  @override
  Future<void> cancel(String id) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson(
        {'userID': 'user-a', 'chatToken': 'test-chat', 'imToken': 'test-im'}));
  });

  test('login QR rejects URLs, old contract, and extra credential fields', () {
    final id = 'a' * 43;
    final payload = {'type': '99chat_desktop_login', 'v': 2, 'requestId': id};
    expect(parseDesktopLoginQr('99chat-login:v1:$id'), id);
    expect(parseDesktopLoginQr(jsonEncode(payload)), isNull);
    expect(parseDesktopLoginQr(jsonEncode({...payload, 'token': 'secret'})),
        isNull);
    expect(parseDesktopLoginQr(jsonEncode({...payload, 'v': 1})), isNull);
    expect(
        parseDesktopLoginQr('https://example.com/login?token=secret'), isNull);
    expect(parseDesktopLoginQr('{}'), isNull);
  });

  test('banner excludes historical records, phones, duplicates, current device',
      () {
    final rows = [
      {'deviceID': 'pc', 'platform': 'windows', 'online': true},
      {'deviceID': 'pc', 'platform': 'windows', 'online': true},
      {'deviceID': 'old', 'platform': 'macos', 'online': false},
      {'deviceID': 'phone', 'platform': 'ios', 'online': true},
      {'deviceID': 'current', 'platform': 'windows', 'online': true},
    ];
    expect(onlineDesktopDevices(rows, 'current').map((d) => d.id), ['pc']);
  });

  testWidgets('unavailable backend never offers approval or fake success',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: DesktopLoginConfirmPage(
            requestId: 'test',
            service: UnavailableDesktopAuthorizationService())));
    await tester.pumpAndSettle();
    expect(find.text('扫码登录暂不可用，请稍后再试'), findsOneWidget);
    expect(find.text('确认登录'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('approval waits for activation; double taps cannot confirm twice',
      (tester) async {
    final service = _Service();
    await tester.pumpWidget(MaterialApp(
        home: DesktopLoginConfirmPage(requestId: 'test', service: service)));
    await tester.pumpAndSettle();
    expect(find.text('482 619'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '482619');
    await tester.tap(find.text('确认登录'));
    await tester.tap(find.text('确认登录'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(service.confirms, 1);
    expect(find.text('已确认，请在电脑上继续'), findsOneWidget);
    expect(find.text('Windows已登录'), findsNothing);
    service.state = DesktopAuthorizationState.active;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Windows已登录'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('account switch prevents confirmation', (tester) async {
    final service = _Service();
    await tester.pumpWidget(MaterialApp(
        home: DesktopLoginConfirmPage(requestId: 'test', service: service)));
    await tester.pumpAndSettle();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson(
        {'userID': 'user-b', 'chatToken': 'other', 'imToken': 'other'}));
    await tester.tap(find.text('确认登录'));
    expect(service.confirms, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('登录状态已变化，请重新扫码'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final brightness in Brightness.values) {
    testWidgets('reference layout ${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: RepaintBoundary(
              key: const Key('capture'),
              child: DesktopAuthorizationLayout(
                  title: '登录 Windows 版 99Chat',
                  onClose: () {},
                  action: '确认登录',
                  onAction: () {},
                  detail: const Text(
                      '我的电脑\n核对码 482 619\n请核对电脑上的数字，仅登录你本人正在使用的设备',
                      textAlign: TextAlign.center)))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(find.byKey(const Key('capture')),
          matchesGoldenFile('goldens/confirm_${brightness.name}.png'));
    });
  }
}
