import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/favorites/favorite_picker_sheet.dart';
import 'package:openim/pages/mine/secondary/favorite_detail_page.dart';
import 'package:openim/pages/mine/secondary/favorite_note_edit_page.dart';
import 'package:openim/pages/mine/secondary/favorites_page.dart';
import 'package:openim/services/favorite_repository.dart';
import 'package:openim/services/favorite_send_coordinator.dart';

import 'support/favorite_ui_test_support.dart';

void main() {
  testWidgets(
      'management never constructs cached contents or actions before both quota flags arrive',
      (tester) async {
    final repo = FavoriteUiRepository(initialQuota: null);
    addTearDown(repo.dispose);
    final deferred = Completer<FavoriteQuota>();
    repo.probe = (_) => deferred.future;
    await tester.pumpWidget(favoriteUiHost(FavoritesPage(repository: repo)));
    await tester.pump();
    expect(find.byKey(const ValueKey('favorite-note-1')), findsNothing);
    expect(find.byKey(const ValueKey('favorites-add-fab')), findsNothing);
    expect(find.byKey(const ValueKey('favorites-edit')), findsNothing);
    expect(repo.queries, isEmpty);
    deferred.complete(uiQuota);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('favorite-note-1')), findsOneWidget);
    expect(repo.queries.length, 1);
  });

  testWidgets(
      'detail performs no detail or preview request until capability verification succeeds',
      (tester) async {
    final repo = FavoriteUiRepository(initialQuota: null);
    addTearDown(repo.dispose);
    final deferred = Completer<FavoriteQuota>();
    repo.probe = (_) => deferred.future;
    await tester.pumpWidget(favoriteUiHost(FavoriteDetailPage(
        repository: repo,
        item: uiNote,
        onSend: (_) async =>
            const FavoriteSendResult(status: FavoriteSendStatus.success))));
    await tester.pump();
    expect(repo.detailCalls, 0);
    expect(find.byKey(const ValueKey('favorite-detail-send')), findsNothing);
    deferred.complete(uiQuota);
    await tester.pumpAndSettle();
    expect(repo.detailCalls, 1);
    expect(find.text('保留收藏正文'), findsOneWidget);
  });

  testWidgets(
      'each false capability blocks management and quick-send without local fallback',
      (tester) async {
    for (final quota in [
      const FavoriteQuota(supportsFavorites: true, supportsPrepareSend: false),
      const FavoriteQuota(supportsFavorites: false, supportsPrepareSend: true)
    ]) {
      final repo = FavoriteUiRepository(initialQuota: quota);
      addTearDown(repo.dispose);
      var sent = 0;
      await tester.pumpWidget(favoriteUiHost(Scaffold(
          body: FavoritePickerSheet(
              repository: repo,
              target: const FavoriteTarget(
                  conversationID: 'group-chat',
                  groupID: 'g',
                  displayName: '项目群'),
              onSend: (_) async {
                sent++;
                return const FavoriteSendResult(
                    status: FavoriteSendStatus.success);
              }))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('favorite-note-1')), findsNothing);
      expect(find.byKey(const ValueKey('favorite-capability-retry')),
          findsOneWidget);
      expect(repo.queries, isEmpty);
      expect(sent, 0);
      await tester.pumpWidget(favoriteUiHost(FavoritesPage(repository: repo)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('favorites-add-fab')), findsNothing);
      expect(repo.queries, isEmpty);
    }
  });

  testWidgets(
      'real capability error remains visible and explicit retry force-queries quota',
      (tester) async {
    final repo = FavoriteUiRepository(initialQuota: null);
    addTearDown(repo.dispose);
    repo.probe = (_) async {
      if (repo.probeForces.length == 1) {
        throw const FavoriteApiException(20066, '收藏服务暂时无法准备，请重试');
      }
      return uiQuota;
    };
    await tester.pumpWidget(favoriteUiHost(FavoritesPage(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('收藏服务暂时无法准备，请重试'), findsOneWidget);
    expect(repo.queries, isEmpty);
    await tester.tap(find.byKey(const ValueKey('favorite-capability-retry')));
    await tester.pumpAndSettle();
    expect(repo.probeForces, [false, true]);
    expect(find.byKey(const ValueKey('favorites-add-fab')), findsOneWidget);
  });

  testWidgets('unopened and unknown item types expose no send action',
      (tester) async {
    for (final kind in [
      FavoriteKind.location,
      FavoriteKind.contact,
      FavoriteKind.messageBundle,
      FavoriteKind.unknown
    ]) {
      final item = FavoriteItem(
          id: 'unsupported',
          kind: kind,
          title: '只读记录',
          version: 1,
          status: FavoriteStatus.ready);
      final repo = FavoriteUiRepository(initial: [item]);
      addTearDown(repo.dispose);
      var sends = 0;
      await tester.pumpWidget(favoriteUiHost(FavoriteDetailPage(
          key: ValueKey(kind),
          repository: repo,
          item: item,
          onSend: (_) async {
            sends++;
            return const FavoriteSendResult(status: FavoriteSendStatus.success);
          })));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('favorite-detail-send')), findsNothing);
      expect(find.byKey(const ValueKey('favorite-detail-tags')), findsNothing);
      expect(sends, 0);
    }
  });

  testWidgets(
      'an unknown block in an otherwise known note cannot invoke the sender',
      (tester) async {
    const item = FavoriteItem(
        id: 'unknown-block',
        kind: FavoriteKind.note,
        title: '新格式',
        version: 1,
        status: FavoriteStatus.ready,
        content: FavoriteContent(
            kind: FavoriteKind.note,
            blocks: [FavoriteBlock(id: 'future', type: 'future_type')]));
    final repo = FavoriteUiRepository(initial: [item]);
    addTearDown(repo.dispose);
    var sends = 0;
    await tester.pumpWidget(favoriteUiHost(FavoriteDetailPage(
        repository: repo,
        item: item,
        onSend: (_) async {
          sends++;
          return const FavoriteSendResult(status: FavoriteSendStatus.success);
        })));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('favorite-detail-send')));
    expect(button.onPressed, isNull);
    expect(sends, 0);
  });

  testWidgets(
      'capability interruption hides the editor but retains the typed draft through retry',
      (tester) async {
    final repo = FavoriteUiRepository();
    addTearDown(repo.dispose);
    await tester.pumpWidget(favoriteUiHost(Builder(
        builder: (context) => Scaffold(
            body: TextButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => FavoriteNoteEditPage(
                            repository: repo, onSave: (_) async {}))),
                child: const Text('写笔记'))))));
    await tester.tap(find.text('写笔记'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '这段草稿不能丢');
    await tester.pump();
    repo.capabilities = null;
    repo.capabilityFailure = '收藏服务连接已中断';
    repo.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('收藏服务连接已中断'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('favorite-capability-retry')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '这段草稿不能丢');
  });

  testWidgets(
      'multi-delete uses one batch request and retains the updated conflict item',
      (tester) async {
    const second = FavoriteItem(
        id: 'note-2',
        kind: FavoriteKind.note,
        title: '第二条',
        version: 1,
        status: FavoriteStatus.ready);
    const current = FavoriteItem(
        id: 'note-2',
        kind: FavoriteKind.note,
        title: '第二条已更新',
        version: 2,
        status: FavoriteStatus.ready);
    final repo = FavoriteUiRepository(initial: [uiNote, second]);
    addTearDown(repo.dispose);
    repo.deleteResult = const FavoriteBatchDeleteResult(items: [
      FavoriteDeleteResult(id: 'note-1', status: FavoriteDeleteStatus.deleted),
      FavoriteDeleteResult(
          id: 'note-2',
          status: FavoriteDeleteStatus.versionConflict,
          currentItem: current)
    ]);
    await tester.pumpWidget(favoriteUiHost(FavoritesPage(repository: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('favorites-edit')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('favorite-note-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('favorite-note-2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('favorites-delete-selected')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '删除'));
    await tester.pumpAndSettle();
    expect(repo.batchDeletes, 1);
    expect(repo.singleDeletes, 0);
    expect(find.text('删除 (1)'), findsOneWidget);
    expect(find.text('第二条已更新'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'sync and recovery errors stay visible while confirmed favorites remain usable',
      (tester) async {
    final repo = FavoriteUiRepository();
    addTearDown(repo.dispose);
    repo.syncError = '增量同步暂不可用';
    repo.replayError = '编辑发生版本冲突，原正文已保留';
    await tester.pumpWidget(favoriteUiHost(FavoritesPage(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('增量同步暂不可用'), findsOneWidget);
    expect(find.text('编辑发生版本冲突，原正文已保留'), findsOneWidget);
    expect(find.byKey(const ValueKey('favorite-note-1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('favorite-recovery-retry')));
    await tester.pumpAndSettle();
    expect(repo.syncCalls, 1);
    expect(
        find.byKey(const ValueKey('favorite-recovery-banner')), findsNothing);
  });
}
