import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/moments/interactions/moments_comment_editor.dart';
import 'package:openim/services/moments_repository.dart';

import '../support/moments_ui_fixture.dart';
import '../support/moments_ui_host.dart';

class _Api extends MomentsUiApi {
  _Api() : super(posts: momentsUiPosts());
  Completer<void>? commentGate;
  Completer<MomentsWriteResult>? resultGate;
  bool timeout = false;
  int attempts = 0;
  int queries = 0;
  bool commentStarted = false;

  @override
  Future<MomentComment> createComment(String momentId,
      {required String text,
      required String clientRequestId,
      String? replyToCommentId}) async {
    commentStarted = true;
    ++attempts;
    await commentGate?.future;
    if (timeout) {
      throw const MomentsException('timeout', unknownResult: true);
    }
    return super.createComment(momentId,
        text: text,
        clientRequestId: clientRequestId,
        replyToCommentId: replyToCommentId);
  }

  @override
  Future<void> deletePost(String momentId) async => posts.remove(momentId);

  @override
  Future<MomentsWriteResult> queryCommentResult(String clientRequestId) async {
    ++queries;
    return resultGate!.future;
  }
}

Future<void> _mount(WidgetTester tester, MomentsRepository repository,
    {MomentComment? replyTo, bool dark = false, VoidCallback? onClosed}) async {
  final post = await repository.loadDetail(momentsUiFriendPostId);
  await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => MaterialApp(
          theme: momentsUiTheme(dark),
          locale: const Locale('en'),
          supportedLocales: const [Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () async {
                        await showMomentsCommentSheet(context, repository, post,
                            replyTo: replyTo);
                        onClosed?.call();
                      },
                      child: const Text('Open editor')))))));
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final dark in [false, true]) {
    testWidgets(
        'deleted parent clears the open draft without scope change ($dark)',
        (tester) async {
      final api = _Api();
      final repository = MomentsRepository(
          api: api,
          userIdProvider: () => momentsUiSelf.userId,
          friendLoader: () async => [momentsUiFriend, momentsUiSecondFriend],
          subscribeToSdk: false);
      addTearDown(repository.dispose);
      await _mount(tester, repository,
          dark: dark, replyTo: api.commentItems[momentsUiFriendPostId]!.first);
      await tester.enterText(find.byType(TextField), 'Private draft');
      final scope = repository.authorizationScope;
      await repository.deletePost(momentsUiFriendPostId);
      await tester.pumpAndSettle();
      expect(repository.authorizationScope, scope);
      expect(find.text('Comment unavailable'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('Private draft'), findsNothing);
      expect(find.textContaining('Reply to'), findsNothing);
      expect(api.commentWrites, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      repository.dispose();
    });

    testWidgets(
        'friend removal hides reply identity and blocks sending ($dark)',
        (tester) async {
      final api = _Api();
      var friends = [momentsUiFriend, momentsUiSecondFriend];
      final repository = MomentsRepository(
          api: api,
          userIdProvider: () => momentsUiSelf.userId,
          friendLoader: () async => friends,
          subscribeToSdk: false);
      addTearDown(repository.dispose);
      await _mount(tester, repository,
          dark: dark, replyTo: api.commentItems[momentsUiFriendPostId]!.first);
      await tester.enterText(find.byType(TextField), 'Unsaved reply');
      friends = [momentsUiFriend];
      await repository.loadFriends(force: true);
      await tester.pumpAndSettle();
      expect(find.text('Comment unavailable'), findsOneWidget);
      expect(
          find.textContaining(momentsUiSecondFriend.displayName), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(api.commentWrites, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'confirmed comment closes its sheet while preserving a covering route',
      (tester) async {
    final api = _Api()..commentGate = Completer<void>();
    final repository = MomentsRepository(
        api: api,
        userIdProvider: () => momentsUiSelf.userId,
        friendLoader: () async => [momentsUiFriend, momentsUiSecondFriend],
        subscribeToSdk: false);
    addTearDown(repository.dispose);
    var closed = false;
    await _mount(tester, repository, onClosed: () => closed = true);
    await tester.enterText(find.byType(TextField), 'Confirmed comment');
    await tester.pump();
    await tester.tap(find.text('Send'));
    for (var i = 0; i < 10 && !api.commentStarted; i++) {
      await tester.pump();
    }
    expect(api.commentStarted, isTrue);
    final navigator = Navigator.of(tester.element(find.byType(TextField)));
    unawaited(navigator.push<void>(MaterialPageRoute(
        builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Other page')),
            body: const SizedBox()))));
    await tester.pump(const Duration(milliseconds: 400));
    api.commentGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Other page'), findsOneWidget);
    expect(closed, isTrue);
    expect(api.commentWrites.single['text'], 'Confirmed comment');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Open editor'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final removeFriend in [false, true]) {
    testWidgets(
        'late NOT_FOUND cannot resend a revoked comment ($removeFriend)',
        (tester) async {
      final api = _Api()..timeout = true;
      var friends = [momentsUiFriend, momentsUiSecondFriend];
      final repository = MomentsRepository(
          api: api,
          userIdProvider: () => momentsUiSelf.userId,
          friendLoader: () async => friends,
          subscribeToSdk: false);
      addTearDown(repository.dispose);
      await _mount(tester, repository,
          replyTo: api.commentItems[momentsUiFriendPostId]!.first);
      await tester.enterText(find.byType(TextField), 'Unconfirmed reply');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm and retry'), findsOneWidget);
      api.resultGate = Completer<MomentsWriteResult>();
      await tester.tap(find.text('Confirm and retry'));
      await tester.pump();
      expect(api.queries, 1);
      if (removeFriend) {
        friends = [momentsUiFriend];
        await repository.loadFriends(force: true);
      } else {
        await repository.deletePost(momentsUiFriendPostId);
      }
      await tester.pump();
      api.timeout = false;
      api.resultGate!.complete(const MomentsWriteResult(status: 'NOT_FOUND'));
      await tester.pumpAndSettle();
      expect(api.attempts, 1);
      expect(find.text('Comment unavailable'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(api.commentWrites, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      repository.dispose();
    });
  }

  testWidgets('overlong Unicode comments show an inline reason and cannot send',
      (tester) async {
    final api = _Api();
    final repository = MomentsRepository(
        api: api,
        userIdProvider: () => momentsUiSelf.userId,
        friendLoader: () async => [momentsUiFriend, momentsUiSecondFriend],
        subscribeToSdk: false);
    addTearDown(repository.dispose);
    await _mount(tester, repository);
    await tester.enterText(
        find.byType(TextField), List.filled(501, '🌱').join());
    await tester.pumpAndSettle();
    expect(find.text('Use at most 500 characters'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(api.commentWrites, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
