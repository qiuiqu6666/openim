import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/services/moments_repository.dart';

const _me = MomentUser(userId: 'me', nickname: 'Me');
const _friend = MomentUser(userId: 'friend', nickname: 'Friend');
const _caps = MomentsCapabilities(
    enabled: true,
    readEnabled: true,
    interactionsEnabled: true,
    settingsEnabled: true);

MomentComment _comment(String id) =>
    MomentComment(commentId: id, author: _me, text: id, createdAt: 1);
MomentPost _post(String id, {int version = 1, bool liked = false}) =>
    MomentPost(
        momentId: id,
        author: _friend,
        text: 'authorised content',
        version: version,
        likedByMe: liked,
        likesPreview: liked ? const [MomentLike(user: _me)] : const [],
        likeCount: liked ? 1 : 0,
        commentsPreview: [_comment('own-comment')],
        commentCount: 1);
MomentNotification _notification(String id, {int seq = 1}) =>
    MomentNotification(
        notificationId: id, actor: _friend, momentId: 'post', seq: seq);

class _Api extends MomentsApi {
  _Api() : super(baseUrl: 'https://business.example');
  MomentsCapabilities caps = _caps;
  final feedCursors = <String?>[];
  final commentCursors = <String?>[];
  final notificationCursors = <String?>[];
  final likesCursors = <String?>[];
  final likeWrites = <bool>[];
  final deletedComments = <String>[];
  int detailCalls = 0;
  int userCalls = 0;
  int version = 1;
  Future<MomentsPageResult<MomentPost>> Function(String?)? feedWork;
  Future<MomentsPageResult<MomentComment>> Function(String?)? commentsWork;
  Future<MomentsPageResult<MomentNotification>> Function(String?)?
      notificationsWork;
  Future<MomentsPageResult<MomentLike>> Function(String?)? likesWork;
  Object? detailError;
  @override
  Future<MomentsCapabilities> capabilities() async => caps;
  @override
  Future<MomentsPageResult<MomentPost>> feed(
      {String? cursor, int pageSize = 20}) async {
    feedCursors.add(cursor);
    return feedWork?.call(cursor) ??
        MomentsPageResult(items: [_post('post', version: version)]);
  }

  @override
  Future<MomentsPageResult<MomentPost>> userMoments(String userId,
      {String? cursor, int pageSize = 20}) async {
    userCalls++;
    return MomentsPageResult(
        items: [_post('post', version: version)],
        author: _friend,
        coverUrl: '/private-cover');
  }

  @override
  Future<MomentPost> detail(String momentId) async {
    detailCalls++;
    if (detailError != null) throw detailError!;
    return _post(momentId, version: version);
  }

  @override
  Future<MomentsPageResult<MomentComment>> comments(String momentId,
      {String? cursor, int pageSize = 20}) async {
    commentCursors.add(cursor);
    return commentsWork?.call(cursor) ??
        MomentsPageResult(items: [_comment('own-comment')]);
  }

  @override
  Future<MomentsPageResult<MomentNotification>> notifications(
      {String? cursor, int pageSize = 20}) async {
    notificationCursors.add(cursor);
    return notificationsWork?.call(cursor) ??
        MomentsPageResult(
            items: [_notification('n')],
            unreadCount: 1,
            readThroughSeq: 1,
            seenWatermark: 'seen-1');
  }

  @override
  Future<MomentsPageResult<MomentLike>> likes(String momentId,
      {String? cursor, int pageSize = 20}) async {
    likesCursors.add(cursor);
    return likesWork?.call(cursor) ?? const MomentsPageResult(items: []);
  }

  @override
  Future<void> setLiked(String momentId, bool liked) async {
    likeWrites.add(liked);
  }

  @override
  Future<void> deleteComment(String momentId, String commentId) async {
    deletedComments.add(commentId);
  }
}

