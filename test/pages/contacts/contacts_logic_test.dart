import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/contacts/contacts_logic.dart';
import 'package:openim/pages/contacts/directory/contact_directory_indexer.dart';
import 'package:openim/pages/home/home_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _App extends GetxController implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends GetxController with IMCallback implements IMController {
  @override
  void onClose() {
    close();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Home extends GetxController implements HomeLogic {
  @override
  final unhandledFriendApplicationCount = 0.obs;
  @override
  final unhandledGroupApplicationCount = 0.obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _IM im;

  setUp(() async {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    Get.put<AppController>(_App());
    im = Get.put<IMController>(_IM()) as _IM;
    Get.put<HomeLogic>(_Home());
  });

  tearDown(Get.reset);

  test('friend event bursts apply locally without reloading the SDK directory',
      () async {
    var fetches = 0;
    final snapshot = <FriendInfo>[];
    final logic = ContactsLogic(fetchFriendsPage: (_, __) async {
      fetches++;
      return snapshot;
    })
      ..onInit();
    addTearDown(() => logic.onDelete());
    final rendered = Completer<void>();
    final subscription = logic.friends.listen((friends) {
      if (friends.length == 50 && !rendered.isCompleted) rendered.complete();
    });
    addTearDown(subscription.cancel);

    for (var i = 0; i < 50; i++) {
      final friend = FriendInfo(userID: 'friend$i', nickname: 'Friend $i');
      snapshot.add(friend);
      im.friendAdded(friend);
    }
    await rendered.future.timeout(const Duration(seconds: 10));

    expect(fetches, 0);
    expect(logic.friends, hasLength(50));
    expect(logic.friends.every((friend) => friend.tagIndex == 'F'), isTrue);
    expect(
        logic.friends.where((friend) => friend.isShowSuspension), hasLength(1));
  });

  test('live additions, deletion and remarks win over a concurrent SDK page',
      () async {
    var fetches = 0;
    final query = Completer<List<FriendInfo>>();
    final logic = ContactsLogic(
      fetchFriendsPage: (_, __) {
        fetches++;
        return query.future;
      },
      directoryIndexer: ContactDirectoryIndexer(
          worker: (names) async => buildContactNameIndex(names)),
    )..onInit();
    addTearDown(() => logic.onDelete());
    final loading = logic.loadFriends();
    im.friendAdded(FriendInfo(userID: 'added', nickname: 'Zed'));
    im.friendInfoChanged(
        FriendInfo(userID: 'updated', nickname: 'Bob', remark: '阿强'));
    im.friendDeleted(FriendInfo(userID: 'deleted'));
    await Future<void>.delayed(Duration.zero);
    query.complete([
      FriendInfo(userID: 'updated', nickname: 'Bob'),
      FriendInfo(userID: 'deleted', nickname: 'Deleted'),
    ]);
    await loading;

    expect(fetches, 1);
    expect(logic.friends.map((friend) => friend.userID), ['updated', 'added']);
    expect(logic.friends.first.showName, '阿强');
    expect(logic.friends.first.tagIndex, 'A');
    expect(logic.friends.last.tagIndex, 'Z');
    expect(logic.friends.every((friend) => friend.isShowSuspension), isTrue);
  });

  testWidgets(
      'index work coalesces changes and never publishes an old snapshot',
      (tester) async {
    var fetches = 0;
    final workers = <Completer<List<ContactNameIndex>>>[];
    final requests = <List<ContactNameIndex>>[];
    final logic = ContactsLogic(
      fetchFriendsPage: (_, __) async {
        fetches++;
        return [];
      },
      directoryIndexer: ContactDirectoryIndexer(worker: (names) {
        requests.add(names);
        final worker = Completer<List<ContactNameIndex>>();
        workers.add(worker);
        return worker.future;
      }),
    )..onInit();
    addTearDown(() => logic.onDelete());
    im.friendAdded(FriendInfo(userID: 'first', nickname: 'First'));
    im.friendAdded(FriendInfo(userID: 'deleted', nickname: 'Deleted'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(workers, hasLength(1));
    im.friendAdded(FriendInfo(userID: 'second', nickname: 'Second'));
    im.friendInfoChanged(
        FriendInfo(userID: 'first', nickname: 'First', remark: '阿强'));
    im.friendDeleted(FriendInfo(userID: 'deleted'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(workers, hasLength(1));
    workers.first.complete(buildContactNameIndex(requests.first));
    await tester.pump();
    expect(logic.friends, isEmpty);
    expect(workers, hasLength(2));
    workers.last.complete(buildContactNameIndex(requests.last));
    await tester.pump();

    expect(logic.friends.map((friend) => friend.userID), ['first', 'second']);
    expect(logic.friends.first.showName, '阿强');
    expect(fetches, 0);
    logic.onDelete();
  });

  for (final invalidation in ['close', 'account', 'token']) {
    test('index finishing after $invalidation does not update visible friends',
        () async {
      final worker = Completer<List<ContactNameIndex>>();
      List<ContactNameIndex>? names;
      var fetches = 0;
      final logic = ContactsLogic(
        fetchFriendsPage: (_, __) async {
          fetches++;
          return [FriendInfo(userID: 'late', nickname: 'Late')];
        },
        directoryIndexer: ContactDirectoryIndexer(worker: (request) {
          names = request;
          return worker.future;
        }),
      );
      addTearDown(() => logic.onDelete());
      logic.friends.add(ISUserInfo.fromJson(
          {'userID': 'kept', 'nickname': 'Kept', 'tagIndex': 'K'}));
      final loading = logic.loadFriends();
      await Future<void>.delayed(Duration.zero);
      expect(names, isNotNull);
      if (invalidation == 'close') {
        logic.onDelete();
      } else if (invalidation == 'account') {
        OpenIM.iMManager.userID = 'other';
      } else {
        await DataSp.putLoginCertificate(LoginCertificate.fromJson({
          'userID': 'self',
          'chatToken': 'new-token',
          'imToken': 'new-im-token',
        }));
      }
      worker.complete(buildContactNameIndex(names!));
      await loading;

      expect(logic.friends.map((friend) => friend.userID), ['kept']);
      await logic.loadFriends();
      expect(fetches, 1);
    });
  }

  test('a worker failure retains friends and the next refresh can recover',
      () async {
    var calls = 0;
    final logic = ContactsLogic(
      fetchFriendsPage: (_, __) async =>
          [FriendInfo(userID: 'fresh', nickname: 'Fresh')],
      directoryIndexer: ContactDirectoryIndexer(worker: (names) async {
        if (calls++ == 0) throw StateError('worker failed');
        return buildContactNameIndex(names);
      }),
    );
    addTearDown(() => logic.onDelete());
    logic.friends.add(ISUserInfo.fromJson(
        {'userID': 'kept', 'nickname': 'Kept', 'tagIndex': 'K'}));
    await logic.loadFriends();
    expect(logic.friends.single.userID, 'kept');
    expect(calls, 1);
    await logic.loadFriends();
    expect(logic.friends.single.userID, 'fresh');
    expect(calls, 2);
  });
}
