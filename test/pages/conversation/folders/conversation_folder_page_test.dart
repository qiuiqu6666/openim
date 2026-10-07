import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/conversation/conversation_organizer.dart';
import 'package:openim/pages/conversation/conversation_view.dart';
import 'package:openim/pages/conversation/folders/conversation_folder_bar.dart';
import 'package:openim/pages/conversation/folders/folder_name_dialog.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../support/conversation_live_fixture.dart';

ChatFolder _folder(String id, String name) => ChatFolder.fromJson({
      'id': id,
      'name': name,
      'sortOrder': 0,
      'createdAt': 1,
      'updatedAt': 1,
    });

ConversationInfo _conversation(String id,
        {bool group = false, int unread = 0, bool muted = false}) =>
    ConversationInfo(
      conversationID: id,
      conversationType:
          group ? ConversationType.superGroup : ConversationType.single,
      userID: group ? null : 'friend-$id',
      groupID: group ? 'group-$id' : null,
      showName: group ? '群聊 $id' : '联系人 $id',
      unreadCount: unread,
      recvMsgOpt: muted ? 2 : 0,
      latestMsgSendTime: 1,
      latestMsg: Message.fromJson({
        'contentType': MessageType.text,
        'sendID': 'friend-$id',
        'textElem': {'content': '你好'},
      }),
    );

class _Conversations extends GetxController
    with ConversationLiveFixture
    implements ConversationLogic {
  @override
  final list = <ConversationInfo>[].obs;
  @override
  final folders = <ChatFolder>[].obs;
  @override
  final states = <String, ChatConversationState>{}.obs;
  @override
  final organizerLoading = false.obs;
  @override
  final organizerError = RxnString();
  @override
  final popCtrl = CustomPopupMenuController();
  final archivedIDs = <String>{};
  final membership = <String, String?>{};
  final createdNames = <String>[];
  final organizerUpdates = <({String id, String? folderID, bool archived})>[];
  final openedIDs = <String>[];
  @override
  bool get isSessionActive => true;
  @override
  String? get imSdkStatus => null;
  @override
  bool get isFailedSdkStatus => false;
  @override
  bool get reInstall => false;
  @override
  bool isArchived(ConversationInfo info) =>
      archivedIDs.contains(info.conversationID);
  @override
  bool isGroupChat(ConversationInfo info) => info.isGroupChat;
  @override
  bool isNotDisturb(ConversationInfo info) => info.recvMsgOpt == 2;
  @override
  String? folderID(ConversationInfo info) => membership[info.conversationID];
  @override
  String getShowName(ConversationInfo info) => info.showName ?? '';
  @override
  String getContent(ConversationInfo info) => IMUtils.parseMsg(info.latestMsg!);
  @override
  String getTime(ConversationInfo info) => '18:29';
  @override
  int getUnreadCount(ConversationInfo info) => info.unreadCount;
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
  Future<void> refreshOrganizer() async {}

  @override
  Future<bool> createFolder(String name) async {
    createdNames.add(name);
    folders.add(_folder('created-${createdNames.length}', name));
    return true;
  }

  @override
  Future<bool> updateOrganizer(ConversationInfo info,
      {required String? folderID, required bool archived}) async {
    organizerUpdates
        .add((id: info.conversationID, folderID: folderID, archived: archived));
    membership[info.conversationID] = folderID;
    if (archived) {
      archivedIDs.add(info.conversationID);
    } else {
      archivedIDs.remove(info.conversationID);
    }
    list.refresh();
    return true;
  }

  @override
  void toChat(
      {bool offUntilHome = true,
      String? userID,
      String? groupID,
      String? nickname,
      String? faceURL,
      int? sessionType,
      ConversationInfo? conversationInfo,
      Message? searchMessage}) {
    openedIDs.add(conversationInfo!.conversationID);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  void onClose() {
    popCtrl.dispose();
    super.onClose();
  }
}

final _exportPreview = Platform.environment['EXPORT_FOLDER_PREVIEW'] == '1' ||
    const String.fromEnvironment('EXPORT_FOLDER_PREVIEW') == '1';
bool _previewFontsLoaded = false;

ThemeData _previewTheme(bool dark) {
  final brightness = dark ? Brightness.dark : Brightness.light;
  final surface = dark ? const Color(0xFF202A36) : Colors.white;
  final foreground = dark ? const Color(0xFFE8EDF5) : const Color(0xFF0C1C33);
  final fontFamily = _previewFontsLoaded ? 'FolderPreviewFont' : null;
  final labelStyle = TextStyle(
      color: CupertinoColors.label, fontSize: 17.sp, fontFamily: fontFamily);
  return ThemeData(
    brightness: brightness,
    fontFamily: fontFamily,
    colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0089FF),
            brightness: brightness,
            surface: surface)
        .copyWith(onSurface: foreground),
    scaffoldBackgroundColor:
        dark ? const Color(0xFF141D27) : const Color(0xFFF8F9FA),
    canvasColor: surface,
    cardColor: surface,
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: brightness,
      primaryColor: CupertinoColors.systemBlue,
      barBackgroundColor: surface,
      applyThemeToAll: true,
      textTheme: const CupertinoTextThemeData().copyWith(
        navActionTextStyle: labelStyle,
        actionTextStyle: labelStyle.copyWith(color: CupertinoColors.systemBlue),
        textStyle: labelStyle,
        navLargeTitleTextStyle: labelStyle.copyWith(fontSize: 20.sp),
        navTitleTextStyle: labelStyle,
        pickerTextStyle: labelStyle,
        tabLabelTextStyle: labelStyle,
        dateTimePickerTextStyle: labelStyle,
      ),
    ),
  );
}

