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

  void success(Map<String, dynamic> data) => response.complete(
        ResponseBody.fromString(
          jsonEncode({'errCode': 0, 'data': data}),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );

  void businessFailure() => response.complete(
        ResponseBody.fromString(
          jsonEncode({
            'errCode': 20010,
            'errMsg': 'organizer rejected',
            'errDlt': 'please retry',
            'data': null,
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );

  void connectionFailure() => response.completeError(DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'organizer unavailable',
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

Map<String, dynamic> _state(String id,
        {bool archived = true, int version = 7}) =>
    {
      'conversationID': id,
      'folderID': 'work',
      'archived': archived,
      'version': version,
    };

Map<String, dynamic> _folder(String id) => {
      'id': id,
      'name': id,
      'sortOrder': 0,
      'createdAt': 1,
      'updatedAt': 2,
    };

Future<void> _signIn(
    {bool differentAccount = false, bool newToken = false}) async {
  final account = differentAccount ? 'other' : 'self';
  OpenIM.iMManager.userID = account;
  await DataSp.putLoginCertificate(LoginCertificate.fromJson({
    'userID': account,
    'chatToken': newToken ? 'new-chat-token' : 'self-chat-token',
    'imToken': '$account-im-token',
  }));
}

Future<void> _waitForRequests(_HTTP adapter, int count) async {
  for (var i = 0; i < 100 && adapter.requests.length < count; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(adapter.requests, hasLength(count));
}

Future<void> _mountToastHost(WidgetTester tester) => tester.pumpWidget(
      GetMaterialApp(
        builder: EasyLoading.init(),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );

Future<void> _disposeToastHost(WidgetTester tester) async {
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
    // Construct the real logic without Get.put/onInit, which starts SDK reads.
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

  testWidgets(
      'unarchive writes the current folder and version and restores the shared feed',
      (tester) async {
    await _mountToastHost(tester);
    final logic = createLogic();
    final row = ConversationInfo(
      conversationID: 'si_friend/one',
      conversationType: ConversationType.single,
      userID: 'friend',
    );
    final group = ConversationInfo(
      conversationID: 'sg_group',
      conversationType: ConversationType.superGroup,
      groupID: 'group',
    );
    logic.list.addAll([row, group]);
    logic.states[row.conversationID] =
        ChatConversationState.fromJson(_state(row.conversationID));
    logic.states[group.conversationID] =
        ChatConversationState.fromJson(_state(group.conversationID));

    await tester.runAsync(() async {
      final updating = logic.updateOrganizer(row,
          folderID: logic.folderID(row), archived: false);
      await _waitForRequests(adapter, 1);
      final request = adapter.requests.single;
      expect(request.options.method, 'PUT');
      expect(request.options.path,
          '${Config.appAuthUrl}/chat/conversation-states/si_friend%2Fone');
      expect(request.options.data,
          {'folderID': 'work', 'archived': false, 'version': 7});
      expect(request.options.headers['token'], 'self-chat-token');
      expect(request.options.headers['operationID'], isNotEmpty);
      // The page continues showing its old scope until the server accepts it.
      expect(logic.isArchived(row), isTrue);
      request.success(_state(row.conversationID, archived: false, version: 8));
      expect(await updating, isTrue);
    });

    expect(logic.states[row.conversationID]?.version, 8);
    expect(logic.folderID(row), 'work');
    expect(logic.list, [row, group]);
    expect(
        logic.list.where((info) => info.isSingleChat && logic.isArchived(info)),
        isEmpty);
    expect(
        logic.list
            .where((info) => info.isSingleChat && !logic.isArchived(info)),
        [row]);
    expect(logic.isArchived(group), isTrue);
    await _disposeToastHost(tester);
  });

  testWidgets(
      'business and connection failures retain archived state and report failure',
      (tester) async {
    await _mountToastHost(tester);
    final logic = createLogic();
    final row = ConversationInfo(conversationID: 'si_friend');
    final old = ChatConversationState.fromJson(_state(row.conversationID));
    logic.states[row.conversationID] = old;

    await tester.runAsync(() async {
      for (final connectionFailure in [false, true]) {
        final count = adapter.requests.length + 1;
        final updating = logic.updateOrganizer(row,
            folderID: logic.folderID(row), archived: false);
        await _waitForRequests(adapter, count);
        final request = adapter.requests.last;
        if (connectionFailure) {
          request.connectionFailure();
        } else {
          request.businessFailure();
        }
        expect(await updating, isFalse);
        expect(logic.states[row.conversationID], same(old));
        expect(logic.isArchived(row), isTrue);
        expect(logic.folderID(row), 'work');
      }
    });
    await _disposeToastHost(tester);
  });

  testWidgets(
      'organizer refresh exposes failure and clears it on a successful retry',
      (tester) async {
    await _mountToastHost(tester);
    final logic = createLogic();
    await tester.runAsync(() async {
      final first = logic.refreshOrganizer();
      await _waitForRequests(adapter, 1);
      expect(logic.organizerLoading.value, isTrue);
      expect(adapter.requests.single.options.path,
          '${Config.appAuthUrl}/chat/folders');
      adapter.requests.single.businessFailure();
      await first;
      expect(logic.organizerLoading.value, isFalse);
      expect(logic.organizerError.value, contains('organizer rejected'));
      expect(logic.folders, isEmpty);
      expect(logic.states, isEmpty);

      final retry = logic.refreshOrganizer();
      expect(logic.organizerError.value, isNull);
      await _waitForRequests(adapter, 2);
      adapter.requests.last.success({
        'folders': [_folder('work')]
      });
      await _waitForRequests(adapter, 3);
      final stateRequest = adapter.requests.last.options;
      expect(stateRequest.method, 'GET');
      expect(
          stateRequest.path, '${Config.appAuthUrl}/chat/conversation-states');
      expect(stateRequest.queryParameters, {'updatedAfter': 0, 'limit': 500});
      adapter.requests.last.success({
        'states': [_state('si_friend')],
        'syncAt': 123,
      });
      await retry;
      expect(logic.organizerLoading.value, isFalse);
      expect(logic.organizerError.value, isNull);
      expect(logic.folders.single.id, 'work');
      expect(logic.states['si_friend']?.archived, isTrue);
    });
    await _disposeToastHost(tester);
  });

  testWidgets(
      'late organizer responses cannot mutate a different account or token session',
      (tester) async {
    await _mountToastHost(tester);
    await tester.runAsync(() async {
      for (final changeAccount in [true, false]) {
        await _signIn();
        final logic = createLogic();
        final row = ConversationInfo(conversationID: 'si_friend');
        final old = ChatConversationState.fromJson(_state(row.conversationID));
        logic.states[row.conversationID] = old;
        final requestCount = adapter.requests.length;
        final updating = logic.updateOrganizer(row,
            folderID: logic.folderID(row), archived: false);
        await _waitForRequests(adapter, requestCount + 1);
        await _signIn(
            differentAccount: changeAccount, newToken: !changeAccount);
        adapter.requests.last
            .success(_state(row.conversationID, archived: false, version: 8));
        expect(await updating, isFalse);
        expect(logic.states[row.conversationID], same(old));
        expect(logic.isSessionActive, isFalse);
        await logic.refreshOrganizer();
        expect(
            await logic.updateOrganizer(row, folderID: 'work', archived: false),
            isFalse);
        expect(adapter.requests, hasLength(requestCount + 1));
        closeLogic(logic);

        await _signIn();
        final refreshingLogic = createLogic();
        refreshingLogic.states[row.conversationID] = old;
        final oldFolder = ChatFolder.fromJson(_folder('cached'));
        refreshingLogic.folders.add(oldFolder);
        final refreshCount = adapter.requests.length;
        final refreshing = refreshingLogic.refreshOrganizer();
        await _waitForRequests(adapter, refreshCount + 1);
        adapter.requests.last.success({
          'folders': [_folder('remote')]
        });
        await _waitForRequests(adapter, refreshCount + 2);
        await _signIn(
            differentAccount: changeAccount, newToken: !changeAccount);
        adapter.requests.last.success({
          'states': [_state(row.conversationID, archived: false, version: 99)],
          'syncAt': 999,
        });
        await refreshing;
        expect(refreshingLogic.states[row.conversationID], same(old));
        expect(refreshingLogic.folders.single, same(oldFolder));
        expect(refreshingLogic.organizerError.value, isNull);
        closeLogic(refreshingLogic);
      }

      await _signIn();
      final closedLogic = createLogic();
      closeLogic(closedLogic);
      final count = adapter.requests.length;
      await closedLogic.refreshOrganizer();
      expect(
          await closedLogic.updateOrganizer(
              ConversationInfo(conversationID: 'si_friend'),
              folderID: 'work',
              archived: false),
          isFalse);
      expect(adapter.requests, hasLength(count));
    });
    await _disposeToastHost(tester);
  });
}
