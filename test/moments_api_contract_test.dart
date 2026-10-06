import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/moments_api.dart';

const me = MomentUser(userId: 'me', nickname: 'Me');
MomentPost post(String id) => MomentPost(
    momentId: id,
    author: me,
    text: 'text',
    createdAt: 1790985600000,
    version: 1,
    canLike: true,
    canComment: true,
    canDelete: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('real business API boundary', () {
    late Dio client;
    late MomentsApi api;
    late List<RequestOptions> requests;
    late dynamic payload;
    late int status;
    var token = 'business-token';
    setUp(() {
      requests = [];
      status = 200;
      token = 'business-token';
      payload = {'errCode': 0, 'data': post('created').toJson()};
      client = Dio();
      client.interceptors
          .add(InterceptorsWrapper(onRequest: (request, handler) {
        requests.add(request);
        handler.resolve(Response(
            requestOptions: request, statusCode: status, data: payload));
      }));
      api = MomentsApi(
          client: client,
          baseUrl: 'https://business.example/chat/',
          tokenProvider: () => token);
    });
    tearDown(() => client.close(force: true));
    test('uses chat token and stable body/header key with a new request trace',
        () async {
      for (var i = 0; i < 2; i++) {
        await api.createPost(
            clientRequestID: 'stable-id',
            text: 'hello',
            mediaIds: ['media'],
            visibility: 'PARTIAL',
            audienceUserIds: ['friend']);
      }
      expect(requests, hasLength(2));
      expect(requests.first.path, 'https://business.example/chat/moments');
      expect(requests.first.headers['token'], 'business-token');
      expect(requests.first.headers['Authorization'], isNull);
      expect(requests.first.headers['Idempotency-Key'], 'stable-id');
      expect(requests.first.data['clientRequestID'], 'stable-id');
      expect(requests.first.data.containsKey('authorId'), false);
      expect(requests.first.data, {
        'clientRequestID': 'stable-id',
        'text': 'hello',
        'mediaIDs': ['media'],
        'visibility': 'PARTIAL',
        'audienceUserIds': ['friend']
      });
      expect(requests.first.data.containsKey('mediaIds'), false);
      expect(requests.first.headers['operationID'],
          isNot(requests.last.headers['operationID']));
      expect(requests.first.data, requests.last.data);
    });
    test('unimplemented endpoints are unavailable without synthetic success',
        () async {
      for (final code in [404, 501]) {
        status = code;
        await expectLater(
            api.capabilities(),
            throwsA(isA<MomentsException>()
                .having((e) => e.unavailable, 'unavailable', true)));
      }
    });
    test('5xx and malformed success leave creation result unknown', () async {
      status = 503;
      await expectLater(
          api.createPost(clientRequestID: 'stable-id', text: 'hello'),
          throwsA(isA<MomentsException>()
              .having((e) => e.unknownResult, 'unknown', true)));
      status = 200;
      payload = {
        'errCode': 0,
        'data': {'momentId': 'created'}
      };
      await expectLater(
          api.createPost(clientRequestID: 'stable-id', text: 'hello'),
          throwsA(isA<MomentsException>()
              .having((e) => e.unknownResult, 'unknown', true)));
    });
    test('authorization failure is definite and does not expose raw request',
        () async {
      status = 401;
      await expectLater(
          api.createPost(clientRequestID: 'stable-id', text: 'hello'),
          throwsA(isA<MomentsException>()
              .having((e) => e.authRequired, 'auth', true)
              .having((e) => e.unknownResult, 'unknown', false)
              .having(
                  (e) => e.toString().contains(token), 'token leaked', false)));
    });
    test('private media rejects foreign origins and token-bearing URLs',
        () async {
      for (final path in [
        'https://other.example/moments/media/id/content',
        '//other.example/moments/media/id/content',
        '/moments/media/id/content?token=secret',
        '/user/photo'
      ]) {
        await expectLater(
            api.downloadMedia(MomentMedia(mediaId: 'id', contentPath: path)),
            throwsA(isA<MomentsException>()));
      }
      expect(requests, isEmpty);
      expect(api.mediaUrl('/moments/media/id/content'),
          'https://business.example/chat/moments/media/id/content');
    });
    test('private bytes use same-origin proxy and disable redirect forwarding',
        () async {
      payload = [1, 2, 3];
      expect(
          await api.downloadMedia(const MomentMedia(mediaId: 'id')), [1, 2, 3]);
      expect(requests.single.headers['token'], 'business-token');
      expect(requests.single.followRedirects, false);
      expect(requests.single.responseType, ResponseType.bytes);
    });
    test('a late media response is discarded after a credential switch',
        () async {
      client.interceptors.clear();
      client.interceptors
          .add(InterceptorsWrapper(onRequest: (request, handler) {
        token = 'another-account-token';
        handler.resolve(
            Response(requestOptions: request, statusCode: 200, data: [1, 2]));
      }));
      await expectLater(
          api.downloadMedia(const MomentMedia(mediaId: 'id')),
          throwsA(isA<MomentsException>()
              .having((e) => e.authRequired, 'changed session', true)));
    });
    test('read all posts the captured watermark without an unbounded readAll',
        () async {
      payload = {
        'errCode': 0,
        'data': {'unreadCount': 1}
      };
      await api.markNotificationsRead(
          readThroughSeq: 100, seenWatermark: 'watermark-100');
      expect(requests.single.data, {
        'notificationIDs': [],
        'markThrough': true,
        'readThroughSeq': 100,
        'seenWatermark': 'watermark-100'
      });
      expect(requests.single.data.containsKey('readAll'), false);
    });
    test('supportsMoments is authoritative without legacy version gates',
        () async {
      payload = {
        'errCode': 0,
        'data': {
          'supportsMoments': true,
          'enabled': false,
          'readEnabled': false,
          'videoEnabled': true,
          'reportsEnabled': true
        }
      };
      final capabilities = await api.capabilities();
      expect(capabilities.supportsMoments, true);
      expect(capabilities.enabled, true);
      expect(capabilities.readEnabled, true);
      expect(capabilities.publishEnabled, true);
      expect(capabilities.interactionsEnabled, true);
      expect(capabilities.settingsEnabled, true);
      expect(capabilities.protocolVersion, 0);
      expect(capabilities.videoEnabled, false);
      expect(capabilities.reportsEnabled, false);
      for (final value in [null, false, 'true']) {
        payload['data'] = {
          'enabled': true,
          'protocolVersion': 1,
          if (value != null) 'supportsMoments': value
        };
        expect((await api.capabilities()).enabled, false);
      }
    });
    test('all paginated endpoints send limit and preserve opaque cursor',
        () async {
      payload = {
        'errCode': 0,
        'data': {'items': [], 'hasMore': false}
      };
      const cursor = 'opaque+cursor/=';
      await api.feed(cursor: cursor, pageSize: 99);
      await api.userMoments('friend', cursor: cursor, pageSize: 99);
      await api.comments('post', cursor: cursor, pageSize: 99);
      await api.likes('post', cursor: cursor, pageSize: 99);
      await api.notifications(cursor: cursor, pageSize: 99);
      for (final request in requests) {
        expect(request.queryParameters, {'cursor': cursor, 'limit': 50});
      }
      await api.feed(pageSize: 0);
      expect(requests.last.queryParameters, {'limit': 1});
    });
    test('comment uses stable key and replyToCommentID empty-string contract',
        () async {
      payload = {
        'errCode': 0,
        'data': {
          'commentId': 'comment',
          'author': me.toJson(),
          'text': 'hello',
          'replyToCommentID': ''
        }
      };
      final comment = await api.createComment('post',
          text: ' hello ', clientRequestId: 'stable-comment');
      expect(comment.replyToCommentId, isNull);
      expect(requests.single.data, {
        'clientRequestID': 'stable-comment',
        'text': 'hello',
        'replyToCommentID': ''
      });
      expect(requests.single.headers['Idempotency-Key'], 'stable-comment');
      await api.createComment('post',
          text: 'reply',
          clientRequestId: 'stable-reply',
          replyToCommentId: 'root');
      expect(requests.last.data['replyToCommentID'], 'root');
      expect(requests.last.data.containsKey('replyToCommentId'), false);
    });
    test('single notification read cannot accidentally mark through', () async {
      payload = {
        'errCode': 0,
        'data': {'unreadCount': 2}
      };
      await api.markNotificationsRead(notificationIds: ['notification']);
      expect(requests.single.data, {
        'notificationIDs': ['notification'],
        'markThrough': false
      });
    });
    test('sync rejects overflow and invalid IDs before sending momentIDs',
        () async {
      payload = {
        'errCode': 0,
        'data': {
          'items': [
            {'momentId': 'private', 'unavailable': true}
          ]
        }
      };
      for (final ids in [
        List.generate(51, (index) => 'post-$index'),
        [''],
        [' padded ']
      ]) {
        await expectLater(
            api.sync(ids),
            throwsA(isA<MomentsException>()
                .having((e) => e.code, 'arguments', 'ArgsError')));
      }
      expect(requests, isEmpty);
      final result =
          await api.sync(List.generate(50, (index) => 'post-$index'));
      expect(requests.single.data.keys, ['momentIDs']);
      expect(requests.single.data['momentIDs'], hasLength(50));
      expect(
          result['items'].single, {'momentId': 'private', 'unavailable': true});
    });
    test('resource-only cancellation and deletion acknowledgements succeed',
        () async {
      payload = {
        'errCode': 0,
        'data': {'momentID': 'post', 'removed': true}
      };
      await api.setLiked('post', false);
      payload['data'] = {'commentID': 'comment', 'removed': true};
      await api.deleteComment('post', 'comment');
      expect(requests.map((request) => request.method), ['DELETE', 'DELETE']);
      expect(requests.first.path, endsWith('/post/likes/me'));
      expect(requests.last.path, endsWith('/post/comments/comment'));
    });
    test(
        '20012 semantic comes from errDlt and relation failure stays retryable',
        () async {
      for (final semantic in [
        'MOMENT_UNAVAILABLE',
        'PERMISSION_REVOKED',
        'RELATION_UNAVAILABLE',
        'IDEMPOTENCY_CONFLICT',
        'VERSION_CONFLICT',
        'MEDIA_NOT_READY',
        'MEDIA_EXPIRED',
        'CURSOR_EXPIRED',
        'CONTEXT_CHANGED'
      ]) {
        payload = {
          'errCode': 20012,
          'errMsg': 'Forbidden',
          'errDlt': semantic,
          'errorCode': 'incorrect-legacy-code',
          'data': null
        };
        await expectLater(
            api.detail('post'),
            throwsA(isA<MomentsException>()
                .having((e) => e.code, 'semantic', semantic)
                .having((e) => e.unavailable, 'module unavailable', false)
                .having((e) => e.relationUnavailable, 'relation unavailable',
                    semantic == 'RELATION_UNAVAILABLE')
                .having(
                    (e) => e.permissionDenied,
                    'permission denied',
                    ['MOMENT_UNAVAILABLE', 'PERMISSION_REVOKED']
                        .contains(semantic))));
      }
      payload = {
        'errCode': 1001,
        'errMsg': 'ArgsError',
        'errDlt': 'invalid arguments',
        'data': null
      };
      await expectLater(
          api.createPost(clientRequestID: 'key', text: 'hello'),
          throwsA(isA<MomentsException>()
              .having((e) => e.code, 'arguments', 'ArgsError')
              .having((e) => e.unknownResult, 'definite rejection', false)));
    });
    test('uploads only send file and clientMediaId for image and cover',
        () async {
      final directory = await Directory.systemTemp.createTemp('moments-api-');
      final file = File('${directory.path}/image.png');
      await file.writeAsBytes([137, 80, 78, 71]);
      addTearDown(() async {
        await file.delete();
        await directory.delete();
      });
      payload = {
        'errCode': 0,
        'data': {
          'mediaID': 'image',
          'contentPath': '/moments/media/image/content'
        }
      };
      final image = await api.uploadMedia(
          filePath: file.path, clientMediaId: 'stable-media');
      final cover = await api.uploadCover(
          filePath: file.path, clientMediaId: 'stable-cover');
      expect(image.type, 'IMAGE');
      expect(image.status, 'READY');
      expect(cover.status, 'READY');
      for (final request in requests) {
        final form = request.data as FormData;
        expect(form.files.map((part) => part.key), ['file']);
        expect(form.fields.map((part) => part.key), ['clientMediaId']);
      }
      expect((requests.first.data as FormData).fields.single.value,
          'stable-media');
      expect(
          (requests.last.data as FormData).fields.single.value, 'stable-cover');
    });
    test('unsupported video reports and status routes do not send requests',
        () async {
      await expectLater(
          api.uploadMedia(
              filePath: 'unused', clientMediaId: 'media', type: 'VIDEO'),
          throwsA(isA<MomentsException>()));
      await expectLater(
          api.reportPost('post', reason: 'unused'),
          throwsA(isA<MomentsException>()
              .having((e) => e.unavailable, 'reports closed', true)));
      await expectLater(
          api.mediaStatus('media'),
          throwsA(isA<MomentsException>()
              .having((e) => e.unavailable, 'status unsupported', true)));
      expect(requests, isEmpty);
    });
    test('real supplied feed settings and notification JSON decode unchanged',
        () async {
      // Exact examples supplied by the backend owner in moments-backend-contract.
      final fixtures = jsonDecode(
          await File('test/fixtures/moments_backend_responses.json')
              .readAsString()) as Map<String, dynamic>;
      payload = fixtures['feed'];
      final feed = await api.feed();
      final item = feed.items.single;
      expect(item.momentId, 'moment-example');
      expect(item.author.userId, 'im_example_author');
      expect(item.author.avatarUrl,
          'http://8.217.191.236:10002/object/example/avatar');
      expect(item.createdAt, 1790985600000);
      expect(item.authorSettingsVersion, 0);
      expect(item.mediaList.single.mediaId, 'media-example');
      expect(item.mediaList.single.isReady, true);
      expect(item.likesPreview.single.user.userId, 'im_example_friend');
      expect(item.likesPreview.single.createdAt, 1790985660000);
      expect(item.commentsPreview.single.commentId, 'comment-example');
      expect(item.commentsPreview.single.author.userId, 'im_example_friend');
      expect(item.commentsPreview.single.replyToCommentId, isNull);
      expect(item.commentsPreview.single.rootCommentId, isNull);
      expect(item.commentsPreview.single.replyToUser, isNull);
      expect(item.commentsPreview.single.replyTargetDeleted, false);
      expect(item.commentsPreview.single.canDelete, false);
      expect(item.audienceUserIds, isEmpty);
      expect(item.canLike, true);
      expect(item.canDelete, false);
      expect(feed.hasMore, false);
      expect(feed.nextCursor, '');
      payload = fixtures['settings'];
      final settings = await api.settings();
      expect(settings.visibleRangeDays, 0);
      expect(settings.coverMediaId, '');
      expect(settings.coverUrl, '');
      expect(settings.version, 0);
      expect(settings.viewerContextVersion, feed.viewerContextVersion);
      expect(settings.blockedViewersLoaded, false);
      expect(settings.hiddenAuthorsLoaded, false);
      payload = fixtures['notifications'];
      final notifications = await api.notifications();
      final notification = notifications.items.single;
      expect(notification.notificationId, 'notification-example');
      expect(notification.type, 'LIKE');
      expect(notification.momentId, 'moment-example');
      expect(notification.commentId, '');
      expect(notification.read, false);
      expect(notification.available, true);
      expect(notifications.readThroughSeq, 1);
      expect(notifications.unreadCount, 1);
      expect(notifications.seenWatermark, 'example-watermark');
    });
    test('real null arrays zero watermark and unavailable actors are valid',
        () async {
      payload = {
        'errCode': 0,
        'data': {
          'items': null,
          'nextCursor': '',
          'hasMore': false,
          'lastSeq': 0,
          'unreadCount': 0,
          'seenWatermark': ''
        }
      };
      final empty = await api.notifications();
      expect(empty.items, isEmpty);
      expect(empty.readThroughSeq, 0);
      expect(empty.unreadCount, 0);
      final noLists = MomentPost.fromJson({
        'momentID': 'post',
        'author': {'userID': 'me', 'avatarURL': ''},
        'mediaList': null,
        'likesPreview': null,
        'commentsPreview': null,
        'audienceUserIds': null,
        'likeCount': 0,
        'commentCount': 0,
        'version': 0
      });
      expect(noLists.mediaList, isEmpty);
      expect(noLists.likesPreview, isEmpty);
      expect(noLists.commentsPreview, isEmpty);
      expect(noLists.audienceUserIds, isEmpty);
      expect(noLists.version, 0);
      expect(noLists.canLike, false);
      final unavailable = MomentNotification.fromJson({
        'notificationID': 'unavailable',
        'type': 'reply',
        'actor': null,
        'unavailable': true,
        'unread': false,
        'momentID': 'post',
        'commentID': 'comment'
      });
      expect(unavailable.available, false);
      expect(unavailable.actor.userId, '');
      expect(unavailable.type, 'REPLY');
      expect(unavailable.read, true);
      expect(unavailable.asRead().commentId, 'comment');
      payload['data']['items'] = {};
      await expectLater(api.notifications(), throwsA(isA<FormatException>()));
      payload['data'].remove('items');
      await expectLater(api.notifications(), throwsA(isA<FormatException>()));
    });
    test('new reply fields retain authorized deleted target anonymously', () {
      final reply = MomentComment.fromJson({
        'commentID': 'reply',
        'actor': {'userID': 'me', 'nickname': 'Me', 'avatarURL': ''},
        'text': 'reply',
        'rootCommentID': 'root',
        'replyToCommentID': 'target',
        'replyToDeleted': true,
        'replyTo': {
          'userID': 'friend',
          'nickname': 'old name',
          'avatarURL': 'old photo',
          'remark': 'old remark'
        }
      });
      expect(reply.replyTargetDeleted, true);
      expect(reply.rootCommentId, 'root');
      expect(reply.replyToCommentId, 'target');
      expect(reply.replyToUser!.userId, 'friend');
      expect(reply.replyToUser!.nickname, '');
      expect(reply.replyToUser!.avatarUrl, '');
      expect(reply.replyTargetLabel, '已删除评论');
    });
    test('result-query SUCCEEDED accepts upper-case resource IDs', () async {
      payload = {
        'errCode': 0,
        'data': {'status': 'SUCCEEDED', 'momentID': 'published'}
      };
      final published = await api.queryPublishResult('stable');
      expect(published.succeeded, true);
      expect(published.resourceId, 'published');
      payload['data'] = {'status': 'SUCCEEDED', 'commentID': 'comment'};
      final comment = await api.queryCommentResult('stable');
      expect(comment.succeeded, true);
      expect(comment.resourceId, 'comment');
    });
    test('settings distinguish missing lists from explicit empty lists', () {
      const constructed = MomentsSettings();
      expect(constructed.blockedViewersLoaded, true);
      expect(constructed.hiddenAuthorsLoaded, true);
      final missing = MomentsSettings.fromJson({'visibleRangeDays': 0});
      expect(missing.blockedViewersLoaded, false);
      expect(missing.hiddenAuthorsLoaded, false);
      final explicitNull = MomentsSettings.fromJson(
          {'blockedViewerIDs': null, 'hiddenAuthorIDs': null});
      expect(explicitNull.blockedViewersLoaded, true);
      expect(explicitNull.hiddenAuthorsLoaded, true);
      expect(explicitNull.blockedViewerIds, isEmpty);
      expect(explicitNull.hiddenAuthorIds, isEmpty);
      final explicitLists = MomentsSettings.fromJson({
        'blockedViewerIds': ['viewer'],
        'hiddenAuthorIDs': ['author']
      });
      expect(explicitLists.blockedViewersLoaded, true);
      expect(explicitLists.hiddenAuthorsLoaded, true);
      expect(explicitLists.blockedViewerIds, ['viewer']);
      expect(explicitLists.hiddenAuthorIds, ['author']);
    });
    test('malformed privacy lists fail instead of becoming a known empty list',
        () async {
      for (final field in ['blockedViewerIds', 'hiddenAuthorIDs']) {
        for (final invalid in [
          false,
          {},
          'not-a-list',
          [1],
          ['']
        ]) {
          payload = {
            'errCode': 0,
            'data': {field: invalid}
          };
          await expectLater(api.settings(), throwsA(isA<FormatException>()));
        }
      }
    });
    test('known business envelope takes priority over non-2xx HTTP status',
        () async {
      for (final code in ['VERSION_CONFLICT', 'MEDIA_NOT_READY']) {
        status = 409;
        payload = {
          'errCode': 20012,
          'errMsg': 'Forbidden',
          'errDlt': code,
          'data': null
        };
        await expectLater(
            api.createPost(clientRequestID: 'stable', text: 'hello'),
            throwsA(isA<MomentsException>()
                .having((e) => e.code, 'semantic', code)
                .having((e) => e.unknownResult, 'definite rejection', false)));
      }
      status = 503;
      payload['errDlt'] = 'MEDIA_NOT_READY';
      await expectLater(
          api.createPost(clientRequestID: 'stable', text: 'hello'),
          throwsA(isA<MomentsException>()
              .having((e) => e.code, 'semantic', 'MEDIA_NOT_READY')
              .having((e) => e.unknownResult, 'definite rejection', false)));
      payload['errDlt'] = 'undocumented';
      await expectLater(
          api.createPost(clientRequestID: 'stable', text: 'hello'),
          throwsA(isA<MomentsException>().having(
              (e) => e.unknownResult, 'unconfirmed transport error', true)));
    });
  });
}
