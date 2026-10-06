import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/pages/chat/chat_setup/chat_setup_logic.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/chat/chat_entry_sdk.dart';

class _Chat extends GetxController implements ChatLogic {
  int clears = 0;
  @override
  void clearAllMessage() => clears++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Conversations extends EntryTestConversation {
  int pins = 0;
  int mutes = 0;
  Completer<void>? mutedReply;

  @override
  Future<void> setPinned(ConversationInfo info, bool pinned) async {
    pins++;
    info.isPinned = pinned;
  }

  @override
  Future<void> setNotDisturb(ConversationInfo info, bool enabled) async {
    mutes++;
    await mutedReply?.future;
    info.recvMsgOpt = enabled ? 2 : 0;
  }
}

ConversationInfo _conversation({bool pinned = false, int muted = 0}) =>
    ConversationInfo(
        conversationID: 'si_owner_peer',
        conversationType: ConversationType.single,
        userID: 'peer',
        showName: '原资料',
        isPinned: pinned,
        recvMsgOpt: muted);

Future<void> _identity({String owner = 'owner', String suffix = ''}) async {
  OpenIM.iMManager.userID = owner;
  OpenIM.iMManager.userInfo = UserInfo(userID: owner);
  await DataSp.putLoginCertificate(LoginCertificate.fromJson({
    'userID': owner,
    'imToken': 'im-token$suffix',
    'chatToken': 'chat-token$suffix',
  }));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  late _Chat chat;
  late EntryTestIM im;
  late _Conversations conversations;
  late Completer<Object?> initialRead;
  late Completer<Object?> clearReply;
  late List<MethodCall> requests;
  late ChatSetupLogic logic;

  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await _identity();
    Get.put<AppController>(EntryTestApp());
    im = EntryTestIM();
    Get.put<IMController>(im);
    GetTags.createChatTag();
    chat = _Chat();
    Get.put<ChatLogic>(chat, tag: GetTags.chat);
    conversations = _Conversations();
    Get.put<ConversationLogic>(conversations);
    requests = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) {
      requests.add(call);
      if (call.method == 'getOneConversation') {
        return initialRead.future.then((value) {
          if (value is PlatformException) throw value;
          return value;
        });
      }
      if (call.method == 'clearConversationAndDeleteAllMsg') {
        return clearReply.future;
      }
      return Future<Object?>.value();
    });
  });

  tearDown(() async {
    await EasyLoading.dismiss(animation: false);
    await LoadingView.singleton.dismiss();
    Get.reset();
    while (GetTags.chat != null) {
      GetTags.destroyChatTag();
    }
    if (!initialRead.isCompleted) {
      initialRead.complete(jsonEncode(_conversation().toJson()));
    }
    if (!clearReply.isCompleted) clearReply.complete(null);
    if (conversations.mutedReply?.isCompleted == false) {
      conversations.mutedReply!.complete();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
  });

  Future<void> mount(WidgetTester tester) async {
    // Replies belong to the widget test's fake async zone, just like the SDK
    // call that awaits them. Creating these in setUp leaves their continuations
    // outside the clock advanced by tester.pump.
    initialRead = Completer<Object?>();
    clearReply = Completer<Object?>();
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        builder: EasyLoading.init(),
        defaultTransition: Transition.noTransition,
        initialRoute: '/home',
        getPages: [
          GetPage(name: '/home', page: () => const Scaffold()),
          GetPage(
              name: '/setup-probe',
              page: () => const Scaffold(body: Text('设置')),
              binding: BindingsBuilder(() {
                logic = Get.put(ChatSetupLogic());
              })),
        ],
      ),
    ));
    await tester.pumpAndSettle();
    Get.toNamed<void>('/setup-probe',
        arguments: {'conversationInfo': _conversation()});
    await tester.pumpAndSettle();
    expect(requests.where((call) => call.method == 'getOneConversation'),
        hasLength(1));
  }

  testWidgets('initial failure retains seed and later SDK updates still work',
      (tester) async {
    await mount(tester);
    initialRead.complete(PlatformException(code: 'NETWORK'));
    await tester.pumpAndSettle();
    expect(logic.conversationInfo.value.showName, '原资料');
    im.conversationChangedSubject.add([_conversation(pinned: true)]);
    await tester.pump();
    expect(logic.isPinned, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('pending muted save keeps newer friend profile information',
      (tester) async {
    await mount(tester);
    conversations.mutedReply = Completer<void>();
    final save = logic.setMuted(true);
    im.friendInfoChangedSubject.add(FriendInfo(
        userID: 'peer',
        nickname: '新昵称',
        faceURL: 'https://avatar.test/new.png'));
    await tester.pump();
    expect(logic.conversationInfo.value.showName, '新昵称');
    conversations.mutedReply!.complete();
    await save;
    expect(logic.isMuted, isTrue);
    expect(logic.conversationInfo.value.showName, '新昵称');
    expect(logic.conversationInfo.value.faceURL, 'https://avatar.test/new.png');
    initialRead.complete(jsonEncode(_conversation().toJson()));
    await tester.pump();
    expect(logic.isMuted, isTrue);
    expect(logic.conversationInfo.value.showName, '新昵称');
  });

  testWidgets('pending muted save cannot overwrite a newer conversation event',
      (tester) async {
    await mount(tester);
    conversations.mutedReply = Completer<void>();
    final save = logic.setMuted(true);
    im.conversationChangedSubject.add([_conversation(muted: 0)]);
    await tester.pump();
    conversations.mutedReply!.complete();
    await save;
    expect(logic.isMuted, isFalse);
    initialRead.complete(jsonEncode(_conversation(muted: 2).toJson()));
    await tester.pump();
    expect(logic.isMuted, isFalse);
  });

  testWidgets(
      'late initial read cannot overwrite SDK event or completed switch',
      (tester) async {
    await mount(tester);
    im.conversationChangedSubject.add([_conversation(muted: 2)]);
    await tester.pump();
    await logic.setPinned(true);
    initialRead.complete(jsonEncode(_conversation().toJson()));
    await tester.pump();
    expect(logic.isMuted, isTrue);
    expect(logic.isPinned, isTrue);
    expect(conversations.pins, 1);
  });

  for (final close in [false, true]) {
    testWidgets(
        'pending muted save cannot write page state after ${close ? 'close' : 'token rotation'}',
        (tester) async {
      await mount(tester);
      conversations.mutedReply = Completer<void>();
      final save = logic.setMuted(true);
      expect(logic.updating.value, isTrue);
      if (close) {
        logic.onClose();
      } else {
        await _identity(suffix: '-new');
      }
      conversations.mutedReply!.complete();
      await save;
      expect(logic.isMuted, isFalse);
      expect(logic.updating.value, isTrue);
      await logic.setPinned(true);
      await logic.setMuted(true);
      expect(conversations.pins, 0);
      expect(conversations.mutes, 1);
      initialRead.complete(jsonEncode(_conversation(pinned: true).toJson()));
      await tester.pump();
      expect(logic.isPinned, isFalse);
    });
  }

  testWidgets(
      'clear guards repeat confirmation and clears only after SDK success',
      (tester) async {
    await mount(tester);
    final clear = logic.clearHistory();
    await tester.pumpAndSettle();
    await logic.clearHistory();
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(logic.clearing.value, isTrue);
    await tester.tap(find.byType(CupertinoDialogAction).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5));
    await logic.clearHistory();
    expect(
        requests
            .where((call) => call.method == 'clearConversationAndDeleteAllMsg'),
        hasLength(1));
    expect(chat.clears, 0);
    clearReply.complete(null);
    await tester.pump();
    await clear;
    expect(chat.clears, 1);
    expect(logic.clearing.value, isFalse);
  });

  testWidgets(
      'account change during confirmation does not invoke destructive SDK call',
      (tester) async {
    await mount(tester);
    final clear = logic.clearHistory();
    await tester.pumpAndSettle();
    await _identity(owner: 'next-owner');
    await tester.tap(find.byType(CupertinoDialogAction).last);
    await tester.pumpAndSettle();
    await clear;
    expect(
        requests
            .where((call) => call.method == 'clearConversationAndDeleteAllMsg'),
        isEmpty);
    expect(chat.clears, 0);
  });

  testWidgets('closed setup does not clear chat after delayed SDK completion',
      (tester) async {
    await mount(tester);
    final clear = logic.clearHistory();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CupertinoDialogAction).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5));
    logic.onClose();
    clearReply.complete(null);
    await tester.pump();
    await clear;
    expect(chat.clears, 0);
    expect(logic.clearing.value, isTrue);
  });

  testWidgets('report confirmation is single and can reopen after cancellation',
      (tester) async {
    await mount(tester);
    initialRead.complete(jsonEncode(_conversation().toJson()));
    await tester.pump();
    final report = logic.reportConversation();
    await tester.pumpAndSettle();
    await logic.reportConversation();
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.text('如需投诉此聊天，请联系人工客服，并提供对方账号：peer。'), findsOneWidget);
    expect(find.byKey(const ValueKey('customer-service-sheet')), findsNothing);
    await tester.tap(find.byType(CupertinoDialogAction).first);
    await tester.pumpAndSettle();
    await report;
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(find.byKey(const ValueKey('customer-service-sheet')), findsNothing);

    final reopened = logic.reportConversation();
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.text('如需投诉此聊天，请联系人工客服，并提供对方账号：peer。'), findsOneWidget);
    await tester.tap(find.byType(CupertinoDialogAction).first);
    await tester.pumpAndSettle();
    await reopened;
    expect(find.byKey(const ValueKey('customer-service-sheet')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final changeAccount in [false, true]) {
    testWidgets(
        'report cannot open customer service after ${changeAccount ? 'account change' : 'token rotation'}',
        (tester) async {
      await mount(tester);
      initialRead.complete(jsonEncode(_conversation().toJson()));
      await tester.pump();
      final report = logic.reportConversation();
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      await _identity(
          owner: changeAccount ? 'next-owner' : 'owner', suffix: '-new');
      await tester.tap(find.byType(CupertinoDialogAction).last);
      await tester.pumpAndSettle();
      await report;
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(
          find.byKey(const ValueKey('customer-service-sheet')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
