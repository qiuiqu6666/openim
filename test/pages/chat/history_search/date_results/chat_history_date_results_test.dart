import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/chat_setup/message_context_page.dart';
import 'package:openim_common/openim_common.dart';

import 'support/date_results_test_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(setUpDateResultsSession);
  tearDown(resetDateResultsSession);

  final more = find.byKey(const ValueKey('chat-history-more'));
  final retry = find.byKey(const ValueKey('chat-history-retry'));

  for (final brightness in Brightness.values) {
    testWidgets(
        '${brightness.name}: date title and complete divided rows retain the day without inherited keyword',
        (tester) async {
      final missingTime = dateResultsMessage('missing-time')..sendTime = null;
      final source = DateResultsSearchSource((call) async {
        if (call.query.keyword.isNotEmpty) return [];
        return [
          dateResultsMessage('midnight',
              sentAt: dateResultsDayStart.millisecondsSinceEpoch),
          dateResultsMessage('last-millisecond',
              sentAt: dateResultsDayEnd.millisecondsSinceEpoch - 1),
          dateResultsMessage('previous-day',
              sentAt: dateResultsDayStart.millisecondsSinceEpoch - 1),
          dateResultsMessage('next-midnight',
              sentAt: dateResultsDayEnd.millisecondsSinceEpoch),
          missingTime,
        ];
      });
      await mountDateResults(tester, source, brightness: brightness);

      expect(source.calls, hasLength(1));
      expectDateResultsScope(source.calls.single, pageIndex: 1);
      expect(find.text('2026年10月2日'), findsOneWidget,
          reason: 'The selected date belongs only in the navigation title.');
      expect(find.text('日期'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(SearchBox), findsNothing);
      for (final included in ['midnight', 'last-millisecond']) {
        final row = find.byKey(ValueKey('chat-history-result-$included'));
        expect(find.text('消息 $included'), findsOneWidget);
        expect(find.descendant(of: row, matching: find.byType(Divider)),
            findsOneWidget,
            reason: 'Every row, including the last, has a visible divider.');
      }
      for (final excluded in [
        'previous-day',
        'next-midnight',
        'missing-time'
      ]) {
        expect(find.text('消息 $excluded'), findsNothing,
            reason: 'SDK timestamps cannot escape the selected calendar day.');
      }
      expect(more, findsNothing);
      expect(retry, findsNothing);
      await unmountDateResults(tester);
    });

    testWidgets(
        '${brightness.name}: date pagination preserves rows and retries its raw cursor within the same day',
        (tester) async {
      var nextPageAttempts = 0;
      final source = DateResultsSearchSource((call) async {
        if (call.pageIndex == 1) {
          return List.generate(
              30, (index) => dateResultsMessage('first-$index'));
        }
        if (++nextPageAttempts == 1) throw StateError('Connection interrupted');
        return [
          dateResultsMessage('last-match'),
          dateResultsMessage('last-outside-day',
              sentAt: dateResultsDayEnd.millisecondsSinceEpoch),
        ];
      });
      await mountDateResults(tester, source, brightness: brightness);
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(more, 500,
          scrollable: scrollable, maxScrolls: 20);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(retry, findsOneWidget);
      expect(find.text('消息 first-29'), findsOneWidget);
      expect(source.calls.map((call) => call.pageIndex), [1, 2]);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('消息 last-match'), 200,
          scrollable: scrollable, maxScrolls: 5);
      expect(source.calls.map((call) => call.pageIndex), [1, 2, 2]);
      for (final call in source.calls) {
        expectDateResultsScope(call, pageIndex: call.pageIndex);
      }
      expect(find.text('消息 first-29'), findsOneWidget);
      expect(find.text('消息 last-match'), findsOneWidget);
      expect(find.text('消息 last-outside-day'), findsNothing);
      expect(retry, findsNothing);
      expect(more, findsNothing);
      await unmountDateResults(tester);
    });

    testWidgets('${brightness.name}: narrow date results support large text',
        (tester) async {
      final message = dateResultsMessage('large-text')
        ..senderNickname = '很长的发送人昵称保持时间和摘要可读'
        ..textElem = TextElem(content: '消息摘要包含很长的一段内容，用于窄屏大字体下的真实布局验证。');
      final source = DateResultsSearchSource((_) async => [message]);
      await mountDateResults(tester, source,
          brightness: brightness, textScale: 2, viewport: const Size(320, 844));
      expect(find.text(message.senderNickname!), findsOneWidget);
      expect(find.text(message.textElem!.content!), findsOneWidget);
      expect(find.text('2026年10月2日'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmountDateResults(tester);
    });
  }

  testWidgets('calendar results ignore the main draft and restore it on return',
      (tester) async {
    final picked = dateResultsMessage('picked-day');
    final source = DateResultsSearchSource((call) async {
      if (call.query.startDate == null) return [];
      if (call.count == 1) {
        return call.pageIndex == 1 && call.query.accepts(picked)
            ? [picked]
            : [];
      }
      return [picked];
    });
    await mountDateResults(tester, source, mainSearch: true);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'unrelated inherited keyword');
    expect(source.calls.single.query.keyword, 'unrelated inherited keyword');
    await tester.tap(find.byKey(const ValueKey('chat-history-category-date')));
    await tester.pumpAndSettle();
    expect(source.calls.where((call) => call.count == 1), isNotEmpty);
    await tester.tap(find.byKey(ValueKey<DateTime>(dateResultsDayStart)));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-history-date-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('2026年10月2日'), findsOneWidget);
    expect(find.text('消息 picked-day'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(source.calls.where((call) => call.count == 30), hasLength(2));
    expectDateResultsScope(source.calls.last, pageIndex: 1);
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'unrelated inherited keyword');
    expect(source.calls.where((call) => call.count == 30), hasLength(2),
        reason: 'Returning retains the original main search and draft.');
    await unmountDateResults(tester);
  });

  testWidgets('a private date result expiring after rendering cannot be opened',
      (tester) async {
    final target = dateResultsMessage('expires-match')
      ..attachedInfoElem = AttachedInfoElem(
        isPrivateChat: true,
        hasReadTime: DateTime.now().millisecondsSinceEpoch,
        burnDuration: 3600,
      );
    final source = DateResultsSearchSource((_) async => [target]);
    final sdkCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(dateResultsChannel, (call) async {
      sdkCalls.add(call);
      throw PlatformException(code: 'unexpected', message: call.method);
    });
    await mountDateResults(tester, source);
    expect(find.byType(ChatExpiringContent), findsOneWidget);
    target.attachedInfoElem!.hasReadTime =
        DateTime(2020).millisecondsSinceEpoch;
    await tester.tap(find.text('消息 expires-match'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(MessageContextPage), findsNothing);
    expect(find.text('消息 expires-match'), findsNothing);
    expect(find.text('sdkExpired'.tr), findsOneWidget);
    expect(sdkCalls, isEmpty);
    await unmountDateResults(tester);
  });

  testWidgets('English date navigation title follows the current locale',
      (tester) async {
    final source =
        DateResultsSearchSource((_) async => [dateResultsMessage('english')]);
    await mountDateResults(tester, source, locale: const Locale('en', 'US'));
    expect(find.text('Oct 2, 2026'), findsOneWidget);
    expectDateResultsScope(source.calls.single, pageIndex: 1);
    expect(find.byType(TextField), findsNothing);
    await unmountDateResults(tester);
  });
}
