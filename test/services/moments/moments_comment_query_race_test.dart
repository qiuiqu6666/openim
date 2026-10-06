import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/moments_repository.dart';

import '../../pages/moments/privacy/privacy_test_store.dart';
import '../../pages/moments/support/moments_ui_fixture.dart';

const _owned = MomentComment(
    commentId: 'owned-before-refresh',
    author: momentsUiSelf,
    text: 'My existing comment',
    createdAt: 1791000600000,
    canDelete: true);
const _next = MomentComment(
    commentId: 'next-page-comment',
    author: momentsUiFriend,
    text: 'Next page remains readable',
    createdAt: 1791000900000);

class _CommentRaceApi extends MomentsUiApi {
  _CommentRaceApi()
      : super(posts: [
          for (final post in momentsUiPosts())
            if (post.momentId == momentsUiFriendPostId)
              MomentPost.fromJson({
                ...post.toJson(),
                'commentsPreview': [
                  _owned.toJson(),
                  momentsUiComments.first.toJson()
                ],
                'commentCount': 2,
              })
            else
              post,
        ]);

  final deleted = <String>[];

  @override
  Future<void> deleteComment(String momentId, String commentId) async {
    deleted.add(commentId);
    final comments = commentItems[momentId]!;
    comments.removeWhere((comment) => comment.commentId == commentId);
    final post = posts[momentId]!;
    posts[momentId] = MomentPost.fromJson({
      ...post.toJson(),
      'version': post.version + 1,
      'commentCount': comments.length,
      'commentsPreview': comments.map((comment) => comment.toJson()).toList(),
    });
  }
}

Future<void> _assertConfirmedMutationSurvives({required bool remove}) async {
  final api = _CommentRaceApi();
  final repository = MomentsRepository(
      api: api,
      userIdProvider: () => momentsUiSelf.userId,
      environmentProvider: () => momentsUiServer,
      friendLoader: () async => const [momentsUiFriend, momentsUiSecondFriend],
      privacySelectionStore: MemoryPrivacySelectionStore(
          ownerUserId: momentsUiSelf.userId, baseUrl: momentsUiServer),
      subscribeToSdk: false);
  addTearDown(repository.dispose);
  api.commentsWork = (_, __) async => MomentsPageResult(
      items: List.of(api.commentItems[momentsUiFriendPostId]!),
      nextCursor: 'confirmed-next',
      hasMore: true,
      viewerContextVersion: 'context-one');
  await repository.loadDetail(momentsUiFriendPostId, trackForSync: false);
  await repository.loadComments(momentsUiFriendPostId);
  final state = repository.commentState(momentsUiFriendPostId);
  final oldItems = List<MomentComment>.of(state.items);
  final gate = Completer<MomentsPageResult<MomentComment>>();
  final entered = Completer<void>();
  api.commentsWork = (_, cursor) async {
    if (cursor == null) {
      if (!entered.isCompleted) entered.complete();
      return gate.future;
    }
    expect(cursor, 'confirmed-next');
    return const MomentsPageResult(
        items: [_next], viewerContextVersion: 'context-one');
  };
  final oldRead = repository.loadComments(momentsUiFriendPostId, refresh: true);
  addTearDown(() async {
    if (!gate.isCompleted) gate.complete(MomentsPageResult(items: oldItems));
    await oldRead;
  });
  await entered.future;
  expect(state.loading, isTrue);
  expect(state.nextCursor, 'confirmed-next');

  String? createdId;
  if (remove) {
    await repository.deleteComment(momentsUiFriendPostId, _owned.commentId);
    expect(api.deleted, [_owned.commentId]);
    expect(state.items.map((comment) => comment.commentId),
        isNot(contains(_owned.commentId)));
  } else {
    final created = await repository.addComment(momentsUiFriendPostId,
        text: 'Confirmed while old refresh was pending',
        clientRequestId: 'stable-write-key');
    createdId = created.commentId;
    expect(api.commentWrites.single['clientRequestId'], 'stable-write-key');
    expect(
        state.items.map((comment) => comment.commentId), contains(createdId));
  }
  expect(state.loading, isFalse,
      reason: 'A successful mutation releases the superseded read state');
  expect(state.error, isNull);
  expect(state.nextCursor, 'confirmed-next');
  expect(state.hasMore, isTrue);

  gate.complete(MomentsPageResult(
      items: oldItems,
      nextCursor: 'stale-next',
      hasMore: true,
      viewerContextVersion: 'context-one'));
  final late = await oldRead;
  final ids = state.items.map((comment) => comment.commentId).toList();
  expect(late.items.map((comment) => comment.commentId), ids);
  expect(state.loading, isFalse);
  expect(state.error, isNull);
  expect(state.nextCursor, 'confirmed-next');
  if (remove) {
    expect(ids, isNot(contains(_owned.commentId)));
  } else {
    expect(ids, contains(createdId));
  }

  await repository.loadComments(momentsUiFriendPostId, refresh: false);
  expect(api.commentRequests, [null, null, 'confirmed-next']);
  final continued = state.items.map((comment) => comment.commentId).toList();
  expect(continued, contains(_next.commentId));
  expect(continued,
      remove ? isNot(contains(_owned.commentId)) : contains(createdId));
  expect(state.loading, isFalse);
  expect(state.error, isNull);
  expect(state.hasMore, isFalse);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('late comment refresh cannot swallow a confirmed new comment',
      () => _assertConfirmedMutationSurvives(remove: false));

  test('late comment refresh cannot revive a confirmed deleted comment',
      () => _assertConfirmedMutationSurvives(remove: true));
}
