import 'package:openim/pages/login/desktop_authorization/widgets/desktop_login_device_details.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/login/desktop_authorization/widgets/desktop_authorization_layout.dart';

void main() {
  final directory = Platform.environment['DESKTOP_LOGIN_PREVIEW'];
  testWidgets('export desktop authorization pages', (tester) async {
    await tester.runAsync(() async {
      final font = File('C:/Windows/Fonts/msyh.ttc');
      await (FontLoader('DesktopPreview')
            ..addFont(
                Future.value(ByteData.sublistView(await font.readAsBytes()))))
          .load();
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
      await Directory(directory!).create(recursive: true);
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final dark in [false, true]) {
      for (final loggedIn in [false, true]) {
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(
                fontFamily: 'DesktopPreview',
                brightness: dark ? Brightness.dark : Brightness.light),
            home: RepaintBoundary(
                key: const Key('preview'),
                child: DesktopAuthorizationLayout(
                    title: loggedIn ? 'Windows已登录' : '登录 Windows 版 99Chat',
                    loggedIn: loggedIn,
                    onClose: () {},
                    action: loggedIn ? '退出该设备' : '确认登录',
                    onAction: () {},
                    detail: loggedIn
                        ? const Text('我的电脑')
                        : const DesktopLoginDeviceDetails(
                            deviceName: '我的电脑',
                            platform: 'Windows',
                            code: '482 619')))));
        await tester.runAsync(() => precacheImage(
            AssetImage(
                'lib/pages/login/desktop_authorization/assets/${loggedIn ? 'jingyin' : 'diann'}.png'),
            tester.element(find.byKey(const Key('preview')))));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 500));
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('preview')));
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
                  '$directory/${loggedIn ? 'devices' : 'confirm'}-${dark ? 'dark' : 'light'}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
  }, skip: directory == null);
}
