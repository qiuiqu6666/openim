import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/secondary/favorite_detail_page.dart';
import 'package:openim/pages/mine/secondary/favorites_page.dart';
import 'package:openim/services/favorite_repository.dart';

import 'support/favorite_ui_test_support.dart';

const _latest = FavoriteItem(
    id: 'note-1',
    kind: FavoriteKind.note,
    title: '服务器最新正文',
    version: 3,
    status: FavoriteStatus.ready,
    content: FavoriteContent(
        kind: FavoriteKind.note,
        blocks: [FavoriteBlock(id: 'b1', type: 'text', text: '最新内容')]));

class _DeletingRepository extends FavoriteUiRepository {
  _DeletingRepository({this.inlineLatest = true});
  final bool inlineLatest;
  bool detailUnavailable = false;
  final List<int?> versions = [];
  @override
  Future<void> delete(String id,
      {int? expectedVersion, String? clientRequestID}) async {
    versions.add(expectedVersion);
    if (versions.length == 1) {
      values[0] = _latest;
      notifyListeners();
      throw FavoriteApiException(20061, '收藏已更新，请确认最新内容',
          currentItem: inlineLatest ? _latest : null);
    }
    throw const FavoriteApiException(20065, '删除服务暂不可用');
  }

  @override
  Future<FavoriteItem> getDetail(String id) async {
    if (versions.isNotEmpty && detailUnavailable) {
      throw const FavoriteApiException(20065, '最新详情暂不可用');
    }
    return super.getDetail(id);
  }
}

const _second = FavoriteItem(
    id: 'note-2',
    kind: FavoriteKind.note,
    title: '第二条',
    version: 1,
    status: FavoriteStatus.ready);

class _BatchConflictRepository extends FavoriteUiRepository {
  _BatchConflictRepository() : super(initial: [uiNote, _second]);
  bool detailUnavailable = true;
  final List<int?> deletedVersions = [];
  int batches = 0;
  @override
  Future<FavoriteBatchDeleteResult> deleteMany(List<FavoriteItem> items,
      {String? clientRequestID}) async {
    batches++;
    values
      ..clear()
      ..add(_latest);
    notifyListeners();
    // Production supplies version only; simulate a failed repository hydrate.
    return const FavoriteBatchDeleteResult(items: [
      FavoriteDeleteResult(
          id: 'note-1', status: FavoriteDeleteStatus.versionConflict),
      FavoriteDeleteResult(id: 'note-2', status: FavoriteDeleteStatus.deleted),
    ]);
  }

  @override
  Future<FavoriteItem> getDetail(String id) async {
    if (detailUnavailable) {
      throw const FavoriteApiException(20065, '最新详情暂不可用');
    }
    return super.getDetail(id);
  }

  @override
  Future<void> delete(String id,
      {int? expectedVersion, String? clientRequestID}) async {
    deletedVersions.add(expectedVersion);
    throw const FavoriteApiException(20065, '删除服务暂不可用');
  }
}

const _image = FavoriteItem(
    id: 'photo',
    kind: FavoriteKind.image,
    title: '照片',
    version: 1,
    status: FavoriteStatus.ready,
    content: FavoriteContent(
        kind: FavoriteKind.image,
        blocks: [FavoriteBlock(id: 'b1', type: 'image', assetID: 'original')]),
    assets: [
      FavoriteAsset(
          id: 'original',
          role: 'original',
          mimeType: 'image/png',
          sizeBytes: 8,
          sha256:
              '0000000000000000000000000000000000000000000000000000000000000000')
    ]);

class _PreviewRepository extends FavoriteUiRepository {
  _PreviewRepository() : super(initial: [_image]);
  int accesses = 0;
  Completer<FavoriteDownload>? retry;
  @override
  Future<FavoriteDownload> assetAccess(String id, String assetID) async {
    accesses++;
    if (retry != null) return retry!.future;
    throw const FavoriteApiException(20066, '原件暂未就绪，请稍后重试');
  }
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(CupertinoDialogAction, '删除'));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

