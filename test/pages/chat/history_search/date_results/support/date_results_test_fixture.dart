import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/history_search/chat_history_category.dart';
import 'package:openim/pages/chat/history_search/chat_history_results_page.dart';
import 'package:openim/pages/chat/history_search/chat_history_search_source.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef DateResultsSearchCall = ({
  String conversationID,
  ChatHistorySearchQuery query,
  int pageIndex,
  int count,
});

class DateResultsSearchSource implements ChatHistorySearchSource {
  DateResultsSearchSource(this.respond);

  final Future<List<Message>> Function(DateResultsSearchCall) respond;
  final calls = <DateResultsSearchCall>[];

  @override
  Future<List<Message>> search({
    required String conversationID,
    required ChatHistorySearchQuery query,
    required int pageIndex,
    int count = 30,
  }) {
    final call = (
      conversationID: conversationID,
      query: query,
      pageIndex: pageIndex,
      count: count,
    );
    calls.add(call);
    return respond(call);
  }
}

const dateResultsConversationID = 'date-search-conversation';
const dateResultsChannel = MethodChannel('flutter_openim_sdk');
final dateResultsSelectedDate = DateTime(2026, 10, 2, 14, 35);
final dateResultsDayStart = DateTime(2026, 10, 2);
final dateResultsDayEnd = DateTime(2026, 10, 3);

Message dateResultsMessage(String id, {int? sentAt}) => Message.fromJson({
      'clientMsgID': id,
      'contentType': MessageType.text,
      'sessionType': ConversationType.single,
      'sendID': 'member-1',
      'recvID': 'self',
      'senderNickname': '213123',
      'sendTime': sentAt ?? DateTime(2026, 10, 2, 8, 18).millisecondsSinceEpoch,
      'seq': 1,
      'status': MessageStatus.succeeded,
      'textElem': {'content': '消息 $id'},
    });

Future<void> setUpDateResultsSession() async {
  Get.testMode = true;
  OpenIM.iMManager.userID = 'self';
  OpenIM.iMManager.userInfo = UserInfo(userID: 'self', nickname: 'Self');
  OpenIM.iMManager.token = 'date-results-session';
  SharedPreferences.setMockInitialValues({});
  await SpUtil().init();
}

void resetDateResultsSession() {
  Get.reset();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(dateResultsChannel, null);
}

Future<void> mountDateResults(
    WidgetTester tester, DateResultsSearchSource source,
    {Brightness brightness = Brightness.light,
    bool settle = true,
    double textScale = 1,
    Size viewport = const Size(390, 844),
    Locale locale = const Locale('zh', 'CN'),
    String? fontFamily,
    bool mainSearch = false,
    GlobalKey? captureKey}) async {
  final wasDark = Styles.isDark;
  Styles.isDark = brightness == Brightness.dark;
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(() => Styles.isDark = wasDark);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: brightness,
        fontFamily: fontFamily,
        colorScheme: ColorScheme.fromSeed(
            seedColor: AppTokens.accent, brightness: brightness),
      ),
      translations: TranslationService(),
      locale: locale,
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: RepaintBoundary(
        key: captureKey,
        child: ChatHistoryResultsPage(
          conversationID: dateResultsConversationID,
          isGroup: mainSearch,
          category: mainSearch ? null : ChatHistoryCategory.date,
          date: mainSearch ? null : dateResultsSelectedDate,
          // Main-search drafts must not silently restrict a calendar result.
          initialQuery: 'unrelated inherited keyword',
          source: source,
        ),
      ),
    ),
  ));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void expectDateResultsScope(DateResultsSearchCall call,
    {required int pageIndex}) {
  expect(call.conversationID, dateResultsConversationID);
  expect(call.pageIndex, pageIndex);
  expect(call.count, 30);
  expect(call.query.keyword, isEmpty);
  expect(call.query.senderIDs, isEmpty);
  expect(call.query.messageTypes, isEmpty);
  expect(call.query.sdkMessageTypes, isNotEmpty);
  expect(call.query.startDate, dateResultsDayStart);
  expect(call.query.endDate, dateResultsDayStart);
  expect(call.query.localStart, dateResultsDayStart);
  expect(call.query.localEndExclusive, dateResultsDayEnd);
  expect(call.query.searchTimePosition,
      dateResultsDayEnd.millisecondsSinceEpoch ~/ 1000);
  expect(call.query.searchTimePeriod,
      dateResultsDayEnd.difference(dateResultsDayStart).inSeconds);
}

Future<void> unmountDateResults(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}
