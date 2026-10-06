import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/conversation/conversation_organizer.dart';
import 'package:openim/pages/conversation/folders/conversation_folder_bar.dart';
import 'package:openim/pages/conversation/folders/conversation_folder_controller.dart';
import 'package:openim/pages/conversation/folders/folder_name_dialog.dart';
import 'package:openim_common/openim_common.dart';

ChatFolder _folder(String id, String name, {int sortOrder = 0}) =>
    ChatFolder.fromJson({
      'id': id,
      'name': name,
      'sortOrder': sortOrder,
      'createdAt': 1,
      'updatedAt': 2,
    });

class _FolderLogic extends GetxController implements ConversationLogic {
  @override
  final folders = <ChatFolder>[].obs;
  @override
  final list = <ConversationInfo>[].obs;
  @override
  final states = <String, ChatConversationState>{}.obs;

  final creates = <String>[];
  final renames = <({String id, String name})>[];
  final deletes = <String>[];
  final updates = <({String id, String? folderID, bool archived})>[];
  final orders = <List<String>>[];
  final events = <String>[];
  bool sessionActive = true;
  bool failCreate = false;
  bool failRename = false;
  bool failDelete = false;
  bool failReorder = false;
  Completer<void>? createGate;
  Completer<void>? reorderGate;
  List<ChatFolder>? orderAfterFailure;

  ConversationInfo seedChat({String? folderID, bool archived = false}) {
    final info = ConversationInfo(
      conversationID: 'chat',
      conversationType: ConversationType.single,
      userID: 'friend',
      showName: '朋友',
      unreadCount: 2,
      latestMsg: Message.fromJson({
        'contentType': MessageType.text,
        'textElem': {'content': '保留聊天记录'},
      }),
    );
    list.add(info);
    states[info.conversationID] = ChatConversationState.fromJson({
      'conversationID': info.conversationID,
      'folderID': folderID,
      'archived': archived,
      'version': 1,
    });
    return info;
  }

  @override
  bool get isSessionActive => sessionActive;
  @override
  String? folderID(ConversationInfo info) => states[info.conversationID]?.folderID;
  @override
  bool isArchived(ConversationInfo info) => states[info.conversationID]?.archived == true;
  @override
  String getShowName(ConversationInfo info) => info.showName ?? '';

  @override
  Future<bool> createFolder(String name) async {
    creates.add(name);
    events.add('create:$name');
    await createGate?.future;
    if (!sessionActive || failCreate) return false;
    folders.add(_folder('new-${creates.length}', name, sortOrder: folders.length));
    return true;
  }

  @override
  Future<bool> renameFolder(ChatFolder folder, String name) async {
    renames.add((id: folder.id, name: name));
    if (!sessionActive || failRename) return false;
    final index = folders.indexWhere((item) => item.id == folder.id);
    folders[index] = _folder(folder.id, name, sortOrder: folder.sortOrder);
    return true;
  }

  @override
  Future<bool> deleteFolder(ChatFolder folder) async {
    deletes.add(folder.id);
    if (!sessionActive || failDelete) return false;
    folders.removeWhere((item) => item.id == folder.id);
    for (final entry in states.entries.toList()) {
      if (entry.value.folderID != folder.id) continue;
      states[entry.key] = ChatConversationState.fromJson({
        'conversationID': entry.key,
        'folderID': null,
        'archived': entry.value.archived,
        'version': entry.value.version + 1,
      });
    }
    return true;
  }

  @override
  Future<bool> updateOrganizer(ConversationInfo info,
      {required String? folderID, required bool archived}) async {
    updates.add((id: info.conversationID, folderID: folderID, archived: archived));
    events.add('update:${info.conversationID}:$folderID:$archived');
    if (!sessionActive) return false;
    states[info.conversationID] = ChatConversationState.fromJson({
      'conversationID': info.conversationID,
      'folderID': folderID,
      'archived': archived,
      'version': (states[info.conversationID]?.version ?? 0) + 1,
    });
    return true;
  }

