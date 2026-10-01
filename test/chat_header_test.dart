import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  testWidgets('single chat header shows back, avatar and name in order',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        home: Scaffold(
          appBar: TitleBar.chat(
            title: '很长的好友昵称需要在狭窄屏幕上截断',
            isSingleChat: true,
            presenceText: '在线',
            isOnline: true,
            onClickCallBtn: () {},
            onClickVideoBtn: () {},
            onClickMoreBtn: () {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final back = find.byType(TitleBar).first;
    final avatar = find.byType(AvatarView);
    final name = find.text('很长的好友昵称需要在狭窄屏幕上截断');
    expect(avatar, findsOneWidget);
    expect(name, findsOneWidget);
    expect(find.text('在线'), findsOneWidget);
    expect(find.byTooltip(StrRes.callVoice), findsOneWidget);
    expect(find.byTooltip(StrRes.callVideo), findsOneWidget);
    expect(tester.getTopLeft(avatar).dx, lessThan(tester.getTopLeft(name).dx));
    expect(tester.getTopLeft(back).dx, lessThan(tester.getTopLeft(avatar).dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('group chat header keeps its title without a user avatar',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        home: Scaffold(
          appBar: TitleBar.chat(title: '群聊', member: '(10)'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(AvatarView), findsNothing);
    expect(find.text('群聊'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('single chat voice and video buttons invoke separate actions',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var audioCalls = 0;
    var videoCalls = 0;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        home: Scaffold(
          appBar: TitleBar.chat(
            title: '好友',
            isSingleChat: true,
            onClickCallBtn: () => audioCalls++,
            onClickVideoBtn: () => videoCalls++,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(StrRes.callVideo));
    expect(videoCalls, 1);
    expect(audioCalls, 0);
    await tester.tap(find.byTooltip(StrRes.callVoice));
    expect(videoCalls, 1);
    expect(audioCalls, 1);
  });
}
