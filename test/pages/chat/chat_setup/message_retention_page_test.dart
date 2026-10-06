import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/chat_setup/message_retention_page.dart';
import 'package:openim_common/openim_common.dart';

import 'support/chat_setup_test_host.dart';
import 'support/retention_sdk_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeChatSetupUi);
  tearDown(Get.reset);
  Finder key(String value) => find.byKey(ValueKey(value));
  Finder valueIn(String row, String text) =>
      find.descendant(of: key(row), matching: find.text(text));

  void retentionTest(String name,
      Future<void> Function(WidgetTester, RetentionSdkFixture) body) {
    testWidgets(name, (tester) async {
      final sdk = RetentionSdkFixture();
      await sdk.initialize();
      try {
        await body(tester, sdk);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await sdk.dispose();
        await tester.pump();
      }
    });
  }

  Future<void> choose(WidgetTester tester, String row, String label) async {
    await tester.ensureVisible(key(row));
    await tester.tap(key(row));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    // The native write intentionally stays pending to exercise the busy state.
    await tester.pump(const Duration(milliseconds: 400));
  }

  retentionTest('selecting a new burn duration saves only the SDK burn fields',
      (tester, sdk) async {
    await mountChatSetupUi(
        tester, MessageRetentionPage(conversation: sdk.server));
    expect(sdk.reads, hasLength(1));
    await choose(tester, 'retention-burn-row', '30 秒');
    expect(sdk.writes, hasLength(1));
    expect(sdk.writes.single.request, {
      'isPrivateChat': true,
      'burnDuration': 30,
    });
    expect(find.text('正在保存…'), findsOneWidget);
    sdk.server = retentionConversation(burn: true, burnSeconds: 30);
    sdk.writes.single.succeed();
    await tester.pumpAndSettle();
    expect(sdk.reads, hasLength(2));
    expect(valueIn('retention-burn-row', '30 秒'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  retentionTest('a saved custom duration is visible and selected in the sheet',
      (tester, sdk) async {
    sdk.server = retentionConversation(burn: true, burnSeconds: 90);
    await mountChatSetupUi(
        tester, MessageRetentionPage(conversation: sdk.server));
    expect(valueIn('retention-burn-row', '90 秒'), findsOneWidget);
    await tester.tap(key('retention-burn-row'));
    await tester.pumpAndSettle();
    final selected = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.selected == true);
    expect(find.descendant(of: selected, matching: find.text('90 秒')),
        findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(sdk.writes, isEmpty);
    expect(valueIn('retention-burn-row', '90 秒'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  retentionTest('a failed save keeps the stored value and can retry its choice',
      (tester, sdk) async {
    sdk.server = retentionConversation(burn: true, burnSeconds: 60);
    await mountChatSetupUi(
        tester, MessageRetentionPage(conversation: sdk.server));
    await choose(tester, 'retention-burn-row', '5 分钟');
    sdk.writes.single.fail();
    await tester.pumpAndSettle();
    expect(valueIn('retention-burn-row', '1 分钟'), findsOneWidget);
    expect(key('retention-save-retry'), findsOneWidget);
    await tester.tap(key('retention-save-retry'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(sdk.writes, hasLength(2));
    expect(sdk.writes.last.request, sdk.writes.first.request);
    sdk.server = retentionConversation(burn: true, burnSeconds: 300);
    sdk.writes.last.succeed();
    await tester.pumpAndSettle();
    expect(valueIn('retention-burn-row', '5 分钟'), findsOneWidget);
    expect(key('retention-save-retry'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  retentionTest('an initial read failure offers a retry for the saved settings',
      (tester, sdk) async {
    final fallback = retentionConversation();
    sdk.server = retentionConversation(delete: true, deleteSeconds: 604800);
    sdk.failNextRead = true;
    await mountChatSetupUi(
        tester, MessageRetentionPage(conversation: fallback));
    expect(key('retention-load-retry'), findsOneWidget);
    final retryRead = sdk.holdNextRead();
    await tester.tap(key('retention-load-retry'));
    await tester.tap(key('retention-load-retry'));
    await tester.pump();
    expect(sdk.reads, hasLength(2),
        reason: 'Rapid retry taps share one pending SDK read.');
    sdk.releaseRead(retryRead);
    await tester.pumpAndSettle();
    expect(sdk.reads, hasLength(2));
    expect(valueIn('retention-delete-row', '7 天'), findsOneWidget);
    expect(key('retention-load-retry'), findsNothing);
    expect(sdk.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  retentionTest('turning retention off omits duration and unrelated SDK fields',
      (tester, sdk) async {
    sdk.server = retentionConversation(delete: true);
    await mountChatSetupUi(
        tester, MessageRetentionPage(conversation: sdk.server));
    await choose(tester, 'retention-delete-row', '关闭');
    expect(sdk.writes.single.request, {'isMsgDestruct': false});
    sdk.server = retentionConversation();
    sdk.writes.single.succeed();
    await tester.pumpAndSettle();
    expect(valueIn('retention-delete-row', '关闭'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  retentionTest(
      'closing during a save ignores completion and skips followup reads',
      (tester, sdk) async {
    await mountChatSetupUi(
        tester, MessageRetentionPage(conversation: sdk.server));
    await choose(tester, 'retention-burn-row', '30 秒');
    await tester.pumpWidget(const SizedBox.shrink());
    sdk.writes.single.succeed();
    await tester.pump();
    expect(sdk.reads, hasLength(1),
        reason: 'A disposed page must not start another SDK read.');
    expect(tester.takeException(), isNull);
  });

  retentionTest(
      'group settings show retention without single-chat burn controls',
      (tester, sdk) async {
    sdk.server = retentionConversation(group: true, delete: true);
    await mountChatSetupUi(
        tester, MessageRetentionPage(conversation: sdk.server));
    expect(key('retention-burn-row'), findsNothing);
    expect(key('retention-delete-row'), findsOneWidget);
    expect(valueIn('retention-delete-row', '1 天'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  retentionTest('changing the IM token ignores a late save for the same user',
      (tester, sdk) async {
    await mountChatSetupUi(
        tester, MessageRetentionPage(conversation: sdk.server));
    await choose(tester, 'retention-burn-row', '30 秒');
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'setup-owner',
      'imToken': 'replacement-im-token',
      'chatToken': 'setup-chat-token',
    }));
    sdk.server = retentionConversation(burn: true, burnSeconds: 30);
    sdk.writes.single.succeed();
    await tester.pump();
    expect(sdk.reads, hasLength(1),
        reason:
            'An old IM session must not read into its replacement session.');
    expect(valueIn('retention-burn-row', '关闭'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    retentionTest(
        'retention choices remain readable at 320px and 2x text ($dark)',
        (tester, sdk) async {
      sdk.server = retentionConversation(burn: true, delete: true);
      final boundary = await mountChatSetupUi(
          tester, MessageRetentionPage(conversation: sdk.server),
          dark: dark, size: const Size(320, 640), scale: 2);
      expect(key('retention-burn-row').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await exportChatSetupUi(
          tester, boundary, 'message-retention-${dark ? 'dark' : 'light'}');
      await tester.ensureVisible(key('retention-delete-row'));
      await tester.tap(key('retention-delete-row'));
      await tester.pumpAndSettle();
      expect(find.text('30 天').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(sdk.writes, isEmpty);
    });
  }

  if (chatSetupPreviewDirectory.isNotEmpty) {
    retentionTest('normal retention preview uses the saved SDK settings',
        (tester, sdk) async {
      sdk.server = retentionConversation(burn: true, delete: true);
      final boundary = await mountChatSetupUi(
          tester, MessageRetentionPage(conversation: sdk.server),
          showBackButton: true);
      expect(find.byIcon(Icons.arrow_back_ios_new_rounded).hitTestable(),
          findsOneWidget);
      expect(valueIn('retention-burn-row', '30 秒'), findsOneWidget);
      expect(valueIn('retention-delete-row', '1 天'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await exportChatSetupUi(
          tester, boundary, 'message-retention-normal-light');
    });
  }
}