  @override
  Future<bool> reorderFolders(List<String> ids) async {
    orders.add(List.of(ids));
    await reorderGate?.future;
    if (!sessionActive) return false;
    if (failReorder) {
      // The real logic refreshes server order when a partial write fails.
      if (orderAfterFailure != null) folders.assignAll(orderAfterFailure!);
      return false;
    }
    final byID = {for (final folder in folders) folder.id: folder};
    folders.assignAll([
      for (var index = 0; index < ids.length; index++)
        _folder(ids[index], byID[ids[index]]!.name, sortOrder: index),
    ]);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Fixture {
  _Fixture(this.logic) : controller = ConversationFolderController(logic: logic);
  final _FolderLogic logic;
  final ConversationFolderController controller;
  late BuildContext context;
  Future<void>? pending;
  bool disposed = false;

  void start(Future<void> task) => pending = task;
  void dispose() {
    if (disposed) return;
    disposed = true;
    controller.dispose();
  }
}

Future<_Fixture> _mount(WidgetTester tester, _FolderLogic logic,
    {bool showBar = false, bool dark = false}) async {
  final fixture = _Fixture(logic);
  addTearDown(fixture.dispose);
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Styles.isDark = dark;
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      builder: EasyLoading.init(),
      home: Scaffold(body: Builder(builder: (context) {
        fixture.context = context;
        return AnimatedBuilder(
          animation: fixture.controller,
          builder: (_, __) => Column(children: [
            if (showBar)
              ConversationFolderBar(
                folders: fixture.controller.displayFolders,
                selectedFolderID: fixture.controller.selectedFolderID,
                unreadForFolder: (_) => 0,
                hasNotifiableUnreadForFolder: (_) => false,
                onSelectAll: () => fixture.start(fixture.controller.selectFolder(null)),
                onSelectFolder: (id) => fixture.start(fixture.controller.selectFolder(id)),
                onCreateFolder: () => fixture.start(fixture.controller.createFolder(context)),
                onFolderLongPress: (folder) => fixture.start(fixture.controller.manageFolder(context, folder)),
              ),
            Text('selected:${fixture.controller.selectedFolderID ?? 'all'}'),
          ]),
        );
      })),
    ),
  ));
  await tester.pumpAndSettle();
  return fixture;
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> _name(WidgetTester tester, String name) async {
  await tester.enterText(find.byType(CupertinoTextField), name);
  await _tap(tester, '确定');
}

Future<void> _startManage(WidgetTester tester, _Fixture fixture, String action) async {
  fixture.start(fixture.controller.manageFolder(fixture.context, fixture.logic.folders.first));
  await tester.pumpAndSettle();
  await _tap(tester, action);
}

Future<void> _startReorder(WidgetTester tester, _Fixture fixture) async {
  await _startManage(tester, fixture, '重新排序');
  await fixture.pending;
  expect(fixture.controller.reorderEditing, isTrue);
}

Future<void> _closeHost(WidgetTester tester, _Fixture fixture) async {
  EasyLoading.dismiss(animation: false);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  fixture.dispose();
  expect(tester.takeException(), isNull);
}

