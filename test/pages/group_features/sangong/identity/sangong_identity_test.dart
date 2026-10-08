import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/pages/group_features/sangong/identity/widgets/sangong_identity_view.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_user_detail_page.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_models.dart';
import '../sangong_test_support.dart';

void main() {
  test('account and real IM avatar are batched and matched by routing ID',
      () async {
    var profileCalls = 0, imCalls = 0;
    final directory = SangongIdentityDirectory(
        session: () => ('owner', 'token', 'endpoint'),
        profiles: (ids) async {
          profileCalls++;
          return [
            for (final id in ids)
              UserFullInfo(
                  userID: id,
                  account: 'acct${id.substring(3)}',
                  faceURL: 'stale-game-avatar')
          ];
        },
        imUsers: (ids) async {
          imCalls++;
          return [
            for (final id in ids.reversed)
              PublicUserInfo(userID: id, faceURL: 'https://im.test/$id.png')
          ];
        });
    final results = await Future.wait([
      for (var i = 0; i < 61; i++) directory.resolve('im_$i'),
      directory.resolve('im_0')
    ]);
    expect(profileCalls, 2);
    expect(imCalls, 2);
    expect(results.first?.account, 'acct0');
    expect(results.first?.faceURL, 'https://im.test/im_0.png');
    expect(results[60]?.faceURL, 'https://im.test/im_60.png');
    await directory.resolve('im_0');
    expect(profileCalls, 2);
    expect(imCalls, 2);
  });

  test('late identity response from old login cannot enter the new login cache',
      () async {
    SangongIdentitySession session = ('owner-A', 'token-A', 'endpoint');
    final pending = Completer<List<UserFullInfo>?>();
    final directory = SangongIdentityDirectory(
        session: () => session,
        profiles: (_) => pending.future,
        imUsers: (_) async => []);
    final request = directory.resolve('im_hidden');
    await Future<void>.delayed(Duration.zero);
    session = ('owner-B', 'token-B', 'endpoint');
    expect(directory.peek('im_hidden'), isNull);
    pending
        .complete([UserFullInfo(userID: 'im_hidden', account: 'oldaccount')]);
    expect(await request, isNull);
    await Future<void>.delayed(Duration.zero);
    expect(directory.peek('im_hidden'), isNull);
  });

  test('mismatched identities and profile avatar cannot replace IM evidence',
      () async {
    final directory = SangongIdentityDirectory(
        session: () => ('owner', 'token', 'endpoint'),
        profiles: (_) async => [
              UserFullInfo(userID: 'other', account: 'wrong'),
              UserFullInfo(
                  userID: 'im_1', account: 'public0001', faceURL: 'not-im')
            ],
        imUsers: (_) async =>
            [PublicUserInfo(userID: 'other', faceURL: 'wrong-avatar')]);
    final result = await directory.resolve('im_1');
    expect(result?.account, 'public0001');
    expect(result?.faceURL, '');
    expect(sangongDisplayName('im_1', 'im_1'), '用户');
  });

  testWidgets('user detail shows public account and never raw IM ID',
      (tester) async {
    const id = 'im_hJT05uAfYjyHQOR_EhV5G0rn0CxCOaLV9i6zkKLkpll';
    final api = SangongTestApi();
    final runtime = sangongTestRuntime(sangongTestContext(api));
    final directory = SangongIdentityDirectory(
        session: () => ('owner', 'token', 'endpoint'),
        profiles: (ids) async => [
              for (final id in ids)
                UserFullInfo(userID: id, account: 'public0001')
            ],
        imUsers: (ids) async => [
              for (final id in ids) PublicUserInfo(userID: id, nickname: '秋666')
            ]);
    await pumpSangongPage(
        tester,
        runtime,
        SangongIdentityScope(
            directory: directory,
            child: const SangongUserDetailPage(
                user: SangongAdminUserReport(
                    userId: 19, imUserId: id, nickname: '秋666'))));
    await flushSangong(tester);
    expect(find.text('账号：public0001'), findsOneWidget);
    expect(find.textContaining(id), findsNothing);
    expect(find.byType(AvatarView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    runtime.dispose();
  });

  testWidgets('failed identity lookup does not reveal routing IDs',
      (tester) async {
    final directory = SangongIdentityDirectory(
        session: () => ('owner', 'token', 'endpoint'),
        profiles: (_) async => throw StateError('unavailable'),
        imUsers: (_) async => throw StateError('unavailable'));
    await tester.pumpWidget(MaterialApp(
        home: SangongIdentityScope(
            directory: directory,
            child: const Column(children: [
              SangongPublicAccount(userID: 'im_secret'),
              SangongUserName(userID: 'im_secret', nickname: 'im_secret')
            ]))));
    await tester.pumpAndSettle();
    expect(find.text('账号：未获取'), findsOneWidget);
    expect(find.text('用户'), findsOneWidget);
    expect(find.textContaining('im_secret'), findsNothing);
  });
}
