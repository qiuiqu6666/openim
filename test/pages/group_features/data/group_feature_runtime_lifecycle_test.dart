import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/pages/group_features/data/group_feature_runtime.dart';
import 'package:openim/pages/group_features/identity/group_name_label.dart';
import 'package:openim/pages/group_features/widgets/group_live_avatar.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _App extends GetxController implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late IMController im;
  Future<void> login(String user, String token) async {
    OpenIM.iMManager.userID = user;
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': user,
      'imToken': 'im-token',
      'chatToken': token,
    }));
  }

  Future<void> switchNode(int node) async {
    await DataSp.putServerConfig({
      'authUrl': 'https://node$node.example/chat',
      'apiUrl': 'https://node$node.example/im',
      'wsUrl': 'wss://node$node.example/ws',
    });
  }

  setUp(() async {
    Get.testMode = true;
    Get.put<AppController>(_App());
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await login('user', 'token');
    im = IMController();
  });
  tearDown(() async {
    GroupFeatureRuntime.reset();
    Get.reset();
  });

  test('node switches preserve the shared store and SDK subscriptions',
      () async {
    final listStore = GroupFeatureRuntime.forAccount(im);
    var notifications = 0;
    listStore.addListener(() => notifications++);
    for (var node = 0; node < 3; node++) {
      await switchNode(node);
      final chatStore = GroupFeatureRuntime.forAccount(im);
      expect(chatStore, same(listStore));
      expect(listStore.active, isTrue);
      expect(listStore.api.baseUrl, Config.appAuthUrl);
      im.groupInfoUpdatedSubject
          .add(GroupInfo(groupID: 'g', groupName: 'n$node'));
      await Future<void>.delayed(Duration.zero);
      expect(listStore.cachedGroupInfo('g')?.groupName, 'n$node');
    }
    expect(notifications, 3);
  });

  test('reset retires data and subscriptions but permits late row listeners',
      () async {
    final old = GroupFeatureRuntime.forAccount(im);
    old.seed(GroupInfo(groupID: 'g', groupName: 'private'));
    var notifications = 0;
    old.addListener(() => notifications++);
    final done = Completer<void>();
    final subscription = old.events('g').listen((_) {}, onDone: done.complete);
    GroupFeatureRuntime.reset();
    await done.future;
    expect(old.active, isFalse);
    expect(old.cachedGroupInfo('g'), isNull);
    expect(notifications, 1);
    void lateListener() {}
    expect(() => old.addListener(lateListener), returnsNormally);
    old.removeListener(lateListener);
    im.groupInfoUpdatedSubject.add(GroupInfo(groupID: 'g', groupName: 'late'));
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 1);
    expect(im.groupInfoUpdatedSubject.hasListener, isFalse);
    final next = GroupFeatureRuntime.forAccount(im);
    expect(next, isNot(same(old)));
    expect(next.active, isTrue);
    await subscription.cancel();
  });

  test('token and account changes retire old references without reviving them',
      () async {
    final first = GroupFeatureRuntime.forAccount(im);
    await login('user', 'new-token');
    final second = GroupFeatureRuntime.forAccount(im);
    expect(second, isNot(same(first)));
    expect(first.active, isFalse);
    await login('another-user', 'another-token');
    final third = GroupFeatureRuntime.forAccount(im);
    expect(third, isNot(same(second)));
    expect(second.active, isFalse);
    await login('user', 'token');
    expect(first.active, isFalse);
  });

  testWidgets('switch node, enter group, pop and recycle rows repeatedly',
      (tester) async {
    final listStore = GroupFeatureRuntime.forAccount(im);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: Scaffold(
          body: ListView.builder(
        itemCount: 150,
        itemExtent: 64,
        itemBuilder: (_, index) => ListTile(
          leading:
              GroupLiveAvatar(store: listStore, child: const Icon(Icons.group)),
          title: GroupNameLabel(
              name: 'group $index', groupID: 'g$index', store: listStore),
        ),
      )),
    ));
    for (var node = 0; node < 3; node++) {
      await switchNode(node);
      final chatStore = GroupFeatureRuntime.forAccount(im);
      unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
            body: GroupNameLabel(
          name: 'chat',
          groupID: 'g0',
          store: chatStore,
        )),
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      for (final distance in [-1200.0, -1200.0, 2400.0]) {
        await tester.drag(find.byType(ListView), Offset(0, distance));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(ErrorWidget), findsNothing);
      }
    }
    // Exit can invalidate before Navigator has removed its old lazy list.
    GroupFeatureRuntime.reset();
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -1600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