void main() {
  tearDown(() => Styles.isDark = false);

  testWidgets('empty picker creates a folder then moves and unarchives the chat', (tester) async {
    final logic = _FolderLogic();
    final chat = logic.seedChat(archived: true);
    final fixture = await _mount(tester, logic);
    fixture.start(fixture.controller.chooseFolder(fixture.context, chat));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    expect(find.text('新建分组'), findsOneWidget);
    await _tap(tester, '新建分组');
    expect(find.byType(FolderNameDialog), findsOneWidget);
    await _name(tester, '  家人  ');
    await fixture.pending;
    expect(logic.creates, ['家人']);
    expect(logic.events, ['create:家人', 'update:chat:new-1:false']);
    expect(logic.updates, [(id: 'chat', folderID: 'new-1', archived: false)]);
    expect(logic.folderID(chat), 'new-1');
    expect(logic.isArchived(chat), isFalse);
    expect(logic.list.single, same(chat));
    await _closeHost(tester, fixture);
  });

  testWidgets('the real folder bar plus creates and selects the new folder', (tester) async {
    final logic = _FolderLogic()..folders.add(_folder('a', '朋友'));
    final fixture = await _mount(tester, logic, showBar: true);
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    await _name(tester, '  工作  ');
    await fixture.pending;
    expect(logic.creates, ['工作']);
    expect(fixture.controller.selectedFolderID, 'new-1');
    expect(find.text('selected:new-1'), findsOneWidget);
    expect(logic.updates, isEmpty);
    await _closeHost(tester, fixture);
  });

  testWidgets('case and whitespace duplicates stay in the prompt without an API call', (tester) async {
    final logic = _FolderLogic()..folders.add(_folder('a', 'Work'));
    final fixture = await _mount(tester, logic);
    await fixture.controller.selectFolder('a');
    fixture.start(fixture.controller.createFolder(fixture.context));
    await tester.pumpAndSettle();
    await _name(tester, '  wOrK  ');
    expect(find.text('分组名称已存在'), findsOneWidget);
    expect(find.byType(FolderNameDialog), findsOneWidget);
    expect(logic.creates, isEmpty);
    expect(fixture.controller.selectedFolderID, 'a');
    await _tap(tester, '取消');
    await fixture.pending;
    logic.failCreate = true;
    fixture.start(fixture.controller.createFolder(fixture.context));
    await tester.pumpAndSettle();
    await _name(tester, 'Home');
    await fixture.pending;
    expect(logic.creates, ['Home']);
    expect(logic.folders.single.name, 'Work');
    expect(fixture.controller.selectedFolderID, 'a');
    expect(fixture.controller.busy, isFalse);
    await _closeHost(tester, fixture);
  });

  testWidgets('rename cancellation and failure retain selection, success keeps the ID', (tester) async {
    final logic = _FolderLogic()..folders.add(_folder('a', '朋友', sortOrder: 4));
    final fixture = await _mount(tester, logic);
    await fixture.controller.selectFolder('a');
    await _startManage(tester, fixture, '重命名');
    await tester.enterText(find.byType(CupertinoTextField), '同事');
    await _tap(tester, '取消');
    await fixture.pending;
    expect(logic.renames, isEmpty);
    expect(logic.folders.single.name, '朋友');
    expect(fixture.controller.selectedFolderID, 'a');

    await _startManage(tester, fixture, '重命名');
    await _name(tester, '  朋友  ');
    await fixture.pending;
    expect(logic.renames, isEmpty);

    logic.failRename = true;
    await _startManage(tester, fixture, '重命名');
    await _name(tester, '  同事  ');
    await fixture.pending;
    expect(logic.folders.single.name, '朋友');
    expect(fixture.controller.selectedFolderID, 'a');
    logic.failRename = false;
    await _startManage(tester, fixture, '重命名');
    await _name(tester, '  同事  ');
    await fixture.pending;
    expect(logic.renames, [(id: 'a', name: '同事'), (id: 'a', name: '同事')]);
    expect(logic.folders.single.name, '同事');
    expect(logic.folders.single.sortOrder, 4);
    expect(fixture.controller.selectedFolderID, 'a');
    await _closeHost(tester, fixture);
  });

  testWidgets('delete cancel and failure keep selection; confirmation retains all chats', (tester) async {
    final logic = _FolderLogic()..folders.add(_folder('a', '朋友'));
    final chat = logic.seedChat(folderID: 'a', archived: true);
    final originalMessage = chat.latestMsg;
    final fixture = await _mount(tester, logic);
    await fixture.controller.selectFolder('a');
    fixture.start(fixture.controller.deleteFolder(fixture.context, logic.folders.single));
    await tester.pumpAndSettle();
    expect(find.textContaining('不会删除聊天记录'), findsOneWidget);
    await _tap(tester, '取消');
    await fixture.pending;
    expect(logic.deletes, isEmpty);
    expect(fixture.controller.selectedFolderID, 'a');

    logic.failDelete = true;
    fixture.start(fixture.controller.deleteFolder(fixture.context, logic.folders.single));
    await tester.pumpAndSettle();
    await _tap(tester, '删除');
    await fixture.pending;
    expect(fixture.controller.selectedFolderID, 'a');
    expect(logic.folderID(chat), 'a');
    expect(logic.folders, hasLength(1));
    logic.failDelete = false;
    fixture.start(fixture.controller.deleteFolder(fixture.context, logic.folders.single));
    await tester.pumpAndSettle();
    await _tap(tester, '删除');
    await fixture.pending;
    expect(logic.deletes, ['a', 'a']);
    expect(logic.folders, isEmpty);
    expect(fixture.controller.selectedFolderID, isNull);
    expect(find.text('selected:all'), findsOneWidget);
    expect(logic.list.single, same(chat));
    expect(chat.latestMsg, same(originalMessage));
    expect(logic.folderID(chat), isNull);
    expect(logic.isArchived(chat), isTrue);
    await _closeHost(tester, fixture);
  });

  testWidgets('picker describes membership and selecting the current folder is a no-op', (tester) async {
    final logic = _FolderLogic()
      ..folders.addAll([_folder('a', '朋友'), _folder('b', '工作', sortOrder: 1)]);
    final chat = logic.seedChat(folderID: 'a');
    final fixture = await _mount(tester, logic, dark: true);
    fixture.start(fixture.controller.chooseFolder(fixture.context, chat));
    await tester.pumpAndSettle();
    expect(find.text('已在此分组'), findsOneWidget);
    expect(find.text('将从「朋友」移入'), findsOneWidget);
    final subtitle = tester.widget<Text>(find.text('已在此分组'));
    expect(subtitle.style!.fontSize, 12);
    expect(subtitle.style!.color,
        CupertinoColors.secondaryLabel.resolveFrom(tester.element(find.text('已在此分组'))));
    await _tap(tester, '朋友');
    await fixture.pending;
    expect(logic.updates, isEmpty);
    fixture.start(fixture.controller.chooseFolder(fixture.context, chat));
    await tester.pumpAndSettle();
    await _tap(tester, '工作');
    await fixture.pending;
    expect(logic.updates, [(id: 'chat', folderID: 'b', archived: false)]);
    expect(logic.folderID(chat), 'b');
    await _closeHost(tester, fixture);
  });

  testWidgets('choosing the current folder for an archived chat unarchives it', (tester) async {
    final logic = _FolderLogic()..folders.add(_folder('a', '朋友'));
    final chat = logic.seedChat(folderID: 'a', archived: true);
    final fixture = await _mount(tester, logic);
    fixture.start(fixture.controller.chooseFolder(fixture.context, chat));
    await tester.pumpAndSettle();
    await _tap(tester, '朋友');
    await fixture.pending;
    expect(logic.updates, [(id: 'chat', folderID: 'a', archived: false)]);
    await _closeHost(tester, fixture);
  });

  testWidgets('reorder preview stays local and concurrent finish saves once', (tester) async {
    final logic = _FolderLogic()
      ..folders.addAll([_folder('a', 'A'), _folder('b', 'B', sortOrder: 1), _folder('c', 'C', sortOrder: 2)]);
    final fixture = await _mount(tester, logic);
    await fixture.controller.selectFolder('a');
    await _startReorder(tester, fixture);
    fixture.controller.previewReorder(0, 3);
    expect(fixture.controller.displayFolders.map((folder) => folder.id), ['b', 'c', 'a']);
    expect(logic.folders.map((folder) => folder.id), ['a', 'b', 'c']);
    expect(logic.orders, isEmpty);
    final gate = Completer<void>();
    logic.reorderGate = gate;
    final first = fixture.controller.finishReordering();
    final second = fixture.controller.finishReordering();
    final selecting = fixture.controller.selectFolder('c');
    expect(fixture.controller.busy, isTrue);
    expect(logic.orders, [['b', 'c', 'a']]);
    fixture.controller.previewReorder(0, 3);
    expect(fixture.controller.displayFolders.map((folder) => folder.id), ['b', 'c', 'a']);
    gate.complete();
    await Future.wait([first, second, selecting]);
    await tester.pumpAndSettle();
    expect(logic.orders, hasLength(1));
    expect(logic.orders.single.toSet(), hasLength(3));
    expect(logic.folders.map((folder) => folder.id), ['b', 'c', 'a']);
    expect(fixture.controller.reorderEditing, isFalse);
    expect(fixture.controller.busy, isFalse);
    expect(fixture.controller.selectedFolderID, 'c');
    await _closeHost(tester, fixture);
  });

  testWidgets('finishing an unchanged folder order does not write', (tester) async {
    final logic = _FolderLogic()..folders.addAll([_folder('a', 'A'), _folder('b', 'B')]);
    final fixture = await _mount(tester, logic);
    await _startReorder(tester, fixture);
    fixture.controller.previewReorder(0, 2);
    fixture.controller.previewReorder(1, 0);
    await fixture.controller.finishReordering();
    expect(logic.orders, isEmpty);
    expect(fixture.controller.reorderEditing, isFalse);
    await _closeHost(tester, fixture);
  });

  testWidgets('failed order save displays the refreshed server order', (tester) async {
    final logic = _FolderLogic()
      ..folders.addAll([_folder('a', 'A'), _folder('b', 'B'), _folder('c', 'C')])
      ..failReorder = true
      ..orderAfterFailure = [_folder('c', 'C'), _folder('a', 'A', sortOrder: 1), _folder('b', 'B', sortOrder: 2)];
    final fixture = await _mount(tester, logic);
    await fixture.controller.selectFolder('a');
    await _startReorder(tester, fixture);
    fixture.controller.previewReorder(0, 3);
    await fixture.controller.finishReordering();
    expect(logic.orders, [['b', 'c', 'a']]);
    expect(fixture.controller.displayFolders.map((folder) => folder.id), ['c', 'a', 'b']);
    expect(fixture.controller.selectedFolderID, 'a');
    expect(fixture.controller.reorderEditing, isFalse);
    expect(fixture.controller.busy, isFalse);
    await _closeHost(tester, fixture);
  });

  for (final dispose in [false, true]) {
    testWidgets('pending creation does not move chats after ${dispose ? 'dispose' : 'session expiry'}', (tester) async {
      final logic = _FolderLogic();
      final chat = logic.seedChat(archived: true);
      final gate = Completer<void>();
      logic.createGate = gate;
      final fixture = await _mount(tester, logic);
      fixture.start(fixture.controller.chooseFolder(fixture.context, chat));
      await tester.pumpAndSettle();
      await _tap(tester, '新建分组');
      await _name(tester, '朋友');
      expect(logic.creates, ['朋友']);
      expect(fixture.controller.busy, isTrue);
      if (dispose) {
        await _closeHost(tester, fixture);
      } else {
        logic.sessionActive = false;
      }
      gate.complete();
      await fixture.pending;
      await tester.pumpAndSettle();
      expect(logic.updates, isEmpty);
      expect(logic.folderID(chat), isNull);
      expect(logic.isArchived(chat), isTrue);
      expect(fixture.controller.selectedFolderID, isNull);
      expect(tester.takeException(), isNull);
      await _closeHost(tester, fixture);
    });
  }

  testWidgets('organize removal and archive preserve the underlying chat', (tester) async {
    final logic = _FolderLogic()..folders.add(_folder('a', '朋友'));
    final chat = logic.seedChat(folderID: 'a');
    final fixture = await _mount(tester, logic);
    await fixture.controller.selectFolder('a');
    fixture.start(fixture.controller.organizeConversation(fixture.context, chat));
    await tester.pumpAndSettle();
    expect(find.text('移出分组'), findsOneWidget);
    await _tap(tester, '移出分组');
    await fixture.pending;
    expect(logic.updates.last, (id: 'chat', folderID: null, archived: false));
    fixture.start(fixture.controller.organizeConversation(fixture.context, chat));
    await tester.pumpAndSettle();
    expect(find.text('移出分组'), findsNothing);
    await _tap(tester, '归档');
    await fixture.pending;
    expect(logic.updates.last, (id: 'chat', folderID: null, archived: true));
    expect(logic.list.single, same(chat));
    await _closeHost(tester, fixture);
  });
}
