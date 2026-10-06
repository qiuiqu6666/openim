import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/chat_setup/message_context_page.dart';
import 'package:openim/pages/chat/history_search/chat_history_category.dart';
import 'package:openim/pages/chat/history_search/chat_history_results_page.dart';
import 'package:openim/pages/chat/history_search/navigation/chat_history_message_navigation.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/chat_attachment_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/chat_history_voice_fixture.dart';

class _NavigationProbe extends ChatHistoryMessageNavigation {
  final calls = <({String conversationID, Message message})>[];

  @override
  Future<bool> open(BuildContext context,
      {required String conversationID,
      required Message message,
      required bool Function() isEntryCurrent}) async {
    expect(isEntryCurrent(), isTrue);
    calls.add((conversationID: conversationID, message: message));
    return true;
  }
}

Future<void> _pumpNavigationPage(WidgetTester tester, VoiceTestSource source,
    ChatHistoryMessageNavigation navigation) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    Get.reset();
  });
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: ChatHistoryResultsPage(
        conversationID: voiceConversationID,
        category: ChatHistoryCategory.voice,
        source: source,
        messageNavigation: navigation,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  late List<MethodCall> sdkCalls;
  late _NavigationProbe messageNavigation;

  setUp(() async {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self');
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    messageNavigation = _NavigationProbe();
    sdkCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      sdkCalls.add(call);
      if (call.method == 'findMessageList') {
        return jsonEncode({'findResultItems': []});
      }
      throw StateError('Unexpected SDK method ${call.method}');
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} voice rows fit 320px and 200% text',
        (tester) async {
      final source = VoiceTestSource()..messages = voiceSamples();
      var httpClients = 0;
      await HttpOverrides.runZoned(() async {
        await pumpVoicePage(tester, source,
            brightness: brightness, width: 320, textScale: 2);
        expect(find.byType(SearchBox), findsNothing);
        expect(find.byType(TextField), findsNothing);
        for (final entry in source.messages) {
          final row = voiceResult(entry.clientMsgID!);
          final title = tester.widget<Text>(find.descendant(
              of: row,
              matching: find.byWidgetPredicate((widget) =>
                  widget is Text &&
                  ((widget.data ?? widget.textSpan?.toPlainText())
                          ?.contains(StrRes.voice) ??
                      false))));
          expect(title.data ?? title.textSpan?.toPlainText(),
              contains('${entry.soundElem!.duration}'));
          expect(tester.getRect(row).right, lessThanOrEqualTo(320));
        }
        expect(find.textContaining('项目工作讨论群'), findsOneWidget);
        expect(find.byType(ChatVoiceMessageView), findsNothing);
        expect(sdkCalls, isEmpty);
        expect(tester.takeException(), isNull);
      }, createHttpClient: (_) {
        httpClients++;
        throw StateError('Voice list must not fetch audio');
      });
      expect(httpClients, 0);
    });
  }

  testWidgets('voice summary follows the active locale', (tester) async {
    final source = VoiceTestSource()..messages = [voiceMessage('english', 7)];
    await pumpVoicePage(tester, source, locale: const Locale('en', 'US'));
    expect(find.textContaining(StrRes.voice), findsAtLeastNWidgets(2));
    expect(find.textContaining('语音'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final private in [false, true]) {
    testWidgets(
        '${private ? 'private' : 'ordinary'} voice requests original chat message',
        (tester) async {
      final target = voiceMessage('original', 7, private: private);
      final source = VoiceTestSource()..messages = [target];
      await _pumpNavigationPage(tester, source, messageNavigation);
      expect(find.byType(ChatVoiceMessageView), findsNothing);
      expect(sdkCalls, isEmpty);
      if (private) expect(find.byType(ChatExpiringContent), findsOneWidget);
      await tester.tap(voiceResult('original'));
      await tester.pumpAndSettle();
      expect(messageNavigation.calls, hasLength(1));
      final call = messageNavigation.calls.single;
      expect(call.conversationID, voiceConversationID);
      expect(call.message.clientMsgID, target.clientMsgID);
      expect(call.message, same(target));
      expect(call.message.attachedInfoElem?.isPrivateChat,
          private ? isTrue : isNull);
      expect(find.byType(MessageContextPage), findsNothing);
      expect(sdkCalls, isEmpty);
      expect(find.byType(ChatVoiceMessageView), findsNothing);
      expect(source.queries, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('expired voice masks content and cannot open', (tester) async {
    final source = VoiceTestSource()
      ..messages = [voiceMessage('expired', 7, expired: true)];
    await _pumpNavigationPage(tester, source, messageNavigation);
    expect(find.text('sdkExpired'.tr), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(ChatVoiceMessageView), findsNothing);
    await tester.tap(voiceResult('expired'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(MessageContextPage), findsNothing);
    expect(messageNavigation.calls, isEmpty);
    expect(sdkCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('voice expiry is rechecked before navigation', (tester) async {
    final target = voiceMessage('expires', 4, private: true);
    final source = VoiceTestSource()..messages = [target];
    await _pumpNavigationPage(tester, source, messageNavigation);
    target.attachedInfoElem!.hasReadTime =
        DateTime(2020).millisecondsSinceEpoch;
    await tester.tap(voiceResult('expires'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatHistoryResultsPage), findsOneWidget);
    expect(find.byType(MessageContextPage), findsNothing);
    expect(messageNavigation.calls, isEmpty);
    expect(sdkCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
