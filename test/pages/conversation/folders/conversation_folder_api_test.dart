import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/conversation/conversation_organizer.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class _App extends GetxController implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends GetxController with IMCallback implements IMController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  void onClose() {
    close();
    super.onClose();
  }
}

class _Home extends GetxController implements HomeLogic {
  @override
  final conversationsAtFirstPage = <ConversationInfo>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request {
  _Request(this.options);
  final RequestOptions options;
  final response = Completer<ResponseBody>();

  void reply(Map<String, dynamic> data, {bool failure = false}) =>
      response.complete(ResponseBody.fromString(
        jsonEncode({
          'errCode': failure ? 1001 : 0,
          'errMsg': failure ? 'folder update failed' : '',
          'errDlt': '',
          'data': data,
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ));
}

class _HTTP implements HttpClientAdapter {
  final requests = <_Request>[];

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? body, Future<void>? cancel) {
    final request = _Request(options);
    requests.add(request);
    return request.response.future;
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _folder(String id,
        {int order = 0, int updated = 1, String? name}) =>
    {
      'id': id,
      'name': name ?? id,
      // ChatFolder uses protobuf JSON omitempty for its zero sort order.
      if (order != 0) 'sortOrder': order,
      'createdAt': id == 'a' ? 1 : 2,
      'updatedAt': updated,
    };

Future<void> _signIn(
    {bool accountChanged = false, bool tokenChanged = false}) async {
  final account = accountChanged ? 'other' : 'self';
  OpenIM.iMManager.userID = account;
  await DataSp.putLoginCertificate(LoginCertificate.fromJson({
    'userID': account,
    'chatToken': tokenChanged ? 'new-chat' : 'self-chat',
    'imToken': '$account-im',
  }));
}

Future<void> _waitForRequests(_HTTP adapter, int count) async {
  for (var i = 0; i < 100 && adapter.requests.length < count; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(adapter.requests, hasLength(count));
}

Future<void> _mount(WidgetTester tester) => tester.pumpWidget(GetMaterialApp(
      builder: EasyLoading.init(),
      home: const Scaffold(body: SizedBox.shrink()),
    ));

Future<void> _disposeHost(WidgetTester tester) async {
  await EasyLoading.dismiss(animation: false);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _HTTP adapter;
  final controllers = <ConversationLogic>[];
  final closed = <ConversationLogic>{};

  ConversationLogic createLogic() {
    // Use the real controller without triggering its SDK-reading onInit.
    final logic = ConversationLogic();
    controllers.add(logic);
    return logic;
  }

  void closeLogic(ConversationLogic logic) {
    if (closed.add(logic)) logic.onClose();
  }

  setUp(() async {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await _signIn();
    Get.put<AppController>(_App());
    Get.put<IMController>(_IM());
    Get.put<HomeLogic>(_Home());
    http.dio = Dio();
    HttpUtil.init();
    adapter = _HTTP();
    http.dio.httpClientAdapter = adapter;
    controllers.clear();
    closed.clear();
  });

  tearDown(() {
    for (final logic in controllers) {
      closeLogic(logic);
    }
    http.dio.close(force: true);
    Get.reset();
  });

  test('folder parser defaults only absent or null sort order to zero', () {
    final omitted = _folder('default');
    expect(omitted.containsKey('sortOrder'), isFalse);
    expect(ChatFolder.fromJson(omitted).sortOrder, 0);
    expect(ChatFolder.fromJson({...omitted, 'sortOrder': null}).sortOrder, 0);
    expect(ChatFolder.fromJson({...omitted, 'sortOrder': 0}).sortOrder, 0);
    expect(ChatFolder.fromJson(_folder('ordered', order: 9)).sortOrder, 9);
    expect(() => ChatFolder.fromJson({...omitted, 'sortOrder': '0'}),
        throwsA(isA<TypeError>()));
  });

  testWidgets('refreshOrganizer loads zero sort order without an error toast',
      (tester) async {
    await _mount(tester);
    final logic = createLogic();
    await tester.runAsync(() async {
      final refreshing = logic.refreshOrganizer();
      await _waitForRequests(adapter, 1);
      adapter.requests.last.reply({
        'folders': [_folder('later', order: 3), _folder('default')],
      });
      await _waitForRequests(adapter, 2);
      adapter.requests.last.reply({'states': [], 'syncAt': 1});
      await refreshing;
      expect(logic.folders.map((folder) => folder.id), ['default', 'later']);
      expect(logic.folders.map((folder) => folder.sortOrder), [0, 3]);
      expect(logic.organizerError.value, isNull);
      expect(logic.organizerLoading.value, isFalse);
    });
    await tester.pump();
    expect(EasyLoading.isShow, isFalse);
    await _disposeHost(tester);
  });

  testWidgets('refreshOrganizer accepts omitted and null empty folder lists',
      (tester) async {
    await _mount(tester);
    await tester.runAsync(() async {
      for (final response in <Map<String, dynamic>>[
        {},
        {'folders': null},
        {'folders': []},
      ]) {
        final logic = createLogic();
        final count = adapter.requests.length;
        final refreshing = logic.refreshOrganizer();
        await _waitForRequests(adapter, count + 1);
        adapter.requests.last.reply(response);
        await _waitForRequests(adapter, count + 2);
        adapter.requests.last.reply({'states': [], 'syncAt': 0});
        await refreshing;
        expect(logic.folders, isEmpty);
        expect(logic.organizerError.value, isNull);
        expect(logic.organizerLoading.value, isFalse);
        closeLogic(logic);
      }
    });
    await tester.pump();
    expect(EasyLoading.isShow, isFalse);
    await _disposeHost(tester);
  });

  testWidgets('folder API rejects a non-list folders value', (tester) async {
    await _mount(tester);
    await tester.runAsync(() async {
      final pending = ChatOrganizerApi.getFolders();
      final rejected = expectLater(pending, throwsA(isA<TypeError>()));
      await _waitForRequests(adapter, 1);
      adapter.requests.last.reply({'folders': 'invalid'});
      await rejected;
    });
    await _disposeHost(tester);
  });

  testWidgets(
      'folder API creates ordered folders and PATCHes only the changed field',
      (tester) async {
    await _mount(tester);
    await tester.runAsync(() async {
      final defaultCreate = ChatOrganizerApi.createFolder('Default');
      await _waitForRequests(adapter, 1);
      expect(adapter.requests.last.options.method, 'POST');
      expect(adapter.requests.last.options.path,
          '${Config.appAuthUrl}/chat/folders');
      expect(adapter.requests.last.options.data,
          {'name': 'Default', 'sortOrder': 0});
      adapter.requests.last.reply(_folder('default'));
      expect((await defaultCreate).sortOrder, 0);

      final create = ChatOrganizerApi.createFolder('Work', sortOrder: 9);
      await _waitForRequests(adapter, 2);
      expect(
          adapter.requests.last.options.data, {'name': 'Work', 'sortOrder': 9});
      adapter.requests.last.reply(_folder('folder/a', order: 9, name: 'Work'));
      expect((await create).sortOrder, 9);

      final reorder = ChatOrganizerApi.setFolderSortOrder('folder/a', 2);
      await _waitForRequests(adapter, 3);
      final sortRequest = adapter.requests.last.options;
      expect(sortRequest.method, 'PATCH');
      expect(sortRequest.path, '${Config.appAuthUrl}/chat/folders/folder%2Fa');
      expect(sortRequest.data, {'sortOrder': 2});
      expect(sortRequest.headers['token'], 'self-chat');
      expect(sortRequest.headers['operationID'], isNotEmpty);
      adapter.requests.last.reply(_folder('folder/a', order: 2, updated: 20));
      final ordered = await reorder;
      expect(ordered.sortOrder, 2);
      expect(ordered.updatedAt, 20);

      final rename = ChatOrganizerApi.renameFolder('folder/a', 'Renamed');
      await _waitForRequests(adapter, 4);
      expect(adapter.requests.last.options.data, {'name': 'Renamed'});
      adapter.requests.last
          .reply(_folder('folder/a', order: 2, name: 'Renamed'));
      expect((await rename).name, 'Renamed');
      expect(
          adapter.requests
              .map((request) => request.options.headers['operationID'])
              .toSet(),
          hasLength(4));
    });
    await _disposeHost(tester);
  });

  testWidgets(
      'state pagination keeps operation IDs unique and stops after token changes',
      (tester) async {
    await _mount(tester);
    final firstPage = [
      for (var i = 0; i < 500; i++)
        {
          'conversationID': 'si_$i',
          'folderID': null,
          'archived': false,
          'version': 1,
        },
    ];
    await tester.runAsync(() async {
      final loading = ChatOrganizerApi.getStates();
      await _waitForRequests(adapter, 1);
      expect(adapter.requests.last.options.queryParameters['updatedAfter'], 0);
      adapter.requests.last.reply({'states': firstPage, 'syncAt': 500});
      await _waitForRequests(adapter, 2);
      expect(adapter.requests.last.options.queryParameters['updatedAfter'], 500);
      adapter.requests.last.reply({'states': [], 'syncAt': 501});
      expect((await loading).states, hasLength(500));
      expect(
          adapter.requests
              .map((request) => request.options.headers['operationID'])
              .toSet(),
          hasLength(2));

      for (final changeAccount in [true, false]) {
        await _signIn();
        final count = adapter.requests.length;
        final pending = ChatOrganizerApi.getStates();
        final stopped = expectLater(pending, throwsStateError);
        await _waitForRequests(adapter, count + 1);
        expect(adapter.requests.last.options.headers['token'], 'self-chat');
        await _signIn(accountChanged: changeAccount, tokenChanged: true);
        adapter.requests.last.reply({'states': firstPage, 'syncAt': 500});
        await stopped;
        expect(adapter.requests, hasLength(count + 1));
      }
    });
    await _disposeHost(tester);
  });

  testWidgets(
      'business pushes cannot change an old controller after account or token switches',
      (tester) async {
    await _mount(tester);
    Get.find<HomeLogic>().conversationsAtFirstPage.add(ConversationInfo(
          conversationID: 'si_friend',
          userID: 'friend',
          latestMsgSendTime: 1,
          draftTextTime: 0,
        ));
    await tester.runAsync(() async {
      for (final changeAccount in [true, false]) {
        await _signIn();
        final logic = createLogic();
        final count = adapter.requests.length;
        logic.onInit();
        await _waitForRequests(adapter, count + 1);
        adapter.requests.last.reply({'folders': [_folder('a')]});
        await _waitForRequests(adapter, count + 2);
        adapter.requests.last.reply({'states': [], 'syncAt': 1});
        for (var i = 0; i < 100 && logic.organizerLoading.value; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        expect(logic.organizerLoading.value, isFalse);
        final messages = Get.find<IMController>().customBusinessMessageSubject;
        void folderPush(Map<String, dynamic> data) => messages.add(jsonEncode({
              'key': 'chatFolderChanged',
              'data': data,
            }));
        void statePush(int version) => messages.add(jsonEncode({
              'key': 'conversationStateChanged',
              'data': {
                'conversationID': 'si_friend',
                'folderID': 'a',
                'archived': false,
                'version': version,
              },
            }));
        folderPush({
          'op': 'upsert',
          'folder': _folder('a', updated: 2, name: 'Active name'),
        });
        statePush(2);
        await Future<void>.delayed(Duration.zero);
        final activeFolder = logic.folders.single;
        final activeState = logic.states['si_friend'];
        expect(activeFolder.name, 'Active name');
        expect(activeState?.version, 2);

        await _signIn(
            accountChanged: changeAccount, tokenChanged: !changeAccount);
        folderPush({
          'op': 'upsert',
          'folder': _folder('a', updated: 99, name: 'Late name'),
        });
        folderPush({'op': 'upsert', 'folder': _folder('new', updated: 99)});
        folderPush({'op': 'delete', 'id': 'a'});
        statePush(99);
        await Future<void>.delayed(Duration.zero);
        expect(logic.isSessionActive, isFalse);
        expect(logic.folders.single, same(activeFolder));
        expect(logic.states['si_friend'], same(activeState));
        expect(adapter.requests, hasLength(count + 2));
        closeLogic(logic);
      }
    });
    await _disposeHost(tester);
  });

  testWidgets(
      'create appends after the maximum order and applies only real server folder data',
      (tester) async {
    await _mount(tester);
    final logic = createLogic();
    logic.folders.addAll([
      ChatFolder.fromJson(_folder('a', order: 3)),
      ChatFolder.fromJson(_folder('b', order: 9)),
    ]);
    await tester.runAsync(() async {
      final creating = logic.createFolder('New');
      await _waitForRequests(adapter, 1);
      expect(
          adapter.requests.last.options.data, {'name': 'New', 'sortOrder': 10});
      // Preserve the returned timestamp/order rather than fabricating a copy.
      adapter.requests.last
          .reply(_folder('new', order: 12, updated: 4, name: 'New'));
      expect(await creating, isTrue);
      expect(logic.folders.map((folder) => folder.id), ['a', 'b', 'new']);
      expect(logic.folders.last.sortOrder, 12);
      expect(logic.folders.last.updatedAt, 4);

      final previous = logic.folders.first;
      final renaming = logic.renameFolder(previous, 'Changed');
      await _waitForRequests(adapter, 2);
      // A successful response can have the same coarse server timestamp.
      adapter.requests.last.reply(_folder('a', order: 3, name: 'Changed'));
      expect(await renaming, isTrue);
      expect(logic.folders.first.name, 'Changed');
      expect(logic.folders.first.updatedAt, previous.updatedAt);
    });
    await _disposeHost(tester);
  });

  testWidgets(
      'reorder skips deleted IDs and cannot overwrite a newer multi-device update',
      (tester) async {
    await _mount(tester);
    await tester.runAsync(() async {
      for (final deletedWhilePending in [false, true]) {
        final logic = createLogic();
        logic.folders.addAll([
          ChatFolder.fromJson(_folder('a')),
          ChatFolder.fromJson(_folder('b', order: 1)),
          ChatFolder.fromJson(_folder('c', order: 2)),
        ]);
        final count = adapter.requests.length;
        final committing =
            logic.reorderFolders(['b', 'unknown', 'a', 'b', 'c']);
        await _waitForRequests(adapter, count + 1);
        expect(adapter.requests.last.options.path,
            '${Config.appAuthUrl}/chat/folders/b');
        expect(adapter.requests.last.options.data, {'sortOrder': 0});
        // Changes from the live SDK/refresh owner arrive during the PATCH.
        logic.folders.removeWhere((folder) => folder.id == 'c');
        if (deletedWhilePending) {
          logic.folders.removeWhere((folder) => folder.id == 'b');
        } else {
          logic.folders[1] = ChatFolder.fromJson(_folder('b',
              order: 2, updated: 100, name: 'From another device'));
        }
        final newlyAdded = ChatFolder.fromJson(_folder('new', order: 5));
        logic.folders.add(newlyAdded);
        adapter.requests.last.reply(_folder('b', order: 0, updated: 2));
        await _waitForRequests(adapter, count + 2);
        expect(adapter.requests.last.options.path,
            '${Config.appAuthUrl}/chat/folders/a');
        final nextOrder = deletedWhilePending ? 0 : 1;
        expect(adapter.requests.last.options.data, {'sortOrder': nextOrder});
        adapter.requests.last.reply(_folder('a', order: nextOrder, updated: 3));
        expect(await committing, isTrue);
        expect(adapter.requests, hasLength(count + 2));
        expect(logic.folders.any((folder) => folder.id == 'c'), isFalse);
        expect(logic.folders.last, same(newlyAdded));
        if (deletedWhilePending) {
          expect(logic.folders.any((folder) => folder.id == 'b'), isFalse);
        } else {
          final live = logic.folders.firstWhere((folder) => folder.id == 'b');
          expect(live.name, 'From another device');
          expect(live.updatedAt, 100);
          expect(live.sortOrder, 2);
        }

        final refreshCount = adapter.requests.length;
        final refreshing = logic.refreshOrganizer();
        await _waitForRequests(adapter, refreshCount + 1);
        adapter.requests.last.reply({
          'folders': [
            _folder('a', order: nextOrder, updated: 3),
            if (!deletedWhilePending) _folder('b', order: 0, updated: 2),
            _folder('new', order: 5),
          ],
        });
        await _waitForRequests(adapter, refreshCount + 2);
        final liveA = ChatFolder.fromJson(
            _folder('a', order: 4, updated: 200, name: 'Latest folder name'));
        logic.folders[logic.folders.indexWhere((folder) => folder.id == 'a')] =
            liveA;
        logic.folders.removeWhere((folder) => folder.id == 'new');
        adapter.requests.last.reply({'states': [], 'syncAt': 10});
        await refreshing;
        expect(logic.folders.firstWhere((folder) => folder.id == 'a'),
            same(liveA));
        expect(logic.folders.any((folder) => folder.id == 'new'), isFalse);
        closeLogic(logic);
      }
    });
    await _disposeHost(tester);
  });

  testWidgets(
      'a partial reorder failure reloads server state without inventing conversation versions',
      (tester) async {
    await _mount(tester);
    final logic = createLogic();
    logic.folders.addAll([
      ChatFolder.fromJson(_folder('a')),
      ChatFolder.fromJson(_folder('b', order: 1)),
    ]);
    logic.states['si_friend'] = ChatConversationState.fromJson({
      'conversationID': 'si_friend',
      'folderID': 'b',
      'archived': true,
      'version': 7,
    });
    await tester.runAsync(() async {
      final committing = logic.reorderFolders(['b', 'a']);
      await _waitForRequests(adapter, 1);
      adapter.requests.last.reply(_folder('b', order: 0, updated: 2));
      await _waitForRequests(adapter, 2);
      adapter.requests.last.reply({}, failure: true);
      await _waitForRequests(adapter, 3);
      expect(adapter.requests.last.options.method, 'GET');
      expect(adapter.requests.last.options.path,
          '${Config.appAuthUrl}/chat/folders');
      adapter.requests.last.reply({
        'folders': [
          _folder('a', order: 4, updated: 10),
          _folder('b', order: 2, updated: 10)
        ],
      });
      await _waitForRequests(adapter, 4);
      expect(adapter.requests.last.options.path,
          '${Config.appAuthUrl}/chat/conversation-states');
      adapter.requests.last.reply({'states': [], 'syncAt': 8});
      expect(await committing, isFalse);
      expect(logic.folders.map((folder) => folder.id), ['b', 'a']);
      expect(logic.folders.map((folder) => folder.sortOrder), [2, 4]);
      expect(logic.states['si_friend']?.version, 7);
      expect(logic.states['si_friend']?.archived, isTrue);
      expect(logic.states['si_friend']?.folderID, 'b');

      final deleting = logic.deleteFolder(logic.folders.first);
      await _waitForRequests(adapter, 5);
      expect(adapter.requests.last.options.method, 'DELETE');
      adapter.requests.last.reply({});
      await _waitForRequests(adapter, 6);
      expect(logic.states['si_friend']?.version, 7);
      adapter.requests.last.reply({
        'folders': [_folder('a', order: 4, updated: 10)]
      });
      await _waitForRequests(adapter, 7);
      adapter.requests.last.reply({
        'states': [
          {
            'conversationID': 'si_friend',
            'folderID': null,
            'archived': true,
            'version': 8,
          }
        ],
        'syncAt': 9,
      });
      expect(await deleting, isTrue);
      expect(logic.folders.single.id, 'a');
      expect(logic.states['si_friend']?.version, 8);
      expect(logic.states['si_friend']?.folderID, isNull);
      expect(logic.states['si_friend']?.archived, isTrue);
    });
    await _disposeHost(tester);
  });

  testWidgets(
      'folder mutations ignore late responses after account or token changes',
      (tester) async {
    await _mount(tester);
    await tester.runAsync(() async {
      for (final changeAccount in [true, false]) {
        for (final action in ['create', 'rename', 'delete', 'reorder']) {
          await _signIn();
          final logic = createLogic();
          final original = ChatFolder.fromJson(_folder('a'));
          logic.folders.add(original);
          final count = adapter.requests.length;
          final pending = switch (action) {
            'create' => logic.createFolder('New'),
            'rename' => logic.renameFolder(original, 'Changed'),
            'delete' => logic.deleteFolder(original),
            _ => logic.reorderFolders(['a']),
          };
          await _waitForRequests(adapter, count + 1);
          await _signIn(
              accountChanged: changeAccount, tokenChanged: !changeAccount);
          adapter.requests.last.reply(action == 'delete'
              ? {}
              : _folder(action == 'create' ? 'new' : 'a', updated: 99));
          expect(await pending, isFalse);
          expect(logic.folders.single, same(original));
          expect(logic.isSessionActive, isFalse);
          expect(await logic.createFolder('Inactive'), isFalse);
          expect(await logic.renameFolder(original, 'Inactive'), isFalse);
          expect(await logic.deleteFolder(original), isFalse);
          expect(await logic.reorderFolders(['a']), isFalse);
          expect(adapter.requests, hasLength(count + 1));
          closeLogic(logic);
        }
      }
    });
    await _disposeHost(tester);
  });
}
