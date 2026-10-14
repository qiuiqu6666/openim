import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
// ControlsView exposes the live package's Room type.
// ignore: depend_on_referenced_packages
import 'package:livekit_client/livekit_client.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/src/models/call_types.dart';
import 'package:openim_live/src/pages/single/widgets/controls.dart';
import 'package:openim_live/src/widgets/call_compact_surface.dart';
import 'package:openim_live/src/widgets/incoming_call/incoming_call_view.dart';

import '../../../support/contact_remark_fixture.dart';

Widget _host(Widget child, Brightness brightness) => ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
          translations: TranslationService(),
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          theme: ThemeData(brightness: brightness),
          home: Scaffold(body: child),
        ));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ContactRemarkFixture contacts;
  setUp(() {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    contacts = ContactRemarkFixture();
    Get.put<ContactRemarkSource>(contacts);
  });
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    for (final surface in ['outgoing', 'incoming', 'connected', 'pip']) {
      testWidgets('$surface call shows current remark in ${brightness.name}',
          (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        contacts.remarks['peer'] = '我的备注⬇️';
        final profile =
            UserInfo(userID: 'peer', nickname: '公开昵称', remark: '过期备注');
        final Widget child = switch (surface) {
          'incoming' => IncomingCallView(
              userID: 'peer',
              userInfo: profile,
              callType: CallType.audio,
              onAccept: () {},
              onReject: () {}),
          'pip' => CallCompactSurface(
              userInfo: profile,
              state: CallState.calling,
              duration: 12,
              systemPip: true),
          _ => ControlsView(
              userID: 'peer',
              userInfo: profile,
              initState: surface == 'connected'
                  ? CallState.calling
                  : CallState.connecting,
              connected: surface == 'connected',
              callType: CallType.audio,
              callStateStream: const Stream<CallState>.empty(),
              roomDidUpdateStream: const Stream<Room>.empty(),
              onCancel: () {},
              onHangUp: (_) {}),
        };
        await tester.pumpWidget(_host(child, brightness));
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('我的备注⬇️'), findsOneWidget);
        expect(find.text('公开昵称'), findsNothing);
        expect(find.text('过期备注'), findsNothing);
        contacts.remarks['peer'] = '新备注';
        await tester.pump();
        expect(find.text('新备注'), findsOneWidget);
        contacts.remarks.remove('peer');
        await tester.pump();
        expect(find.text('公开昵称'), findsOneWidget);
        expect(profile.nickname, '公开昵称');
        expect(profile.remark, '过期备注');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