MomentsRepository _repository(_Api api, {bool sdk = false}) =>
    MomentsRepository(
        api: api,
        userIdProvider: () => 'me',
        friendLoader: () async => [_friend],
        subscribeToSdk: sdk);

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Api api;
  late MomentsRepository repository;
  setUp(() {
    api = _Api();
    repository = _repository(api);
  });
  tearDown(() => repository.dispose());

  test('capability truth is accepted without an invented protocol version gate',
      () async {
    api.caps = const MomentsCapabilities(
        enabled: true, readEnabled: true, protocolVersion: 9);
    await repository.loadFeed();
    expect(repository.available, isTrue);
    expect(repository.feedState.items, hasLength(1));
  });

  test('the first user album load belongs to the established account state',
      () async {
    await repository.loadUser('friend');
    expect(repository.userState('friend').items.single.momentId, 'post');
    expect(repository.userState('friend').author!.userId, 'friend');
  });

  test(
      'unavailable notification placeholders do not suppress valid unread count',
      () async {
    api.notificationsWork = (_) async => MomentsPageResult.fromJson({
          'items': [
            {
              'notificationID': 'unavailable',
              'momentID': 'hidden',
              'actor': null,
              'unavailable': true
            },
            {
              'notificationID': 'available',
              'momentID': 'post',
              'actor': {'userID': 'friend', 'nickname': 'Friend'},
              'type': 'like',
              'unread': true
            }
          ],
          'unreadCount': 1,
          'lastSeq': 2,
          'seenWatermark': 'seen-2'
        }, MomentNotification.fromJson);
    await repository.loadNotifications();
    expect(repository.notifications.single.notificationId, 'available');
    expect(repository.notificationsCountsTrusted, isTrue);
    expect(repository.unreadCount, 1);
    expect(repository.readThroughSeq, 2);
  });

  test(
      'a success page from another viewer context is never appended to old rows',
      () async {
    api.feedWork = (cursor) async => MomentsPageResult(
        items: [_post(cursor == null ? 'fresh' : 'wrong-context')],
        hasMore: true,
        nextCursor: 'older',
        viewerContextVersion: api.feedCursors.length == 1 ? 'one' : 'two');
    await repository.loadFeed();
    await repository.loadFeed(refresh: false);
    expect(api.feedCursors, [null, 'older', null]);
    expect(repository.feedState.items.single.momentId, 'fresh');
    expect(repository.postById('wrong-context'), isNull);
    expect(repository.feedState.viewerContextVersion, 'two');
  });

  test(
      'feed context changes purge old projections and retry from the first page',
      () async {
    api.feedWork = (cursor) async {
      if (cursor != null) {
        throw const MomentsException('changed', code: 'CONTEXT_CHANGED');
      }
      return MomentsPageResult(
          items: [_post(api.feedCursors.length == 1 ? 'old' : 'fresh')],
          hasMore: true,
          nextCursor: 'older');
    };
    await repository.loadFeed();
    await repository.loadUser('friend');
    await repository.loadComments('post');
    await repository.loadNotifications();
    await repository.loadFeed(refresh: false);
    expect(api.feedCursors, [null, 'older', null]);
    expect(repository.feedState.items.single.momentId, 'fresh');
    expect(repository.postById('old'), isNull);
    expect(repository.userState('friend').author, isNull);
    expect(repository.userState('friend').coverUrl, isNull);
    expect(repository.commentState('post').items, isEmpty);
    expect(repository.notifications, isEmpty);
    expect(repository.unreadCount, 0);
  });

  test('persistent expired cursors retry once and remain recoverable',
      () async {
    api.feedWork = (_) async =>
        throw const MomentsException('expired', code: 'CURSOR_EXPIRED');
    await expectLater(repository.loadFeed(), throwsA(isA<MomentsException>()));
    expect(api.feedCursors, [null, null]);
    expect(repository.feedState.loading, isFalse);
    expect(repository.feedState.error, isA<MomentsException>());
    expect(repository.feedState.nextCursor, isNull);
    api.feedWork = (_) async => MomentsPageResult(items: [_post('recovered')]);
    await repository.loadFeed(refresh: false);
    expect(api.feedCursors.last, isNull);
    expect(repository.feedState.items.single.momentId, 'recovered');
  });

  test(
      'continuation while a restarted first page is loading cannot duplicate it',
      () async {
    final pending = Completer<MomentsPageResult<MomentPost>>();
    api.feedWork = (_) => pending.future;
    final first = repository.loadFeed(refresh: false);
    await Future<void>.delayed(Duration.zero);
    await repository.loadFeed(refresh: false);
    expect(api.feedCursors, [null]);
    pending.complete(MomentsPageResult(items: [_post('fresh')]));
    await first;
    expect(repository.feedState.items.single.momentId, 'fresh');
  });

  test('comment context restart replaces the stale comment list', () async {
    api.commentsWork = (cursor) async {
      if (cursor != null) {
        throw const MomentsException('expired', code: 'CURSOR_EXPIRED');
      }
      return MomentsPageResult(
          items: [_comment(api.commentCursors.length == 1 ? 'old' : 'fresh')],
          hasMore: true,
          nextCursor: 'older');
    };
    await repository.loadComments('post');
    await repository.loadComments('post', refresh: false);
    expect(api.commentCursors, [null, 'older', null]);
    expect(repository.commentState('post').items.single.commentId, 'fresh');
  });

  test('notification context restart replaces history and read watermarks',
      () async {
    api.notificationsWork = (cursor) async {
      if (cursor != null) {
        throw const MomentsException('changed', code: 'CONTEXT_CHANGED');
      }
      final seq = api.notificationCursors.length == 1 ? 1 : 5;
      return MomentsPageResult(
          items: [_notification('n-$seq', seq: seq)],
          hasMore: true,
          nextCursor: 'older',
          unreadCount: 1,
          readThroughSeq: seq,
          seenWatermark: 'seen-$seq');
    };
    await repository.loadNotifications();
    await repository.loadNotifications(refresh: false);
    expect(api.notificationCursors, [null, 'older', null]);
    expect(repository.notifications.single.notificationId, 'n-5');
    expect(repository.readThroughSeq, 5);
    expect(repository.seenWatermark, 'seen-5');
  });

  test('likes with an expired external cursor restart once from null',
      () async {
    api.likesWork = (cursor) async {
      if (cursor != null) {
        throw const MomentsException('expired', code: 'CURSOR_EXPIRED');
      }
      return const MomentsPageResult(items: [MomentLike(user: _friend)]);
    };
    final page = await repository.loadLikes('post', cursor: 'expired');
    expect(api.likesCursors, ['expired', null]);
    expect(page.items.single.user.userId, 'friend');
  });

  test('relation outage removes private caches without disabling recovery',
      () async {
    await repository.loadFeed();
    await repository.loadUser('friend');
    await repository.loadComments('post');
    await repository.loadNotifications();
    api.feedWork = (_) async => throw const MomentsException(
        'relation unavailable',
        code: 'RELATION_UNAVAILABLE');
    await expectLater(repository.loadFeed(), throwsA(isA<MomentsException>()));
    expect(repository.available, isTrue);
    expect(repository.postsById, isEmpty);
    expect(repository.friends, isEmpty);
    expect(repository.userState('friend').coverUrl, isNull);
    expect(repository.commentState('post').items, isEmpty);
    expect(repository.notifications, isEmpty);
    expect(repository.unreadCount, 0);
    api.feedWork = (_) async => MomentsPageResult(items: [_post('recovered')]);
    await repository.loadFeed(refresh: false);
    expect(repository.feedState.items.single.momentId, 'recovered');
    expect(repository.friends.single.userId, 'friend');
  });

  test(
      'relation outage rejects in-flight private responses from its old context',
      () async {
    final pending = Completer<MomentsPageResult<MomentComment>>();
    api.commentsWork = (_) => pending.future;
    final oldLoad = repository.loadComments('post');
    final oldExpectation =
        expectLater(oldLoad, throwsA(isA<MomentsException>()));
    await Future<void>.delayed(Duration.zero);
    api.feedWork = (_) async => throw const MomentsException(
        'relation unavailable',
        code: 'RELATION_UNAVAILABLE');
    await expectLater(repository.loadFeed(), throwsA(isA<MomentsException>()));
    pending.complete(MomentsPageResult(items: [_comment('private-old')]));
    await oldExpectation;
    expect(repository.commentState('post').items, isEmpty);
  });

  test('unlike self-cleanup does not require reading or interaction capability',
      () async {
    api.caps = const MomentsCapabilities(enabled: true);
    final result = await repository.setLiked('post', false);
    expect(result, isNull);
    expect(api.likeWrites, [false]);
    expect(api.detailCalls, 0);
  });

  test('confirmed unlike stays successful when the parent becomes unreadable',
      () async {
    await repository.loadFeed();
    api.detailError = const MomentsException('unavailable',
        code: 'MOMENT_UNAVAILABLE', permissionDenied: true);
    expect(await repository.setLiked('post', false), isNull);
    expect(api.likeWrites, [false]);
    expect(repository.postsById, isEmpty);
    expect(repository.feedState.items, isEmpty);
  });

  test(
      'confirmed unlike updates its local flag despite a refresh network error',
      () async {
    await repository.loadFriends();
    repository.applyPost(_post('post', liked: true));
    api.detailError = StateError('network');
    expect(await repository.setLiked('post', false), isNull);
    expect(repository.postById('post')!.likedByMe, isFalse);
    expect(repository.postById('post')!.likesPreview, isEmpty);
    expect(repository.postById('post')!.interactionCountsTrusted, isFalse);
  });

  test('new likes still require the interaction capability', () async {
    api.caps = const MomentsCapabilities(enabled: true, readEnabled: true);
    await expectLater(
        repository.setLiked('post', true), throwsA(isA<MomentsException>()));
    expect(api.likeWrites, isEmpty);
  });

  test('comment self-cleanup succeeds when the parent loses reading capability',
      () async {
    await repository.loadComments('post');
    repository.capabilities =
        api.caps = const MomentsCapabilities(enabled: true);
    await repository.deleteComment('post', 'own-comment');
    expect(api.deletedComments, ['own-comment']);
    expect(repository.commentState('post').items, isEmpty);
    expect(api.detailCalls, 0);
  });

  test('confirmed comment removal updates previews when the refresh fails',
      () async {
    await repository.loadFeed();
    await repository.loadComments('post');
    api.detailError = StateError('network');
    await repository.deleteComment('post', 'own-comment');
    expect(repository.commentState('post').items, isEmpty);
    expect(repository.postById('post')!.commentsPreview, isEmpty);
    expect(repository.postById('post')!.interactionCountsTrusted, isFalse);
  });

  group('OpenIM moments business notifications', () {
    late _FakeIM im;
    setUp(() {
      Get.testMode = true;
      Get.put<AppController>(_FakeApp());
      im = Get.put<IMController>(_FakeIM()) as _FakeIM;
      repository.dispose();
      repository = _repository(api, sdk: true);
    });
    tearDown(() => Get.reset());

    testWidgets('map and string data invalidate and deduplicate only event IDs',
        (tester) async {
      await repository.loadFeed();
      await repository.loadUser('friend');
      await repository.loadDetail('post');
      await repository.loadComments('post');
      await repository.loadNotifications();
      final scope = repository.authorizationScope;
      api.version = 2;
      final event = {
        'key': 'moments',
        'data': {
          'eventId': 'event-1',
          'momentId': 'post',
          'action': 'LIKE_CHANGED',
          'aggregateVersion': 99999,
          'occurredAt': 1,
          'text': 'untrusted payload must never become a post'
        }
      };
      im.recvCustomBusinessMessage(jsonEncode(event));
      await tester.pump();
      expect(repository.authorizationScope, isNot(scope));
      expect(repository.postsById, isEmpty);
      expect(repository.notifications, isEmpty);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(repository.postById('post')!.version, 2);
      expect(repository.postById('post')!.text, 'authorised content');
      expect(api.detailCalls, 2);
      expect(api.commentCursors, [null, null]);
      expect(api.notificationCursors, [null, null]);
      final calls = api.feedCursors.length;
      final after = repository.authorizationScope;
      im.recvCustomBusinessMessage(jsonEncode(event));
      await tester.pump(const Duration(milliseconds: 250));
      expect(api.feedCursors.length, calls);
      expect(repository.authorizationScope, after);
      api.version = 3;
      im.recvCustomBusinessMessage(jsonEncode({
        'key': 'moments',
        'data': jsonEncode({'eventId': 'event-2', 'momentId': 'post'})
      }));
      await tester.pump();
      expect(repository.postsById, isEmpty);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(repository.postById('post')!.version, 3);
    });

    testWidgets('matching key with malformed data still safely refreshes',
        (tester) async {
      await repository.loadFeed();
      im.recvCustomBusinessMessage(jsonEncode({'key': 'moments', 'data': '{'}));
      await tester.pump();
      expect(repository.postsById, isEmpty);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(api.feedCursors, [null, null]);
      final scope = repository.authorizationScope;
      im.recvCustomBusinessMessage(jsonEncode({
        'key': 'other-feature',
        'data': {'eventId': 'foreign'}
      }));
      im.recvCustomBusinessMessage(jsonEncode({'event': 'moment_changed'}));
      await tester.pump(const Duration(milliseconds: 250));
      expect(api.feedCursors, [null, null]);
      expect(repository.authorizationScope, scope);
    });

    testWidgets(
        'feed read failure does not prevent notification synchronization',
        (tester) async {
      await repository.loadFeed();
      api.feedWork = (_) async => throw StateError('network');
      im.recvCustomBusinessMessage(jsonEncode({
        'key': 'moments',
        'data': {'eventId': 'event'}
      }));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(repository.feedState.error, isA<StateError>());
      expect(api.notificationCursors, [null]);
      expect(repository.notifications.single.notificationId, 'n');
    });

    testWidgets('session reset cancels a previous session scheduled reload',
        (tester) async {
      await repository.loadFeed();
      im.recvCustomBusinessMessage(jsonEncode({
        'key': 'moments',
        'data': {'eventId': 'event'}
      }));
      await tester.pump();
      repository.resetSession();
      await repository.ensureCapabilities();
      await tester.pump(const Duration(milliseconds: 250));
      expect(api.feedCursors, [null]);
      expect(repository.postsById, isEmpty);
    });
  });
}
