import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/moments/moments_likes_page.dart';
import 'package:openim/pages/moments/presentation/moments_theme.dart';
import 'package:openim/services/moments_repository.dart';
import 'package:openim_common/openim_common.dart';

import '../../../support/performance/render_test_fakes.dart';

const _alice = MomentUser(userId: 'alice', nickname: 'Alice');
const _bob = MomentUser(userId: 'bob', nickname: 'Bob');
const _post =
    MomentPost(momentId: 'post', author: renderTestUser, canDelete: true);

class _Api extends RenderTestApi {
  final calls = <String>[];
  Future<MomentsPageResult<MomentLike>> Function(String, String?)? likesWork;
  @override
  Future<MomentsCapabilities> capabilities() async =>
      MomentsCapabilities.fromJson({'supportsMoments': true});
  @override
  Future<MomentsPageResult<MomentLike>> likes(String momentId,
      {String? cursor, int pageSize = 20}) async {
    calls.add('$momentId:${cursor ?? 'first'}');
    return likesWork?.call(momentId, cursor) ??
        const MomentsPageResult(items: [MomentLike(user: _alice)]);
  }
}

MomentsRepository _repository(_Api api) => MomentsRepository(
    api: api,
    userIdProvider: () => 'me',
    environmentProvider: () => 'test',
    friendLoader: () async => const [_alice, _bob],
    subscribeToSdk: false);

Future<void> _mount(WidgetTester tester, MomentsRepository repository,
    {String momentId = 'post',
    Brightness brightness = Brightness.light,
    ValueChanged<MomentUser>? onOpenAuthor}) async {
  await tester.pumpWidget(renderTestHost(
      MomentsLikesPage(
          repository: repository,
          momentId: momentId,
          onOpenAuthor: onOpenAuthor),
      brightness: brightness));
  await tester.pump();
}

void main() {
  tearDown(Get.reset);
  for (final brightness in Brightness.values) {
    testWidgets('likes rows use reference sizes and colors in $brightness',
        (tester) async {
      final api = _Api();
      final repository = _repository(api)..applyPost(_post);
      addTearDown(repository.dispose);
      MomentUser? opened;
      await _mount(tester, repository,
          brightness: brightness, onOpenAuthor: (user) => opened = user);
      await tester.pumpAndSettle();
      final avatar = tester.widget<AvatarView>(find.byType(AvatarView));
      expect(avatar.width, 44);
      expect(avatar.height, 44);
      final dark = brightness == Brightness.dark;
      expect(tester.widget<Text>(find.text('Alice')).style!.color,
          MomentsTheme.text(dark));
      expect(tester.widget<Text>(find.text('Alice')).style!.fontWeight,
          FontWeight.w600);
      expect(find.text('All visible likes loaded'), findsNothing);
      await tester.tap(find.text('Alice'));
      expect(opened, _alice);
      expect(api.calls, ['post:first']);
    });
  }

  testWidgets('deleted cached post clears visible likes immediately',
      (tester) async {
    final api = _Api();
    final repository = _repository(api)..applyPost(_post);
    addTearDown(repository.dispose);
    await _mount(tester, repository);
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsOneWidget);
    await repository.deletePost('post');
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsNothing);
    expect(find.text('Likes unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(api.calls, ['post:first']);
  });

  testWidgets('old repository result cannot populate a replacement page',
      (tester) async {
    final pending = Completer<MomentsPageResult<MomentLike>>();
    final oldApi = _Api()..likesWork = (_, __) => pending.future;
    final old = _repository(oldApi)..applyPost(_post);
    final nextApi = _Api()
      ..likesWork = (_, __) async =>
          const MomentsPageResult(items: [MomentLike(user: _bob)]);
    final next = _repository(nextApi)..applyPost(_post);
    addTearDown(old.dispose);
    addTearDown(next.dispose);
    await _mount(tester, old);
    await _mount(tester, next);
    await tester.pumpAndSettle();
    pending
        .complete(const MomentsPageResult(items: [MomentLike(user: _alice)]));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsNothing);
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('refresh does not duplicate an already pending first page',
      (tester) async {
    final pending = Completer<MomentsPageResult<MomentLike>>();
    final api = _Api()..likesWork = (_, __) => pending.future;
    final repository = _repository(api)..applyPost(_post);
    addTearDown(repository.dispose);
    await _mount(tester, repository);
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    expect(api.calls, ['post:first']);
    pending.complete(const MomentsPageResult(items: []));
    await tester.pumpAndSettle();
    expect(find.text('No visible likes yet'), findsOneWidget);
  });

  testWidgets('pagination appends by actor without replacing previous rows',
      (tester) async {
    final api = _Api()
      ..likesWork = (_, cursor) async => cursor == null
          ? const MomentsPageResult(
              items: [MomentLike(user: _alice)],
              nextCursor: 'next',
              hasMore: true)
          : const MomentsPageResult(
              items: [MomentLike(user: _alice), MomentLike(user: _bob)]);
    final repository = _repository(api)..applyPost(_post);
    addTearDown(repository.dispose);
    await _mount(tester, repository);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(api.calls, ['post:first', 'post:next']);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('session invalidation drops a late likes response',
      (tester) async {
    final pending = Completer<MomentsPageResult<MomentLike>>();
    final api = _Api()..likesWork = (_, __) => pending.future;
    final repository = _repository(api)..applyPost(_post);
    addTearDown(repository.dispose);
    await _mount(tester, repository);
    repository.resetSession();
    await tester.pump();
    pending
        .complete(const MomentsPageResult(items: [MomentLike(user: _alice)]));
    await tester.pumpAndSettle();
    expect(find.text('Alice'), findsNothing);
    expect(api.calls, ['post:first']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changed page context replaces old likes from a fresh first page',
      (tester) async {
    var firstPages = 0;
    final api = _Api()
      ..likesWork = (_, cursor) async {
        if (cursor != null) {
          return const MomentsPageResult(
              items: [MomentLike(user: _bob)], viewerContextVersion: 'new');
        }
        if (firstPages++ == 0) {
          return const MomentsPageResult(
              items: [MomentLike(user: _alice)],
              nextCursor: 'next',
              hasMore: true,
              viewerContextVersion: 'old');
        }
        return const MomentsPageResult(
            items: [MomentLike(user: _bob)], viewerContextVersion: 'new');
      };
    final repository = _repository(api)..applyPost(_post);
    addTearDown(repository.dispose);
    await _mount(tester, repository);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(api.calls, ['post:first', 'post:next', 'post:first']);
    expect(find.text('Alice'), findsNothing);
    expect(find.text('Bob'), findsOneWidget);
  });
}
