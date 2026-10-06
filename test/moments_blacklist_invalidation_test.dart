import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/services/moments_repository.dart';

class _FakeApp extends GetxController implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeIM extends GetxController with IMCallback implements IMController {
  @override
  void onClose() {
    close();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _friend = MomentUser(userId: 'friend', nickname: 'Friend');

class _Api extends MomentsApi {
  _Api()
      : super(
            baseUrl: 'https://business.example/chat',
            tokenProvider: () => 'business-token');

  @override
  Future<MomentsCapabilities> capabilities() async => const MomentsCapabilities(
      enabled: true, readEnabled: true, interactionsEnabled: true);

  @override
  Future<MomentsPageResult<MomentPost>> feed(
          {String? cursor, int pageSize = 20}) async =>
      const MomentsPageResult(items: [
        MomentPost(
            momentId: 'post',
            author: MomentUser(userId: 'me'),
            text: 'authorized own post',
            likesPreview: [MomentLike(user: _friend)],
            likeCount: 1,
            version: 1)
      ]);

  @override
  Future<MomentsPageResult<MomentNotification>> notifications(
          {String? cursor, int pageSize = 20}) async =>
      const MomentsPageResult(items: []);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeIM im;

  setUp(() {
    Get.testMode = true;
    Get.put<AppController>(_FakeApp());
    im = Get.put<IMController>(_FakeIM()) as _FakeIM;
  });
  tearDown(() => Get.reset());

  test('blacklist broadcast coexists with existing add/delete callbacks',
      () async {
    final events = <BlacklistInfo>[];
    final legacyAdded = <BlacklistInfo>[];
    final legacyDeleted = <BlacklistInfo>[];
    im.onBlacklistAdd = legacyAdded.add;
    im.onBlacklistDeleted = legacyDeleted.add;
    final listener = im.blacklistChangedSubject.listen(events.add);
    final entry = BlacklistInfo(blockUserID: 'friend', userID: 'me');
    im.blacklistAdded(entry);
    im.blacklistDeleted(entry);
    await Future<void>.delayed(Duration.zero);
    expect(events, [entry, entry]);
    expect(legacyAdded, [entry]);
    expect(legacyDeleted, [entry]);
    await listener.cancel();
    im.onDelete();
    expect(im.blacklistChangedSubject.isClosed, true);
  });

  testWidgets('blacklist change revokes projection before background reload',
      (tester) async {
    var blocked = false;
    final repo = MomentsRepository(
        api: _Api(),
        userIdProvider: () => 'me',
        environmentProvider: () => 'https://business.example/chat',
        friendLoader: () async => blocked ? [] : [_friend]);
    addTearDown(repo.dispose);
    await repo.loadFeed();
    final scope = repo.authorizationScope;
    expect(repo.postById('post')!.likesPreview, hasLength(1));
    blocked = true;
    im.blacklistAdded(BlacklistInfo(blockUserID: 'friend', userID: 'me'));
    await tester.pump();
    expect(repo.authorizationScope, isNot(scope));
    expect(repo.postsById, isEmpty);
    expect(repo.feedState.items, isEmpty);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(repo.friends, isEmpty);
    expect(repo.postById('post')!.likesPreview, isEmpty);
    expect(repo.postById('post')!.interactionCountsTrusted, false);
    blocked = false;
    im.blacklistDeleted(BlacklistInfo(blockUserID: 'friend', userID: 'me'));
    await tester.pump();
    expect(repo.postsById, isEmpty);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(repo.postById('post')!.likesPreview, hasLength(1));
  });
}
