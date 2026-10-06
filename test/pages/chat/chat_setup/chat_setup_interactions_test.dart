import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/chat_setup/chat_setup_view.dart';
import 'package:openim/pages/chat/chat_setup/message_retention_page.dart';
import 'package:openim_common/openim_common.dart';

import 'support/chat_setup_fake_logic.dart';
import 'support/chat_setup_test_host.dart';
import 'support/retention_sdk_fixture.dart';

class _PendingMuteLogic extends ChatSetupFakeLogic {
  final muteGate = Completer<void>();

  @override
  Future<void> setMuted(bool value) async {
    if (updating.value) return;
    updating.value = true;
    muted.add(value);
    try {
      await muteGate.future;
      conversationInfo.value.recvMsgOpt = value ? 2 : 0;
      conversationInfo.refresh();
    } finally {
      updating.value = false;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeChatSetupUi);
  tearDown(Get.reset);
  Finder key(String name) => find.byKey(ValueKey(name));

  void setupTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    });
  }

  setupTest(
      'member tiles stay beside each other and preserve both entry actions',
      (tester) async {
    final logic = ChatSetupFakeLogic();
    await mountChatSetupUi(tester, ChatSetupPage(logic: logic),
        size: const Size(320, 640), scale: 2);
    final member = key('chat-setup-member-profile');
    final add = key('chat-setup-add-member');
    final cardRect = tester.getRect(key('chat-setup-members'));
    expect(member.hitTestable(), findsOneWidget);
    expect(add.hitTestable(), findsOneWidget);
    expect(tester.getRect(member).top, closeTo(tester.getRect(add).top, 1));
    expect(cardRect.contains(tester.getCenter(member)), isTrue);
    expect(cardRect.contains(tester.getCenter(add)), isTrue);
    await tester.tap(member);
    await tester.tap(add);
    expect(logic.profiles, 1);
    expect(logic.groups, 1);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final dark in [false, true]) {
      setupTest(
          '${platform.name} shared switches lock during each save and publish values ($dark)',
          (tester) async {
        final logic = _PendingMuteLogic()..pinGate = Completer<void>();
        final boundary = await mountChatSetupUi(
            tester, ChatSetupPage(logic: logic),
            dark: dark,
            platform: platform,
            showBackButton: chatSetupPreviewDirectory.isNotEmpty);
        final pin = find.descendant(
            of: key('chat-setup-pin'), matching: find.byType(AppSwitch));
        final mute = find.descendant(
            of: key('chat-setup-mute'), matching: find.byType(AppSwitch));
        expect(pin.hitTestable(), findsOneWidget);
        expect(mute.hitTestable(), findsOneWidget);
        for (final control in [pin, mute]) {
          final native = find.descendant(
              of: control, matching: find.byType(CupertinoSwitch));
          expect(tester.widget<CupertinoSwitch>(native).activeTrackColor,
              Styles.c_0089FF);
        }
        expect(tester.widget<AppSwitch>(pin).value, isFalse);
        expect(tester.widget<AppSwitch>(mute).value, isFalse);
        if (platform == TargetPlatform.android) {
          await exportChatSetupUi(tester, boundary,
              'chat-setup-switches-android-${dark ? 'dark' : 'light'}-off');
        }

        await tester.tap(pin);
        await tester.pump();
        expect(logic.pinned, [true]);
        expect(tester.widget<AppSwitch>(pin).onChanged, isNull);
        expect(tester.widget<AppSwitch>(mute).onChanged, isNull);
        await tester.tap(pin);
        await tester.tap(mute);
        expect(logic.pinned, [true]);
        expect(logic.muted, isEmpty);
        logic.pinGate!.complete();
        await tester.pumpAndSettle();
        expect(tester.widget<AppSwitch>(pin).value, isTrue);
        expect(tester.widget<AppSwitch>(mute).onChanged, isNotNull);

        await tester.tap(mute);
        await tester.pump();
        expect(logic.muted, [true]);
        expect(tester.widget<AppSwitch>(mute).value, isFalse);
        expect(tester.widget<AppSwitch>(pin).onChanged, isNull);
        expect(tester.widget<AppSwitch>(mute).onChanged, isNull);
        await tester.tap(pin);
        await tester.tap(mute);
        expect(logic.pinned, [true]);
        expect(logic.muted, [true]);
        logic.muteGate.complete();
        await tester.pumpAndSettle();
        expect(tester.widget<AppSwitch>(pin).value, isTrue);
        expect(tester.widget<AppSwitch>(mute).value, isTrue);
        expect(tester.widget<AppSwitch>(pin).onChanged, isNotNull);
        expect(tester.widget<AppSwitch>(mute).onChanged, isNotNull);
        if (platform == TargetPlatform.android) {
          await exportChatSetupUi(tester, boundary,
              'chat-setup-switches-android-${dark ? 'dark' : 'light'}-on');
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  setupTest('history and appearance rows keep navigation and clear is gated',
      (tester) async {
    final logic = ChatSetupFakeLogic();
    await mountChatSetupUi(tester, ChatSetupPage(logic: logic));
    await tester.tap(key('chat-setup-search'));
    expect(logic.searches, 1);
    await tester.scrollUntilVisible(key('chat-setup-background'), 140,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(key('chat-setup-background'));
    expect(logic.backgrounds, 1);
    await tester.scrollUntilVisible(key('chat-setup-clear'), 140,
        scrollable: find.byType(Scrollable).first);
    logic.clearing.value = true;
    await tester.pump();
    await tester.tap(key('chat-setup-clear'));
    expect(logic.clears, 0);
    logic.clearing.value = false;
    await tester.pump();
    await tester.tap(key('chat-setup-clear'));
    expect(logic.clears, 1);
    expect(tester.takeException(), isNull);
  });

  setupTest('retention row reads SDK settings for the current conversation',
      (tester) async {
    final sdk = RetentionSdkFixture();
    await sdk.initialize();
    addTearDown(sdk.dispose);
    final logic = ChatSetupFakeLogic();
    final currentConversation = retentionConversation()
      ..conversationID = 'si-current-settings';
    logic.conversationInfo.value = currentConversation;
    sdk.server = currentConversation;
    await mountChatSetupUi(tester, ChatSetupPage(logic: logic));
    expect(key('chat-setup-retention').hitTestable(), findsOneWidget);
    await tester.tap(key('chat-setup-retention'));
    await tester.pumpAndSettle();
    final page =
        tester.widget<MessageRetentionPage>(find.byType(MessageRetentionPage));
    expect(page.conversation.conversationID, 'si-current-settings');
    expect(sdk.reads, hasLength(1));
    expect(sdk.reads.single.arguments,
        containsPair('conversationIDList', ['si-current-settings']));
    expect(tester.takeException(), isNull);
  });

  setupTest('complaint row keeps the conversation report entry available',
      (tester) async {
    final logic = ChatSetupFakeLogic();
    await mountChatSetupUi(tester, ChatSetupPage(logic: logic));
    expect(key('chat-setup-retention').hitTestable(), findsOneWidget);
    expect(find.text('消息免打扰'), findsOneWidget);
    final referenceOrder = [
      'chat-setup-members',
      'chat-setup-retention',
      'chat-setup-search',
      'chat-setup-pin',
      'chat-setup-mute',
      'chat-setup-background',
      'chat-setup-clear',
      'chat-setup-report',
    ];
    for (var index = 1; index < referenceOrder.length; index++) {
      expect(tester.getRect(key(referenceOrder[index])).top,
          greaterThan(tester.getRect(key(referenceOrder[index - 1])).top),
          reason:
              'The displayed entries preserve the reference reading order.');
    }
    await tester.scrollUntilVisible(key('chat-setup-report'), 140,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('投诉').hitTestable(), findsOneWidget);
    await tester.tap(key('chat-setup-report'));
    expect(logic.reports, 1);
    expect(logic.clears, 0);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    setupTest('grouped settings remain usable at 320px and 2x text ($dark)',
        (tester) async {
      final logic = ChatSetupFakeLogic();
      final boundary = await mountChatSetupUi(
          tester, ChatSetupPage(logic: logic),
          dark: dark, size: const Size(320, 640), scale: 2);
      expect(tester.takeException(), isNull);
      final notificationsGroup = key('chat-setup-notifications-group');
      final material = find.descendant(
          of: notificationsGroup,
          matching: find.byWidgetPredicate((widget) =>
              widget is Material && widget.clipBehavior != Clip.none));
      expect(material, findsOneWidget,
          reason: 'Adjacent notification controls share one clipped surface.');
      expect(find.descendant(of: material, matching: key('chat-setup-pin')),
          findsOneWidget);
      expect(find.descendant(of: material, matching: key('chat-setup-mute')),
          findsOneWidget);
      expect(key('chat-setup-retention'), findsOneWidget);
      await exportChatSetupUi(
          tester, boundary, 'chat-setup-${dark ? 'dark' : 'light'}');
      await tester.scrollUntilVisible(key('chat-setup-clear'), 160,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(key('chat-setup-clear').hitTestable(), findsOneWidget);
      await tester.tap(key('chat-setup-clear'));
      expect(logic.clears, 1);
      expect(tester.getRect(key('chat-setup-clear')).bottom,
          lessThanOrEqualTo(624));
      await tester.scrollUntilVisible(key('chat-setup-report'), 140,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(key('chat-setup-report').hitTestable(), findsOneWidget);
      await tester.tap(key('chat-setup-report'));
      expect(logic.reports, 1);
      expect(tester.getRect(key('chat-setup-report')).bottom,
          lessThanOrEqualTo(624));
      expect(tester.takeException(), isNull);
    });
  }

  if (chatSetupPreviewDirectory.isNotEmpty) {
    setupTest('normal chat settings preview uses the actual settings page',
        (tester) async {
      final logic = ChatSetupFakeLogic();
      final boundary = await mountChatSetupUi(
          tester, ChatSetupPage(logic: logic),
          showBackButton: true);
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded).hitTestable(),
          findsOneWidget);
      expect(key('chat-setup-member-profile').hitTestable(), findsOneWidget);
      expect(key('chat-setup-search').hitTestable(), findsOneWidget);
      expect(key('chat-setup-retention').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await exportChatSetupUi(tester, boundary, 'chat-setup-normal-light');
    });
  }
}
