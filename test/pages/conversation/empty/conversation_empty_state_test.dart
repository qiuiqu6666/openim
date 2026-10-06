import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/conversation/conversation_organizer.dart';
import 'package:openim/pages/conversation/conversation_view.dart';
import 'package:openim/pages/conversation/empty/conversation_empty_state.dart';
import 'package:openim/pages/conversation/folders/conversation_folder_bar.dart';
import 'package:openim_common/openim_common.dart';

import '../../../support/conversation_live_fixture.dart';

class _Conversations extends GetxController
    with ConversationLiveFixture
    implements ConversationLogic {
  @override
  final list = <ConversationInfo>[].obs;
  @override
  final folders = <ChatFolder>[].obs;
  @override
  final organizerLoading = false.obs;
  @override
  final organizerError = RxnString();
  @override
  final popCtrl = CustomPopupMenuController();
  final connection = 'ready'.obs;
  final feedReady = true.obs;
  final archivedIDs = <String>{};
  int listRefreshes = 0;
  int organizerRefreshes = 0;

  @override
  String? get imSdkStatus =>
      connection.value == 'ready' ? null : connection.value;
  @override
  bool get isFailedSdkStatus => connection.value == 'failed';
  @override
  bool get isSessionActive => true;
  @override
  bool get reInstall => false;
  @override
  bool get canShowEmptyFeed => feedReady.value;
  @override
  bool isArchived(ConversationInfo info) =>
      archivedIDs.contains(info.conversationID);
  @override
  bool isGroupChat(ConversationInfo info) => info.isGroupChat;
  @override
  bool isNotDisturb(ConversationInfo info) => false;
  @override
  String? folderID(ConversationInfo info) => null;
  @override
  int getUnreadCount(ConversationInfo info) => info.unreadCount;
  @override
  String getShowName(ConversationInfo info) => info.showName ?? '';
  @override
  String getContent(ConversationInfo info) => IMUtils.parseMsg(info.latestMsg!);
  @override
  String getTime(ConversationInfo info) => '18:29';
  @override
  String? getPrefixTag(ConversationInfo info) => '';
  @override
  void globalSearch() {}
  @override
  void addFriend() {}
  @override
  void addGroup() {}
  @override
  void createGroup() {}
  @override
  Future<void> onRefresh() async {
    listRefreshes++;
    feedReady.value = true;
  }

  @override
  Future<void> refreshOrganizer() async {
    organizerRefreshes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  void onClose() {
    popCtrl.dispose();
    super.onClose();
  }
}

ConversationInfo _conversation(String id, {bool group = false}) =>
    ConversationInfo(
      conversationID: id,
      conversationType:
          group ? ConversationType.superGroup : ConversationType.single,
      userID: group ? null : 'friend-$id',
      groupID: group ? 'group-$id' : null,
      showName: group ? '群聊 $id' : '联系人 $id',
      latestMsgSendTime: 1,
      latestMsg: Message.fromJson({
        'contentType': MessageType.text,
        'sendID': 'friend-$id',
        'textElem': {'content': '你好'},
      }),
    );

const _previewOutput = String.fromEnvironment('CONVERSATION_EMPTY_PREVIEW');
bool _previewFontsLoaded = false;

Future<void> _mount(
  WidgetTester tester,
  Widget home, {
  _Conversations? conversations,
  bool dark = false,
  Locale locale = const Locale('zh', 'CN'),
  Size size = const Size(375, 812),
  double textScale = 1,
  GlobalKey? boundaryKey,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Styles.isDark = dark;
  if (conversations != null) Get.put<ConversationLogic>(conversations);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: locale,
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        fontFamily: _previewFontsLoaded ? 'EmptyPreviewFont' : null,
      ),
      builder: (_, child) => MediaQuery(
        data: MediaQueryData(
            size: size, textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: RepaintBoundary(key: boundaryKey, child: home),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'empty-state-viewer';
  });
  tearDown(() {
    Styles.isDark = false;
    Get.reset();
  });

  testWidgets('empty group page shows the supplied mascot and guidance',
      (tester) async {
    await _mount(tester, const ConversationPage(groupChats: true),
        conversations: _Conversations());

    expect(find.text('暂无群聊'), findsOneWidget);
    expect(find.text('点击右上角“+”创建或加入群聊'), findsOneWidget);
    final image = tester.widget<Image>(find.descendant(
      of: find.byType(ConversationEmptyState),
      matching: find.byType(Image),
    ));
    final provider = image.image is ResizeImage
        ? (image.image as ResizeImage).imageProvider
        : image.image;
    expect((provider as AssetImage).assetName,
        'lib/pages/conversation/empty/assets/99chat_empty.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('group empty state follows the filtered live conversation list',
      (tester) async {
    final conversations = _Conversations()..list.add(_conversation('single'));
    await _mount(tester, const ConversationPage(groupChats: true),
        conversations: conversations);
    expect(find.text('暂无群聊'), findsOneWidget);
    expect(find.byKey(const ValueKey('single')), findsNothing);

    conversations.list.add(_conversation('group', group: true));
    await tester.pumpAndSettle();
    expect(find.byType(ConversationEmptyState), findsNothing);
    expect(find.byKey(const ValueKey('group')), findsOneWidget);

    conversations.list.removeWhere((info) => info.isGroupChat);
    await tester.pumpAndSettle();
    expect(find.text('暂无群聊'), findsOneWidget);
    expect(find.byKey(const ValueKey('group')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('incomplete reads and SDK states do not claim no groups',
      (tester) async {
    final conversations = _Conversations();
    await _mount(tester, const ConversationPage(groupChats: true),
        conversations: conversations);
    conversations.feedReady.value = false;
    await tester.pump();
    expect(find.byType(ConversationEmptyState), findsNothing);
    conversations.feedReady.value = true;
    for (final status in ['connecting', 'syncing', 'failed']) {
      conversations.connection.value = status;
      // The busy header intentionally animates continuously while syncing.
      await tester.pump();
      expect(find.byType(ConversationEmptyState), findsNothing);
    }
    conversations.connection.value = 'ready';
    await tester.pumpAndSettle();
    expect(find.text('暂无群聊'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'pull refresh reloads empty feed and recovers failed initial reads',
      (tester) async {
    final conversations = _Conversations();
    await _mount(tester, const ConversationPage(groupChats: true),
        conversations: conversations);
    final scroll = find.descendant(
        of: find.byType(RefreshIndicator), matching: find.byType(Scrollable));
    expect(find.text('暂无群聊'), findsOneWidget);
    await tester.drag(scroll, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(conversations.listRefreshes, 1);
    expect(conversations.organizerRefreshes, 1);

    conversations.feedReady.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(ConversationEmptyState), findsNothing);
    await tester.drag(scroll, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(conversations.listRefreshes, 2);
    expect(conversations.organizerRefreshes, 2);
    expect(find.text('暂无群聊'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('archived group entry remains accessible when feed is empty',
      (tester) async {
    final conversations = _Conversations()
      ..list.add(_conversation('archived', group: true))
      ..archivedIDs.add('archived');
    await _mount(tester, const ConversationPage(groupChats: true),
        conversations: conversations);

    expect(find.text('归档'), findsOneWidget);
    expect(find.byType(ConversationEmptyState), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected empty folder shows folder guidance and restores All',
      (tester) async {
    final conversations = _Conversations()
      ..folders.add(ChatFolder.fromJson({
        'id': 'work',
        'name': '工作',
        'sortOrder': 0,
        'createdAt': 1,
        'updatedAt': 1,
      }))
      ..list.add(_conversation('group', group: true));
    await _mount(tester, const ConversationPage(groupChats: true),
        conversations: conversations);
    await tester.tap(find.descendant(
        of: find.byType(ConversationFolderBar), matching: find.text('工作')));
    await tester.pumpAndSettle();

    expect(find.text('分组内暂无会话'), findsOneWidget);
    expect(find.text('可将会话添加到此分组'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(ConversationFolderBar), matching: find.text('全部')));
    await tester.pumpAndSettle();
    expect(find.byType(ConversationEmptyState), findsNothing);
    expect(find.byKey(const ValueKey('group')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final groupChats in [false, true]) {
    testWidgets('empty page uses English copy for its tab ($groupChats)',
        (tester) async {
      await _mount(tester, ConversationPage(groupChats: groupChats),
          conversations: _Conversations(), locale: const Locale('en', 'US'));

      expect(find.text(groupChats ? 'No group chats yet' : 'No messages yet'),
          findsOneWidget);
      expect(
          find.text(groupChats
              ? 'Use + in the top right to create or join a group'
              : 'Add a friend to start chatting'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final dark in [false, true]) {
    testWidgets('empty component fits small, landscape and large text ($dark)',
        (tester) async {
      for (final size in [const Size(320, 568), const Size(568, 240)]) {
        await _mount(
          tester,
          const Scaffold(body: ConversationEmptyState(groupChats: true)),
          dark: dark,
          size: size,
          textScale: 2,
        );
        expect(find.text('暂无群聊'), findsOneWidget);
        expect(find.text('点击右上角“+”创建或加入群聊'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    });
  }

  testWidgets('export actual light and dark group empty pages', (tester) async {
    await tester.runAsync(() async {
      final font = File('C:/Windows/Fonts/msyh.ttc');
      if (await font.exists()) {
        await (FontLoader('EmptyPreviewFont')
              ..addFont(font.readAsBytes().then(ByteData.sublistView)))
            .load();
        await (FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
            .load();
        _previewFontsLoaded = true;
      }
    });
    final conversations = _Conversations();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final captured = <ui.Image>[];
    for (var index = 0; index < 2; index++) {
      final key = GlobalKey();
      await _mount(tester, const ConversationPage(groupChats: true),
          conversations: conversations, dark: index == 1, boundaryKey: key);
      final mascot = tester.widget<Image>(find.descendant(
          of: find.byType(ConversationEmptyState),
          matching: find.byType(Image)));
      await tester.runAsync(() async {
        await precacheImage(mascot.image, key.currentContext!);
        await precacheImage(
            const AssetImage('assets/images/home_nav_plus_99chat.png',
                package: 'openim_common'),
            key.currentContext!);
      });
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image =
          (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
      captured.add(image);
      canvas.drawImage(image, Offset(index * 375.0, 0), Paint());
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
    final picture = recorder.endRecording();
    await tester.runAsync(() async {
      final combined = await picture.toImage(750, 812);
      final data = await combined.toByteData(format: ui.ImageByteFormat.png);
      final file = File(_previewOutput);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      combined.dispose();
      picture.dispose();
      for (final image in captured) {
        image.dispose();
      }
    });
    expect(tester.takeException(), isNull);
  }, skip: _previewOutput.isEmpty);
}
