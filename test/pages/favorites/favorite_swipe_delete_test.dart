import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/secondary/favorites_page.dart';
import 'package:openim/routes/swipe_back/app_page_route.dart';
import 'package:openim/services/favorite_repository.dart';

import 'support/favorite_ui_test_support.dart';

const _other = FavoriteItem(
    id: 'note-2',
    kind: FavoriteKind.note,
    title: '第二条收藏',
    version: 2,
    status: FavoriteStatus.ready);

class _Repository extends FavoriteUiRepository {
  _Repository() : super(initial: [uiNote, _other]);
  final deleted = <(String, int?)>[];
  bool fail = false;
  Completer<void>? pending;

  @override
  Future<void> delete(String id,
      {int? expectedVersion, String? clientRequestID}) async {
    deleted.add((id, expectedVersion));
    if (pending != null) await pending!.future;
    if (fail) throw const FavoriteApiException(20065, '删除失败，请重试');
    values.removeWhere((item) => item.id == id);
    notifyListeners();
  }
}

Finder _row([String id = 'note-1']) => find.byKey(ValueKey('favorite-$id'));
Finder _action([String id = 'note-1']) =>
    find.byKey(ValueKey('favorite-swipe-delete-$id'));

Future<void> _swipe(WidgetTester tester, [String id = 'note-1']) async {
  await tester.drag(_row(id), const Offset(220, 0));
  await tester.pumpAndSettle();
}

Future<void> _requestDelete(WidgetTester tester) async {
  await _swipe(tester);
  await tester.tap(_action());
  await tester.pumpAndSettle();
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('right swipe confirms or cancels the selected record ($dark)',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = _Repository();
      addTearDown(repo.dispose);
      await tester.pumpWidget(
          favoriteUiHost(FavoritesPage(repository: repo), dark: dark));
      await tester.pumpAndSettle();
      await _swipe(tester);
      expect(_action().hitTestable(), findsOneWidget);
      expect(repo.deleted, isEmpty);
      expect(tester.getRect(_action()).center.dx,
          lessThan(tester.getRect(_row()).left));
      await tester.tap(_action());
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(CupertinoDialogAction, '取消'));
      await tester.pumpAndSettle();
      expect(repo.deleted, isEmpty);
      expect(_row(), findsOneWidget);
      expect(_action().hitTestable(), findsNothing);
      await _requestDelete(tester);
      await tester.tap(find.widgetWithText(CupertinoDialogAction, '删除'));
      await tester.pumpAndSettle();
      expect(repo.deleted, [('note-1', 1)]);
      expect(_row(), findsNothing);
      expect(_row('note-2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed deletion retains the record and existing retry selection',
      (tester) async {
    final repo = _Repository()..fail = true;
    addTearDown(repo.dispose);
    await tester.pumpWidget(favoriteUiHost(FavoritesPage(repository: repo)));
    await tester.pumpAndSettle();
    await _requestDelete(tester);
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '删除'));
    await tester.pumpAndSettle();
    expect(_row(), findsOneWidget);
    expect(find.text('删除 (1)'), findsOneWidget);
    expect(repo.deleted, [('note-1', 1)]);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await _swipe(tester);
    expect(_action().hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing closes an open action and allows normal multi-selection',
      (tester) async {
    final repo = _Repository();
    addTearDown(repo.dispose);
    await tester.pumpWidget(favoriteUiHost(FavoritesPage(repository: repo)));
    await tester.pumpAndSettle();
    await _swipe(tester);
    await tester.tap(find.byKey(const ValueKey('favorites-edit')));
    await tester.pumpAndSettle();
    expect(_action().hitTestable(), findsNothing);
    await _swipe(tester);
    expect(_action().hitTestable(), findsNothing);
    await tester.tap(_row());
    await tester.pumpAndSettle();
    expect(find.text('删除 (1)'), findsOneWidget);
    expect(repo.deleted, isEmpty);
  });

  testWidgets('opening another row closes the first without deleting either',
      (tester) async {
    final repo = _Repository();
    addTearDown(repo.dispose);
    await tester.pumpWidget(favoriteUiHost(FavoritesPage(repository: repo)));
    await tester.pumpAndSettle();
    await _swipe(tester);
    await _swipe(tester, 'note-2');
    expect(_action().hitTestable(), findsNothing);
    expect(_action('note-2').hitTestable(), findsOneWidget);
    expect(repo.deleted, isEmpty);
  });

  testWidgets('pending delete cannot start another request or swipe',
      (tester) async {
    final completion = Completer<void>();
    final repo = _Repository()..pending = completion;
    addTearDown(repo.dispose);
    try {
      await tester.pumpWidget(favoriteUiHost(FavoritesPage(repository: repo)));
      await tester.pumpAndSettle();
      await _requestDelete(tester);
      await tester.tap(find.widgetWithText(CupertinoDialogAction, '删除'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // Disabled rows intentionally do not participate in gesture hit testing.
      await tester.drag(_row('note-2'), const Offset(220, 0),
          warnIfMissed: false);
      await tester.pump();
      expect(_action('note-2').hitTestable(), findsNothing);
      expect(repo.deleted, [('note-1', 1)]);
      completion.complete();
      await tester.pumpAndSettle();
      expect(_row(), findsNothing);
    } finally {
      if (!completion.isCompleted) completion.complete();
    }
  });

  testWidgets('chat picker has no destructive swipe action', (tester) async {
    final repo = _Repository();
    addTearDown(repo.dispose);
    await tester.pumpWidget(favoriteUiHost(Scaffold(
        body: FavoriteCollectionView(
            repository: repo, pickerStyle: true, onTap: (_) {}))));
    await tester.pumpAndSettle();
    await _swipe(tester);
    expect(find.byType(Slidable), findsNothing);
    expect(repo.deleted, isEmpty);
  });

  testWidgets('row right swipe and page edge back remain separate',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repository();
    addTearDown(repo.dispose);
    await tester.pumpWidget(favoriteUiHost(Builder(
        builder: (context) => Scaffold(
            body: TextButton(
                onPressed: () => Navigator.of(context).push(
                    AppMaterialPageRoute(
                        builder: (_) => FavoritesPage(repository: repo))),
                child: const Text('打开收藏'))))));
    await tester.tap(find.text('打开收藏'));
    await tester.pumpAndSettle();
    await _swipe(tester);
    expect(_action().hitTestable(), findsOneWidget);
    expect(find.byType(FavoritesPage), findsOneWidget);
    await tester.dragFrom(
        Offset(2, tester.getCenter(_row()).dy), const Offset(330, 0));
    await tester.pumpAndSettle();
    expect(find.byType(FavoritesPage), findsNothing);
    expect(repo.deleted, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
