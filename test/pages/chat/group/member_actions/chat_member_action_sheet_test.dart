import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/group/member_actions/chat_member_action_policy.dart';
import 'package:openim/pages/chat/group/member_actions/chat_member_action_sheet.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  setUp(() {
    Get.addTranslations(TranslationService().keys);
    Get.locale = const Locale('zh', 'CN');
  });
  tearDown(() {
    Styles.isDark = false;
    Get.reset();
  });

  for (final brightness in Brightness.values) {
    for (final (size, textScale) in [
      (const Size(320, 640), 1.0),
      (const Size(375, 812), 3.0),
      (const Size(812, 375), 2.0),
    ]) {
      testWidgets(
        'member actions fit $brightness at $size and text scale $textScale',
        (tester) async {
          ChatMemberAction? selected;
          await _pumpHost(
            tester,
            brightness: brightness,
            size: size,
            textScale: textScale,
            onOpen: (context) async {
              selected = await showChatMemberActionSheet(
                context,
                actions: const [
                  ChatMemberAction.mention,
                  ChatMemberAction.exclusiveRedPacket,
                  ChatMemberAction.unmute,
                  ChatMemberAction.remove,
                ],
                displayName: '群成员',
              );
            },
          );
          await tester.tap(find.text('打开'));
          await tester.pumpAndSettle();

          expect(find.text('@对方'), findsOneWidget);
          expect(find.text('专属红包'), findsOneWidget);
          expect(find.text('解除禁言'), findsOneWidget);
          expect(find.text('禁言'), findsNothing);
          expect(find.text('移除群聊'), findsOneWidget);
          expect(find.text('取消'), findsOneWidget);
          expect(find.byType(BottomSheetView), findsOneWidget);
          expect(
            tester.widget<Text>(find.text('移除群聊')).style!.color,
            Theme.of(tester.element(find.text('移除群聊'))).colorScheme.error,
          );
          expect(
            tester.widget<Text>(find.text('@对方')).style!.color,
            Styles.c_0C1C33,
          );
          final surface = tester.widget<Ink>(
            find.ancestor(of: find.text('@对方'), matching: find.byType(Ink)),
          );
          expect((surface.decoration as BoxDecoration).color, Styles.c_FFFFFF);
          for (final label in ['@对方', '专属红包', '解除禁言', '移除群聊', '取消']) {
            final target = find.ancestor(
              of: find.text(label),
              matching: find.byType(InkWell),
            );
            expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
          }
          expect(tester.takeException(), isNull);

          await tester.tap(find.text('解除禁言'));
          await tester.pumpAndSettle();
          expect(selected, ChatMemberAction.unmute);
          expect(find.byType(BottomSheetView), findsNothing);
        },
      );
    }
  }

  testWidgets('only allowed options appear and cancellation has no action',
      (tester) async {
    ChatMemberAction? selected = ChatMemberAction.remove;
    await _pumpHost(tester, onOpen: (context) async {
      selected = await showChatMemberActionSheet(
        context,
        actions: const [
          ChatMemberAction.mention,
          ChatMemberAction.exclusiveRedPacket
        ],
        displayName: '普通成员',
      );
    });
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('@对方'), findsOneWidget);
    expect(find.text('专属红包'), findsOneWidget);
    for (final label in ['禁言', '解除禁言', '移除群聊']) {
      expect(find.text(label), findsNothing);
    }
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
  });

  testWidgets('an empty action list does not open a menu', (tester) async {
    ChatMemberAction? selected = ChatMemberAction.remove;
    await _pumpHost(tester, onOpen: (context) async {
      selected = await showChatMemberActionSheet(
        context,
        actions: const [],
        displayName: '无权限成员',
      );
    });
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.byType(BottomSheetView), findsNothing);
  });

  for (final (action, question) in [
    (ChatMemberAction.mute, '确定禁言「成员甲」吗？'),
    (ChatMemberAction.unmute, '确定解除「成员甲」的禁言吗？'),
    (ChatMemberAction.remove, '确定将「成员甲」移除群聊吗？'),
  ]) {
    testWidgets('$action requires a confirmation and supports cancellation',
        (tester) async {
      bool? confirmed;
      await _pumpHost(tester, onOpen: (context) async {
        confirmed = await confirmChatMemberAction(
          context,
          action: action,
          displayName: '成员甲',
        );
      });
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomDialog), findsOneWidget);
      expect(find.text(question), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(confirmed, isFalse);

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);
      expect(find.byType(CustomDialog), findsNothing);
    });
  }

  testWidgets('mention does not require moderation confirmation',
      (tester) async {
    bool? confirmed;
    await _pumpHost(tester, onOpen: (context) async {
      confirmed = await confirmChatMemberAction(
        context,
        action: ChatMemberAction.mention,
        displayName: '成员甲',
      );
    });
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
    expect(find.byType(CustomDialog), findsNothing);
  });

  testWidgets(
      'exclusive packet selection returns directly without confirmation',
      (tester) async {
    ChatMemberAction? selected;
    bool? confirmed;
    await _pumpHost(tester, onOpen: (context) async {
      selected = await showChatMemberActionSheet(context,
          actions: const [ChatMemberAction.exclusiveRedPacket],
          displayName: '成员甲');
      if (selected != null && context.mounted) {
        confirmed = await confirmChatMemberAction(context,
            action: selected!, displayName: '成员甲');
      }
    });
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('专属红包'));
    await tester.pumpAndSettle();
    expect(selected, ChatMemberAction.exclusiveRedPacket);
    expect(confirmed, isTrue);
    expect(find.byType(CustomDialog), findsNothing);
  });
}

Future<void> _pumpHost(
  WidgetTester tester, {
  required Future<void> Function(BuildContext) onOpen,
  Brightness brightness = Brightness.light,
  Size size = const Size(375, 812),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Styles.isDark = brightness == Brightness.dark;
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    minTextAdapt: true,
    fontSizeResolver: (fontSize, _) => fontSize.toDouble(),
    builder: (_, __) => MaterialApp(
      theme: ThemeData(brightness: brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => onOpen(context),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}
