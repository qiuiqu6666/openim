import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/secondary/favorite_detail_page.dart';
import 'package:openim/services/favorite_repository.dart';
import 'package:openim/services/favorite_send_coordinator.dart';

import '../support/favorite_ui_test_support.dart';

const _longTitle = '周末出行需要保留的完整路线、集合时间和临时安排';
const _source = '周末出行安排与路线确认群聊中的收藏记录';
const _body = '下午三点在门口集合。\n请先确认路线与时间，再出发。\n'
    '如果临时有变化，我们在群里同步。\n这段内容应当可以继续滚动查看，底部操作始终可用。';

FavoriteItem _note({FavoriteStatus status = FavoriteStatus.ready}) =>
    FavoriteItem(
      id: 'layout-note',
      kind: FavoriteKind.note,
      title: _longTitle,
      version: 1,
      status: status,
      source: const FavoriteSource(displayName: _source),
      content: const FavoriteContent(
        kind: FavoriteKind.note,
        blocks: [FavoriteBlock(id: 'body', type: 'text', text: _body)],
      ),
    );

Finder _action(String name) => find.byKey(ValueKey('favorite-detail-$name'));

void _expectUsableAction(WidgetTester tester, Finder action) {
  final rect = tester.getRect(action);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(320));
  expect(rect.top, greaterThanOrEqualTo(24));
  expect(rect.bottom, lessThanOrEqualTo(640 - 24));
  expect(action.hitTestable(), findsOneWidget);
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('detail operations fit 320px and 2x text / $dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);
      for (final status in [FavoriteStatus.ready, FavoriteStatus.failed]) {
        final item = _note(status: status);
        final repo = FavoriteUiRepository(initial: [item]);
        await tester.pumpWidget(favoriteUiHost(
          FavoriteDetailPage(
            key: ValueKey(status),
            repository: repo,
            item: item,
            onSend: (_) async =>
                const FavoriteSendResult(status: FavoriteSendStatus.success),
          ),
          dark: dark,
          textScale: 2,
        ));
        await tester.pumpAndSettle();
        expect(find.text(_longTitle), findsOneWidget);
        expect(find.text(_body), findsOneWidget);
        final secondary =
            _action(status == FavoriteStatus.ready ? 'edit' : 'retry-archive');
        _expectUsableAction(tester, secondary);
        _expectUsableAction(tester, _action('send'));
        expect(
            tester.getRect(secondary).overlaps(tester.getRect(_action('send'))),
            isFalse);
        expect(tester.widget<FilledButton>(_action('send')).onPressed,
            status == FavoriteStatus.ready ? isNotNull : isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        repo.dispose();
      }
    });

    testWidgets('read-only detail keeps content and hides mutations / $dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final item = _note();
      final repo = FavoriteUiRepository(initial: [item]);
      addTearDown(repo.dispose);
      await tester.pumpWidget(favoriteUiHost(
        FavoriteDetailPage(repository: repo, item: item, readOnly: true),
        dark: dark,
        textScale: 2,
      ));
      await tester.pumpAndSettle();
      expect(find.text(_body), findsOneWidget);
      expect(_action('edit'), findsNothing);
      expect(_action('send'), findsNothing);
      expect(_action('retry-archive'), findsNothing);
      expect(find.byTooltip('删除收藏'), findsNothing);
      expect(repo.saves, 0);
      expect(repo.singleDeletes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('stale detail send callbacks share the active submission',
      (tester) async {
    final repo = FavoriteUiRepository();
    addTearDown(repo.dispose);
    final pending = Completer<FavoriteSendResult>();
    var sends = 0;
    await tester.pumpWidget(favoriteUiHost(FavoriteDetailPage(
      repository: repo,
      item: uiNote,
      onSend: (item) {
        sends++;
        expectSync(item.id, uiNote.id);
        return pending.future;
      },
    )));
    await tester.pumpAndSettle();
    expect(sends, 0);
    final send = tester.widget<FilledButton>(_action('send')).onPressed!;
    send();
    send();
    await tester.pump();
    expect(sends, 1);
    expect(tester.widget<FilledButton>(_action('send')).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(_action('edit')).onPressed, isNull);
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '删除收藏'))
            .onPressed,
        isNull);
    pending.complete(const FavoriteSendResult(
        status: FavoriteSendStatus.failed, errorCode: 'CANCELLED'));
    await tester.pumpAndSettle();
    expect(sends, 1);
    expect(tester.widget<FilledButton>(_action('send')).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
