import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  for (final dark in [false, true]) {
    for (final width in [320.0, 375.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('single header keeps presence geometry $dark/$width/$scale',
            (tester) async {
          tester.view.physicalSize = Size(width, 812);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final previousDark = Styles.isDark;
          Styles.isDark = dark;
          addTearDown(() => Styles.isDark = previousDark);
          final semantics = tester.ensureSemantics();
          try {
            final state = ValueNotifier<({String? label, bool online})>(
                (label: null, online: false));
            addTearDown(state.dispose);

            await tester.pumpWidget(ScreenUtilInit(
              designSize: const Size(375, 812),
              builder: (_, __) => GetMaterialApp(
                theme: ThemeData(
                    brightness: dark ? Brightness.dark : Brightness.light),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: ValueListenableBuilder(
                  valueListenable: state,
                  builder: (context, value, _) {
                    final height = TitleBar.chatToolbarHeightFor(context);
                    return Scaffold(
                      appBar: PreferredSize(
                        preferredSize: Size.fromHeight(height),
                        child: TitleBar.chat(
                          toolbarHeight: height,
                          title: '普通好友',
                          isSingleChat: true,
                          presenceText: value.label,
                          isOnline: value.online,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ));
            await tester.pumpAndSettle();
            final title = find.text('普通好友');
            final avatar = find.byType(AvatarView);
            final status = find.byKey(const ValueKey('chat-header-presence'));
            final titlePosition = tester.getTopLeft(title);
            final avatarPosition = tester.getTopLeft(avatar);
            final statusRect = tester.getRect(status);
            expect(statusRect.height, greaterThan(0));
            expect(tester.widget<Text>(status).data, isEmpty);
            if (scale == 1) {
              expect(tester.getSize(find.byType(TitleBar)).height,
                  closeTo(TitleBar.chatToolbarHeight, 0.1));
            }

            const labels = ['在线', '正在输入…', '5分钟前在线'];
            for (final value in <({String? label, bool online})>[
              (label: labels[0], online: true),
              (label: labels[1], online: true),
              (label: labels[2], online: false),
              (label: null, online: false),
            ]) {
              state.value = value;
              await tester.pumpAndSettle();
              expect(tester.getTopLeft(title), titlePosition);
              expect(tester.getTopLeft(avatar), avatarPosition);
              expect(tester.getTopLeft(status), statusRect.topLeft);
              expect(tester.getSize(status).height, statusRect.height);
              final text = tester.widget<Text>(status);
              expect(text.data, value.label ?? '');
              expect(text.style!.fontSize, 11.sp);
              expect(text.style!.color,
                  value.online ? Styles.c_0089FF : Styles.c_8E9AB0);
              final rich = tester.widget<RichText>(
                  find.descendant(of: status, matching: find.byType(RichText)));
              expect(rich.textScaler.scale(11.sp), closeTo(11.sp * scale, 0.1));
              for (final label in labels) {
                final spoken = find.bySemanticsLabel(
                    RegExp(r'(^|\n)' + RegExp.escape(label) + r'($|\n)'));
                expect(
                    spoken, value.label == label ? findsWidgets : findsNothing);
              }
              final headerRect = tester.getRect(find.byType(TitleBar));
              expect(tester.getRect(title).top,
                  greaterThanOrEqualTo(headerRect.top));
              expect(tester.getRect(status).bottom,
                  lessThanOrEqualTo(headerRect.bottom));
              expect(tester.takeException(), isNull);
            }
          } finally {
            semantics.dispose();
          }
        });
      }
    }
  }

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

  testWidgets('group chat header shares avatar layout and opens group settings',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var settings = 0;
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        home: Scaffold(
          appBar: TitleBar.chat(
              title: '群聊', member: '(10)', onClickMoreBtn: () => settings++),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(AvatarView), findsOneWidget);
    expect(tester.widget<AvatarView>(find.byType(AvatarView)).isGroup, isTrue);
    expect(find.text('(10)'), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
    await tester.tap(find.text('群聊'));
    expect(settings, 1);
    expect(find.text('群聊'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('group header fits scaled members and keeps actions $dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previousDark = Styles.isDark;
      Styles.isDark = dark;
      addTearDown(() => Styles.isDark = previousDark);
      final semantics = tester.ensureSemantics();
      try {
        var settings = 0;
        var calls = 0;
        await tester.pumpWidget(ScreenUtilInit(
          designSize: const Size(375, 812),
          builder: (_, __) => GetMaterialApp(
            theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Builder(builder: (context) {
              final height =
                  TitleBar.chatToolbarHeightFor(context, isSingleChat: false);
              return Scaffold(
                appBar: PreferredSize(
                  preferredSize: Size.fromHeight(height),
                  child: TitleBar.chat(
                    toolbarHeight: height,
                    title: '群聊',
                    member: '(10)',
                    onClickMoreBtn: () => settings++,
                    onClickCallBtn: () => calls++,
                  ),
                ),
              );
            }),
          ),
        ));
        await tester.pumpAndSettle();
        final headerRect = tester.getRect(find.byType(TitleBar));
        final members = find.text('(10)');
        expect(tester.getRect(find.text('群聊')).top,
            greaterThanOrEqualTo(headerRect.top));
        expect(tester.getRect(members).bottom,
            lessThanOrEqualTo(headerRect.bottom));
        expect(tester.widget<Text>(members).strutStyle, isNull);
        expect(
            find.bySemanticsLabel(RegExp(r'(^|\n)\(10\)($|\n)')), findsWidgets);
        expect(
            find.byKey(const ValueKey('chat-header-presence')), findsNothing);
        expect(
            tester.widget<AvatarView>(find.byType(AvatarView)).isGroup, isTrue);
        expect(find.byTooltip(StrRes.callVideo), findsNothing);
        await tester.tap(find.text('群聊'));
        expect(settings, 1);
        await tester.tap(find.byTooltip(StrRes.callVoice));
        expect(calls, 1);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

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