Future<void> _mount(WidgetTester tester, _Conversations conversations,
    {bool groupChats = false,
    bool dark = false,
    GlobalKey? boundaryKey}) async {
  Get.testMode = true;
  OpenIM.iMManager.userID = 'viewer';
  Styles.isDark = dark;
  addTearDown(() {
    Styles.isDark = false;
    Get.reset();
  });
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    final navigators = tester
        .stateList<NavigatorState>(find.byType(Navigator, skipOffstage: false));
    if (navigators.isNotEmpty) {
      navigators.first.popUntil((route) => route.isFirst);
    }
    // Let route.completed finish through frames; do not await the preview's
    // pending Future across the teardown fake-async boundary.
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  Get.put<ConversationLogic>(conversations);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => RepaintBoundary(
      key: boundaryKey,
      child: GetMaterialApp(
        debugShowCheckedModeBanner: false,
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: boundaryKey != null
            ? _previewTheme(dark)
            : ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        builder: (_, child) => MediaQuery(
          data: const MediaQueryData(
              size: Size(375, 812),
              padding: EdgeInsets.only(top: 24, bottom: 34)),
          child: child!,
        ),
        home: ConversationPage(groupChats: groupChats),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

_Conversations _mixedFolder() {
  final conversations = _Conversations()
    ..folders.add(_folder('work', '工作'))
    ..list.addAll([
      _conversation('single', unread: 2, muted: true),
      _conversation('group', group: true, unread: 3, muted: true),
      _conversation('archived', unread: 97),
    ])
    ..archivedIDs.add('archived');
  for (final info in conversations.list) {
    conversations.membership[info.conversationID] = 'work';
  }
  return conversations;
}

Finder _row(String id) => find.byKey(ValueKey(id));
Finder _folderLabel(String name) => find.descendant(
    of: find.byType(ConversationFolderBar), matching: find.text(name));

Future<void> _enablePeekHistory() async {
  SharedPreferences.setMockInitialValues({});
  await DataSp.init();
  await DataSp.putLoginCertificate(LoginCertificate.fromJson({
    'userID': 'viewer',
    'chatToken': 'folder-preview-token',
    'imToken': 'folder-preview-im-token',
  }));
  ChatHistoryCache.clear();
  const channel = MethodChannel('flutter_openim_sdk');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    expect(call.method, 'getAdvancedHistoryMessageList');
    return jsonEncode(AdvancedMessage(
      messageList: [
        Message.fromJson({
          'clientMsgID': 'folder-preview-message',
          'contentType': MessageType.text,
          'sessionType': ConversationType.single,
          'sendID': 'friend-single',
          'recvID': 'viewer',
          'senderNickname': '联系人',
          'sendTime': 1,
          'seq': 1,
          'status': MessageStatus.succeeded,
          'isRead': false,
          'textElem': {'content': '来自 SDK 的历史消息'},
          'exMap': {'showTime': false},
        }),
      ],
      isEnd: true,
      errCode: 0,
    ).toJson());
  });
  addTearDown(() {
    ChatHistoryCache.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}

void main() {
  for (final groupChats in [false, true]) {
    testWidgets(
        'All follows its tab while folders include both chat types ($groupChats)',
        (tester) async {
      final conversations = _mixedFolder();
      await _mount(tester, conversations, groupChats: groupChats);
      expect(_row(groupChats ? 'group' : 'single'), findsOneWidget);
      expect(_row(groupChats ? 'single' : 'group'), findsNothing);
      expect(_row('archived'), findsNothing);

      await tester.tap(_folderLabel('工作'));
      await tester.pumpAndSettle();
      expect(_row('single'), findsOneWidget);
      expect(_row('group'), findsOneWidget);
      expect(_row('archived'), findsNothing);
      expect(find.text('归档'), findsNothing);

      await tester.tap(_row('single'));
      await tester.pumpAndSettle();
      expect(conversations.openedIDs, ['single']);
      await tester.tap(_folderLabel('全部'));
      await tester.pumpAndSettle();
      expect(_row(groupChats ? 'group' : 'single'), findsOneWidget);
      expect(_row(groupChats ? 'single' : 'group'), findsNothing);
      expect(conversations.organizerUpdates, isEmpty);
    });
  }

  testWidgets(
      'folder badge excludes archives and counts notification policy correctly',
      (tester) async {
    final conversations = _mixedFolder();
    await _mount(tester, conversations);
    final bar = find.byType(ConversationFolderBar);
    final badgeText = find.descendant(of: bar, matching: find.text('5'));
    expect(badgeText, findsOneWidget);
    expect(find.descendant(of: bar, matching: find.text('99+')), findsNothing);
    BoxDecoration badgeDecoration() => tester
        .widget<Container>(find
            .ancestor(of: badgeText, matching: find.byType(Container))
            .first)
        .decoration! as BoxDecoration;
    expect(badgeDecoration().color, const Color(0xFFA8A8AE));

    conversations.list
        .firstWhere((info) => info.conversationID == 'group')
        .recvMsgOpt = 0;
    conversations.list.refresh();
    await tester.pumpAndSettle();
    expect(badgeText, findsOneWidget);
    expect(badgeDecoration().color, const Color(0xFFFF524B));
  });

  testWidgets('an empty selected folder explains how to add conversations',
      (tester) async {
    final conversations = _mixedFolder()..folders.add(_folder('empty', '空分组'));
    await _mount(tester, conversations);
    await tester.tap(_folderLabel('空分组'));
    await tester.pumpAndSettle();
    expect(find.text('分组内暂无会话'), findsOneWidget);
    expect(find.text('可将会话添加到此分组'), findsOneWidget);
    expect(find.byType(Slidable), findsNothing);
    await tester.tap(_folderLabel('全部'));
    await tester.pumpAndSettle();
    expect(_row('single'), findsOneWidget);
    expect(find.text('暂无会话，可将会话添加到分组'), findsNothing);
  });

  testWidgets('a row can create its first folder and save its membership',
      (tester) async {
    await _enablePeekHistory();
    final conversations = _Conversations()..list.add(_conversation('single'));
    await _mount(tester, conversations);
    expect(_folderLabel('全部'), findsNothing);
    await tester.longPress(_row('single'));
    await tester.pumpAndSettle();
    expect(find.text('来自 SDK 的历史消息'), findsOneWidget);
    await tester.tap(
        find.byKey(const ValueKey('conversation-peek-action-addToFolder')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('conversation-peek-card')), findsNothing);
    await tester.tap(find.text('新建分组'));
    await tester.pumpAndSettle();
    expect(find.byType(FolderNameDialog), findsOneWidget);
    await tester.enterText(find.byType(CupertinoTextField), '生活');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(conversations.createdNames, ['生活']);
    expect(conversations.organizerUpdates,
        [(id: 'single', folderID: 'created-1', archived: false)]);
    expect(conversations.membership['single'], 'created-1');
    expect(_folderLabel('生活'), findsOneWidget);
    expect(_folderLabel('全部'), findsOneWidget);
    expect(find.byType(FolderNameDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a folder swipe action saves null membership and restores All',
      (tester) async {
    final conversations = _mixedFolder();
    await _mount(tester, conversations);
    await tester.tap(_folderLabel('工作'));
    await tester.pumpAndSettle();
    final row = _row('single');
    final controller = tester.widget<Slidable>(row).controller!;
    final opening = controller.openStartActionPane();
    await tester.pumpAndSettle();
    await opening;
    final remove = find.descendant(of: row, matching: find.text('移出分组'));
    expect(remove, findsOneWidget);
    await tester.tap(remove);
    await tester.pumpAndSettle();

    expect(conversations.organizerUpdates,
        [(id: 'single', folderID: null, archived: false)]);
    expect(conversations.membership['single'], isNull);
    expect(_row('single'), findsNothing);
    expect(_row('group'), findsOneWidget);
    await tester.tap(_folderLabel('全部'));
    await tester.pumpAndSettle();
    expect(_row('single'), findsOneWidget);
    expect(conversations.openedIDs, isEmpty);

    // Filtered rows own fresh slide controllers and no stale auto-close listeners.
    final restoredController =
        tester.widget<Slidable>(_row('single')).controller!;
    expect(identical(restoredController, controller), isFalse);
    final reopening = restoredController.openStartActionPane();
    await tester.pumpAndSettle();
    await reopening;
    final closing = restoredController.close();
    await tester.pumpAndSettle();
    await closing;
    await tester.tap(_folderLabel('工作'));
    await tester.pumpAndSettle();
    final groupController = tester.widget<Slidable>(_row('group')).controller!;
    final openingGroup = groupController.openStartActionPane();
    await tester.pumpAndSettle();
    await openingGroup;
    final closingGroup = groupController.close();
    await tester.pumpAndSettle();
    await closingGroup;
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the existing title double tap still scrolls the feed to its start',
      (tester) async {
    final conversations = _Conversations()
      ..list.addAll([
        for (var index = 0; index < 20; index++) _conversation('single-$index')
      ]);
    await _mount(tester, conversations);
    final list = find.byWidgetPredicate((widget) =>
        widget is ListView && widget.scrollDirection == Axis.vertical);
    await tester.drag(list, const Offset(0, -500));
    await tester.pumpAndSettle();
    final controller = tester.widget<ListView>(list).controller!;
    expect(controller.offset, greaterThan(0));
    final title = find.byKey(const ValueKey('main-tab-title-text'));
    await tester.tap(title);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(0, .01));
    expect(conversations.openedIDs, isEmpty);
    expect(conversations.createdNames, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('export actual folder menus and name dialogs for visual review',
      (tester) async {
    await tester.runAsync(() async {
      final font = File('C:/Windows/Fonts/msyh.ttc');
      if (await font.exists()) {
        final bytes = ByteData.sublistView(await font.readAsBytes());
        for (final family in [
          'FolderPreviewFont',
          'CupertinoSystemText',
          'CupertinoSystemDisplay',
        ]) {
          await (FontLoader(family)..addFont(Future.value(bytes))).load();
        }
        await (FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
            .load();
        _previewFontsLoaded = true;
      }
    });
    final conversations = _mixedFolder();
    for (final dark in [false, true]) {
      final key = GlobalKey();
      await _mount(tester, conversations, dark: dark, boundaryKey: key);
      await tester.tap(_folderLabel('工作'));
      await tester.pumpAndSettle();
      await tester.longPress(_folderLabel('工作'));
      await tester.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final menu =
          (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();
      expect(find.byType(FolderNameDialog), findsOneWidget);
      final dialog =
          (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final paint = Paint();
        canvas.drawImage(menu, Offset.zero, paint);
        canvas.drawImage(dialog, const Offset(375, 0), paint);
        final picture = recorder.endRecording();
        final combined = await picture.toImage(750, 812);
        final bytes = await combined.toByteData(format: ui.ImageByteFormat.png);
        final file =
            File('docs/previews/folders-${dark ? 'dark' : 'light'}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        combined.dispose();
        picture.dispose();
        menu.dispose();
        dialog.dispose();
      });
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  }, skip: !_exportPreview);
}
