import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/chat_setup/chat_history_search_page.dart';
import 'package:openim/pages/chat/chat_setup/message_context_page.dart';
import 'package:openim/pages/chat/history_search/chat_history_category.dart';
import 'package:openim/pages/chat/history_search/chat_history_results_page.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_source.dart';
import 'package:openim/pages/chat/history_search/navigation/chat_history_message_navigation.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_date_page.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_sender_page.dart';
import 'package:openim/pages/chat/history_search/selection/chat_history_sender_source.dart';
import 'package:openim/pages/chat/media/widgets/chat_video_thumbnail.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class _SearchCall {
  const _SearchCall(
      this.conversationID, this.query, this.pageIndex, this.count);
  final String conversationID;
  final ChatHistorySearchQuery query;
  final int pageIndex;
  final int count;
}

class _SearchSource implements ChatHistorySearchSource {
  final calls = <_SearchCall>[];
  List<_SearchCall> get resultCalls =>
      calls.where((call) => call.count == 30).toList();
  List<Message> messages = [];
  int failures = 0;
  Future<List<Message>> Function(_SearchCall call)? respond;

  @override
  Future<List<Message>> search({
    required String conversationID,
    required ChatHistorySearchQuery query,
    required int pageIndex,
    int count = 30,
  }) async {
    final call = _SearchCall(conversationID, query, pageIndex, count);
    calls.add(call);
    if (respond case final respond?) return respond(call);
    if (failures > 0) {
      --failures;
      throw StateError('Search temporarily unavailable');
    }
    if (count == 1) {
      return pageIndex == 1
          ? messages.where(query.accepts).take(1).toList()
          : [];
    }
    return messages;
  }
}

class _SenderSource implements ChatHistorySenderSource {
  static const member =
      ChatHistorySender(userID: 'member-42', displayName: '测试发送人');
  final conversations = <String>[];

  @override
  String get currentUserID => 'self';

  @override
  Future<ChatHistorySenderPageData> load({
    required String conversationID,
    required String query,
    required int offset,
    required int count,
  }) async {
    conversations.add(conversationID);
    return const ChatHistorySenderPageData(
        items: [member], nextOffset: 1, hasMore: false);
  }
}