void main() {
  for (final detail in [false, true]) {
    testWidgets(
        '${detail ? 'detail' : 'management'} no-hint delete conflict blocks stale retries until detail is readable',
        (tester) async {
      final repo = _DeletingRepository(inlineLatest: false)
        ..detailUnavailable = true;
      addTearDown(repo.dispose);
      await tester.pumpWidget(favoriteUiHost(detail
          ? FavoriteDetailPage(repository: repo, item: uiNote)
          : FavoritesPage(repository: repo)));
      await tester.pumpAndSettle();
      if (!detail) {
        await tester.tap(find.byKey(const ValueKey('favorites-edit')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('favorite-note-1')));
        await tester.pump();
      }
      final remove = detail
          ? find.byTooltip('删除收藏')
          : find.byKey(const ValueKey('favorites-delete-selected'));
      await tester.tap(remove);
      await _confirm(tester);
      expect(repo.versions, [1]);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(repo.versions, [1]);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      repo.detailUnavailable = false;
      await tester.tap(remove);
      await _confirm(tester);
      expect(repo.versions, [1, 3]);
    });
  }

  testWidgets(
      'version-only batch conflict keeps selection and reads latest before another confirmed delete',
      (tester) async {
    final repo = _BatchConflictRepository();
    addTearDown(repo.dispose);
    await tester.pumpWidget(favoriteUiHost(FavoritesPage(repository: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('favorites-edit')));
    await tester.pump();
    for (final id in ['note-1', 'note-2']) {
      await tester.tap(find.byKey(ValueKey('favorite-$id')));
      await tester.pump();
    }
    final remove = find.byKey(const ValueKey('favorites-delete-selected'));
    await tester.tap(remove);
    await _confirm(tester);
    expect(repo.batches, 1);
    expect(find.text('删除 (1)'), findsOneWidget);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    expect(repo.deletedVersions, isEmpty);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    repo.detailUnavailable = false;
    await tester.tap(remove);
    await _confirm(tester);
    expect(repo.deletedVersions, [3]);
  });
  testWidgets(
      'preview reports the API error and rapid retries share one request',
      (tester) async {
    final repo = _PreviewRepository();
    addTearDown(repo.dispose);
    await tester.pumpWidget(favoriteUiHost(
        FavoriteDetailPage(repository: repo, item: _image, readOnly: true)));
    await tester.pumpAndSettle();
    expect(find.text('原件暂未就绪，请稍后重试'), findsOneWidget);
    expect(repo.accesses, 1);
    repo.retry = Completer<FavoriteDownload>();
    final button = tester.widget<TextButton>(
        find.byKey(const ValueKey('favorite-preview-retry-original')));
    button.onPressed!();
    button.onPressed!();
    await tester.pump();
    expect(repo.accesses, 2);
    repo.retry!.completeError(const FavoriteApiException(20066, '原件仍待处理'));
    await tester.pumpAndSettle();
    expect(find.text('原件仍待处理'), findsOneWidget);
  });
  testWidgets('rapid add callbacks open only one creation menu',
      (tester) async {
    final repo = FavoriteUiRepository();
    addTearDown(repo.dispose);
    await tester.pumpWidget(favoriteUiHost(FavoritesPage(repository: repo)));
    await tester.pumpAndSettle();
    final button = tester.widget<FloatingActionButton>(
        find.byKey(const ValueKey('favorites-add-fab')));
    button.onPressed!();
    button.onPressed!();
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
  });

  testWidgets(
      'single management delete conflict keeps the latest selected version',
      (tester) async {
    final repo = _DeletingRepository();
    addTearDown(repo.dispose);
    await tester.pumpWidget(favoriteUiHost(FavoritesPage(repository: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('favorites-edit')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('favorite-note-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('favorites-delete-selected')));
    await _confirm(tester);
    expect(repo.versions, [1]);
    expect(find.text('服务器最新正文'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('favorites-delete-selected')));
    await _confirm(tester);
    expect(repo.versions, [1, 3]);
  });

  testWidgets(
      'detail delete conflict requires a new confirmation with the latest version',
      (tester) async {
    final repo = _DeletingRepository();
    addTearDown(repo.dispose);
    await tester.pumpWidget(
        favoriteUiHost(FavoriteDetailPage(repository: repo, item: uiNote)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除收藏'));
    await _confirm(tester);
    expect(repo.versions, [1]);
    expect(find.text('最新内容'), findsOneWidget);
    await tester.tap(find.byTooltip('删除收藏'));
    await _confirm(tester);
    expect(repo.versions, [1, 3]);
  });
}
