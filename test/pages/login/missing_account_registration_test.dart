import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/login/login_logic.dart';
import 'package:openim/routes/app_pages.dart';

import 'device_verification/device_verification_login_fixture.dart';

void main() {
  for (final type in LoginType.values) {
    for (final code in [20002, 20001]) {
      testWidgets('$type error $code registration routing', (tester) async {
        final f = DeviceLoginFixture();
        Map? registration;
        await f.initialize(tester, additionalPages: [
          GetPage(
              name: AppRoutes.register,
              page: () {
                registration = Get.arguments as Map;
                return const Scaffold(body: Text('registration ready'));
              }),
        ]);
        addTearDown(() => f.dispose(tester));
        f.logic.selectLoginType(type);
        f.logic.areaCode.value = '+855';
        final account = type == LoginType.email
            ? 'new@example.com'
            : type == LoginType.phone
                ? '966464014'
                : '@missing';
        f.logic.phoneCtrl.text = account;
        f.logic.pwdCtrl.text = 'password123';
        await tester.runAsync(() async {
          f.pendingLogin = f.logic.login();
          await waitForAuth(() => f.adapter.requests.isNotEmpty);
          f.adapter.reply(0, code: code);
          if (code != 20002) await f.pendingLogin;
          if (code == 20002) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        await tester.pumpAndSettle();
        if (code == 20002) {
          expect(registration, isNull);
          expect(find.text('registration ready'), findsNothing);
          expect(
              find.text(type == LoginType.email ? '邮箱未注册，请先注册' : '账号不存在，请先注册'),
              findsOneWidget);
          await tester.tap(find.text('确定'));
          await tester.pumpAndSettle();
          await tester.runAsync(() async => await f.pendingLogin);
          await tester.pumpAndSettle();
          expect(find.text('registration ready'), findsOneWidget);
          expect(registration, {
            'registrationEmail': type == LoginType.email,
            'registrationAccount': type == LoginType.account ? '' : account,
            'registrationAreaCode': '+855',
          });
          expect(f.logic.formError, isNull);
        } else {
          expect(registration, isNull);
          expect(f.logic.formError, isNotNull);
        }
        f.expectNoSession();
      });
    }
  }
}