Message _textMessage() => Message.fromJson({
      'clientMsgID': 'matching-message',
      'contentType': MessageType.text,
      'sessionType': ConversationType.single,
      'sendID': 'self',
      'recvID': 'peer',
      'senderNickname': 'Self',
      'seq': 1,
      'sendTime': DateTime(DateTime.now().year, DateTime.now().month, 1, 12)
          .millisecondsSinceEpoch,
      'status': MessageStatus.succeeded,
      'textElem': {'content': 'matching result'},
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  const conversationID = 'fixed-conversation';
  late _SearchSource source;
  late _SenderSource senderSource;
  late _NavigationProbe messageNavigation;

  setUp(() async {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'self', nickname: 'Self');
    OpenIM.iMManager.token = 'history-navigation-session';
    SharedPreferences.setMockInitialValues({});
    await SpUtil().init();
    source = _SearchSource();
    senderSource = _SenderSource();
    messageNavigation = _NavigationProbe();
  });

  tearDown(() {
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> mount(WidgetTester tester,
      {Brightness brightness = Brightness.light,
      String initialQuery = '',
      bool filesOnly = false,
      bool isGroup = false,
      Widget? page}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        theme: ThemeData(brightness: brightness),
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        home: page ??
            ChatHistorySearchPage(
              conversationID: conversationID,
              initialQuery: initialQuery,
              filesOnly: filesOnly,
              isGroup: isGroup,
              source: source,
              senderSource: senderSource,
              messageNavigation: messageNavigation,
            ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder categoryEntry(ChatHistoryCategory category) =>
      find.byKey(ValueKey('chat-history-category-${category.name}'));

  Future<void> pop(WidgetTester tester) async {
    final context = tester.element(find.byType(Scaffold).last);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
  }

  Future<void> disposePage(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    for (final category in [
      ChatHistoryCategory.media,
      ChatHistoryCategory.file,
      ChatHistoryCategory.date,
      ChatHistoryCategory.sender,
    ]) {
      testWidgets('${brightness.name}: ${category.name} opens scoped page',
          (tester) async {
        if (category == ChatHistoryCategory.date) {
          source.messages = [_textMessage()];
        }
        await mount(tester, brightness: brightness, isGroup: true);
        expect(source.calls, isEmpty,
            reason: 'Opening the category hub must not issue an empty search.');
        await tester.tap(categoryEntry(category));
        await tester.pumpAndSettle();

        final selectedDate =
            DateTime(DateTime.now().year, DateTime.now().month, 1);
        if (category == ChatHistoryCategory.date) {
          expect(find.byType(ChatHistoryDatePage), findsOneWidget);
          expect(source.calls, isNotEmpty,
              reason: 'The calendar checks which days have real records.');
          expect(source.calls.every((call) => call.count == 1), isTrue);
          expect(source.resultCalls, isEmpty);
          await tester.tap(find.byKey(ValueKey<DateTime>(selectedDate)).last);
          await tester.pump();
          await tester
              .tap(find.byKey(const ValueKey('chat-history-date-confirm')));
          await tester.pumpAndSettle();
        } else if (category == ChatHistoryCategory.sender) {
          expect(find.byType(ChatHistorySenderPage), findsOneWidget);
          expect(senderSource.conversations, [conversationID]);
          expect(source.calls, isEmpty);
          await tester
              .tap(find.byKey(const ValueKey('chat-history-sender-member-42')));
          await tester.pumpAndSettle();
        }

        expect(find.byType(ChatHistoryResultsPage), findsOneWidget);
        final results = tester.widget<ChatHistoryResultsPage>(
            find.byType(ChatHistoryResultsPage));
        expect(results.conversationID, conversationID);
        expect(results.category, category);
        expect(source.resultCalls, hasLength(1));
        final request = source.resultCalls.single;
        expect(request.conversationID, conversationID);
        expect(request.pageIndex, 1);
        expect(request.count, 30);
        expect(request.query.messageTypes, category.messageTypes);
        expect(request.query.keyword, isEmpty);
        if (category == ChatHistoryCategory.date) {
          expect(request.query.startDate, selectedDate);
          expect(request.query.endDate, selectedDate);
          expect(request.query.localEndExclusive,
              DateTime(selectedDate.year, selectedDate.month, 2));
        } else if (category == ChatHistoryCategory.sender) {
          expect(request.query.senderIDs, [_SenderSource.member.userID]);
          expect(results.sender?.displayName, _SenderSource.member.displayName);
        }
        expect(find.byKey(const ValueKey('chat-history-search-input')),
            findsNothing);
        await pop(tester);
        expect(categoryEntry(category), findsOneWidget);
        expect(source.resultCalls, hasLength(1));
        await disposePage(tester);
      });
    }
  }

  for (final category in [
    ChatHistoryCategory.date,
    ChatHistoryCategory.sender
  ]) {
    testWidgets(
        'cancel ${category.name} preserves input and resumes its keyword',
        (tester) async {
      await mount(tester, isGroup: true);
      await tester.enterText(find.byType(TextField), '保留的关键字');
      await tester.tap(categoryEntry(category));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      expect(source.resultCalls, isEmpty,
          reason: 'Covered search must not dispatch the unsent keyword.');
      await pop(tester);
      expect(source.resultCalls, hasLength(1));
      expect(source.resultCalls.single.query.keyword, '保留的关键字');
      expect(source.resultCalls.single.query.messageTypes, isEmpty);
      expect(source.resultCalls.single.query.startDate, isNull);
      expect(source.resultCalls.single.query.senderIDs, isEmpty);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '保留的关键字');
      await tester.tap(categoryEntry(ChatHistoryCategory.file));
      await tester.pumpAndSettle();
      expect(source.resultCalls, hasLength(2));
      expect(source.resultCalls.last.query.keyword, '保留的关键字');
      expect(source.resultCalls.last.query.messageTypes, [MessageType.file]);
      await pop(tester);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '保留的关键字');
      await disposePage(tester);
    });
  }

  testWidgets('single chat exposes media and files while group adds filters',
      (tester) async {
    await mount(tester);
    expect(categoryEntry(ChatHistoryCategory.media), findsOneWidget);
    expect(categoryEntry(ChatHistoryCategory.file), findsOneWidget);
    expect(categoryEntry(ChatHistoryCategory.date), findsNothing);
    expect(categoryEntry(ChatHistoryCategory.sender), findsNothing);
    expect(categoryEntry(ChatHistoryCategory.picture), findsNothing);
    expect(categoryEntry(ChatHistoryCategory.video), findsNothing);
    expect(categoryEntry(ChatHistoryCategory.voice), findsNothing);
    expect(source.calls, isEmpty);
    await disposePage(tester);
  });

  testWidgets('media browses combined images and videos without keywords',
      (tester) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField), '保留的关键字');
    await tester.tap(categoryEntry(ChatHistoryCategory.media));
    await tester.pumpAndSettle();
    expect(source.calls.single.query.keyword, isEmpty);
    expect(source.calls.single.query.messageTypes,
        [MessageType.picture, MessageType.video]);
    expect(find.byType(TextField), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
    expect(source.calls, hasLength(1),
        reason: 'The covered hub must cancel pending debounced searches.');
    await pop(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '保留的关键字');
    await tester.pump(const Duration(milliseconds: 600));
    expect(source.calls, hasLength(2),
        reason: 'Returning resumes the unsent keyword draft in place.');
    expect(source.calls.last.query.keyword, '保留的关键字');
    expect(source.calls.last.query.messageTypes, isEmpty);
    await disposePage(tester);
  });

  for (final category in [
    ChatHistoryCategory.picture,
    ChatHistoryCategory.video,
    ChatHistoryCategory.voice,
  ]) {
    testWidgets(
        'legacy ${category.name} browses media without textual keywords',
        (tester) async {
      await mount(tester,
          page: ChatHistoryResultsPage(
              conversationID: conversationID,
              category: category,
              initialQuery: '保留的关键字',
              source: source));

      expect(source.calls.single.query.keyword, isEmpty,
          reason: 'OpenIM media types cannot match textual keywords.');
      expect(source.calls.single.query.messageTypes, category.messageTypes);
      expect(source.calls.single.conversationID, conversationID);
      expect(find.byType(SearchBox), findsNothing);
      expect(find.byType(TextField), findsNothing);

      expect(source.calls, hasLength(1));
      await disposePage(tester);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets(
        '${brightness.name}: expired picture cannot preview or navigate',
        (tester) async {
      source.messages = [
        _textMessage()
          ..clientMsgID = 'expired-picture'
          ..contentType = MessageType.picture
          ..pictureElem = PictureElem(
            sourcePath: '/private/expired-picture.png',
            sourcePicture:
                PictureInfo(url: 'https://example.invalid/expired-picture.png'),
          )
          ..attachedInfoElem = AttachedInfoElem(
            isPrivateChat: true,
            hasReadTime: DateTime(2024, 1, 1).millisecondsSinceEpoch,
            burnDuration: 1,
          ),
      ];
      final sdkCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        sdkCalls.add(call);
        throw PlatformException(code: 'unexpected', message: call.method);
      });
      await mount(tester, brightness: brightness);
      await tester.tap(categoryEntry(ChatHistoryCategory.media));
      await tester.pumpAndSettle();

      expect(find.byType(ChatExpiringContent), findsOneWidget);
      expect(find.text('sdkExpired'.tr), findsOneWidget);
      expect(find.byType(ChatVideoThumbnail), findsNothing,
          reason: 'Expired media must not load a local or remote thumbnail.');
      expect(find.byType(Image), findsNothing);
      await tester.tap(find.text('sdkExpired'.tr));
      await tester.pumpAndSettle();
      expect(find.byType(MessageContextPage), findsNothing);
      expect(messageNavigation.calls, isEmpty);
      expect(find.byType(ChatHistoryResultsPage), findsOneWidget);
      expect(sdkCalls, isEmpty);
      await disposePage(tester);
    });
  }

  testWidgets('a message expiring after render is blocked again at tap time',
      (tester) async {
    final target = _textMessage()
      ..attachedInfoElem = AttachedInfoElem(
          isPrivateChat: true,
          hasReadTime: DateTime.now().millisecondsSinceEpoch,
          burnDuration: 3600);
    source.messages = [target];
    final sdkCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      sdkCalls.add(call);
      throw PlatformException(code: 'unexpected', message: call.method);
    });
    await mount(tester, initialQuery: 'matching');
    expect(find.text('matching result'), findsOneWidget);
    target.attachedInfoElem!.hasReadTime =
        DateTime(2024, 1, 1).millisecondsSinceEpoch;
    await tester.tap(find.text('matching result'));
    await tester.pumpAndSettle();
    expect(find.byType(MessageContextPage), findsNothing);
    expect(messageNavigation.calls, isEmpty);
    expect(find.byType(ChatHistoryResultsPage), findsOneWidget);
    expect(sdkCalls, isEmpty);
    await disposePage(tester);
  });

  testWidgets('rapid category presses create one route and one request',
      (tester) async {
    await mount(tester);
    final media = tester
        .widget<GestureDetector>(categoryEntry(ChatHistoryCategory.media));
    final files =
        tester.widget<GestureDetector>(categoryEntry(ChatHistoryCategory.file));
    media.onTap!();
    files.onTap!();
    media.onTap!();
    await tester.pumpAndSettle();
    expect(find.byType(ChatHistoryResultsPage), findsOneWidget);
    expect(source.calls, hasLength(1));
    expect(source.calls.single.query.messageTypes,
        [MessageType.picture, MessageType.video]);
    await pop(tester);
    expect(categoryEntry(ChatHistoryCategory.media), findsOneWidget);
    await tester.tap(categoryEntry(ChatHistoryCategory.file));
    await tester.pumpAndSettle();
    expect(source.calls, hasLength(2));
    expect(source.calls.last.query.messageTypes, [MessageType.file]);
    await disposePage(tester);
  });

  testWidgets('typing debounces in place and keeps shortcuts beside results',
      (tester) async {
    source.messages = [_textMessage()];
    await mount(tester);
    final resultsState = tester.state(find.byType(ChatHistoryResultsPage));
    await tester.enterText(find.byType(TextField), 'm');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), '  matching  ');
    await tester.pump(const Duration(milliseconds: 499));
    expect(source.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(source.calls, hasLength(1));
    expect(source.calls.single.query.keyword, 'matching');
    expect(find.text('matching result'), findsOneWidget);
    expect(find.byType(ChatHistoryResultsPage), findsOneWidget);
    expect(
        tester.state(find.byType(ChatHistoryResultsPage)), same(resultsState));
    expect(categoryEntry(ChatHistoryCategory.media), findsOneWidget);
    expect(categoryEntry(ChatHistoryCategory.file), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    await disposePage(tester);
  });

  testWidgets('submitting a pending keyword searches once immediately',
      (tester) async {
    source.messages = [_textMessage()];
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'matching');
    await tester.pump(const Duration(milliseconds: 200));
    expect(source.calls, isEmpty);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(source.calls, hasLength(1));
    await tester.pump(const Duration(milliseconds: 600));
    expect(source.calls, hasLength(1),
        reason: 'Submitting cancels the pending onChanged timer.');
    expect(find.text('matching result'), findsOneWidget);
    await disposePage(tester);
  });

  testWidgets(
      'clearing during a request restores the hub and ignores its result',
      (tester) async {
    final response = Completer<List<Message>>();
    source.respond = (_) => response.future;
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'matching');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(source.calls, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('chat-history-search-clear')));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(categoryEntry(ChatHistoryCategory.media), findsOneWidget);
    response.complete([_textMessage()]);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    expect(source.calls, hasLength(1),
        reason: 'An empty query must not search all chat history.');
    expect(find.text('matching result'), findsNothing);
    expect(find.byKey(const ValueKey('chat-history-retry')), findsNothing);
    await disposePage(tester);
  });

  testWidgets('disposing cancels an unsent typing debounce', (tester) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'matching');
    await tester.pump(const Duration(milliseconds: 100));
    await disposePage(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(source.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel closes search and discards an unsent typing debounce',
      (tester) async {
    await mount(tester,
        page: Scaffold(
          body: TextButton(
            onPressed: () => Get.to<void>(() => ChatHistorySearchPage(
                conversationID: conversationID, source: source)),
            child: const Text('Open search'),
          ),
        ));
    await tester.tap(find.text('Open search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'matching');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('chat-history-search-cancel')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(ChatHistorySearchPage), findsNothing);
    expect(find.text('Open search'), findsOneWidget);
    expect(source.calls, isEmpty);
    await disposePage(tester);
  });

  testWidgets('result keyword submission and retry preserve category scope',
      (tester) async {
    source.failures = 1;
    await mount(tester);
    await tester.tap(categoryEntry(ChatHistoryCategory.file));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-history-retry')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-history-retry')));
    await tester.pumpAndSettle();
    expect(source.calls, hasLength(2));
    expect(source.calls.map((call) => call.pageIndex), [1, 1]);
    expect(find.byKey(const ValueKey('chat-history-retry')), findsNothing);
    await tester.enterText(find.byType(TextField), '  invoice  ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(source.calls, hasLength(3));
    expect(source.calls.last.query.keyword, 'invoice');
    expect(source.calls.last.query.messageTypes, [MessageType.file]);
    expect(source.calls.last.conversationID, conversationID);
    expect(source.calls.last.pageIndex, 1);
    await disposePage(tester);
  });

  for (final entry in [
    (query: 'invoice', filesOnly: false),
    (query: 'invoice', filesOnly: true),
    (query: '', filesOnly: true),
  ]) {
    testWidgets(
        'global entry query=${entry.query}, filesOnly=${entry.filesOnly} stays compatible',
        (tester) async {
      await mount(tester,
          initialQuery: entry.query, filesOnly: entry.filesOnly);
      expect(find.byType(ChatHistoryResultsPage), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-history-search-input')),
          entry.filesOnly ? findsNothing : findsOneWidget);
      expect(source.calls, hasLength(1));
      expect(source.calls.single.query.keyword, entry.query);
      expect(source.calls.single.query.messageTypes,
          entry.filesOnly ? [MessageType.file] : isEmpty);
      expect(source.calls.single.conversationID, conversationID);
      await disposePage(tester);
    });
  }

  testWidgets('keyword result requests its original message in the same chat',
      (tester) async {
    final target = _textMessage();
    source.messages = [target];
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'matching');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(source.calls.single.query.keyword, 'matching');
    await tester.tap(
        find.byKey(const ValueKey('chat-history-result-matching-message')));
    await tester.pumpAndSettle();
    expect(messageNavigation.calls, hasLength(1));
    expect(messageNavigation.calls.single.conversationID, conversationID);
    expect(
        messageNavigation.calls.single.message.clientMsgID, target.clientMsgID);
    expect(messageNavigation.calls.single.message, same(target));
    expect(find.byType(MessageContextPage), findsNothing);
    expect(find.byType(ChatHistoryResultsPage), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'matching');
    expect(find.text('matching result'), findsOneWidget);
    expect(categoryEntry(ChatHistoryCategory.media), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(source.calls, hasLength(1));
    await disposePage(tester);
  });
}
