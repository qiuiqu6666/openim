import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/secondary/favorite_detail_page.dart';
import 'package:openim/pages/mine/secondary/favorite_note_edit_page.dart';
import 'package:openim/pages/favorites/widgets/favorite_note_byte_formatter.dart';
import 'package:openim/services/favorite_repository.dart';

import 'support/favorite_ui_test_support.dart';

FavoriteItem _note(int version, String text, {List<FavoriteBlock>? blocks}) =>
    FavoriteItem(
        id: 'conflicting-note',
        kind: FavoriteKind.note,
        title: '笔记版本 $version',
        version: version,
        status: FavoriteStatus.ready,
        content: FavoriteContent(
            kind: FavoriteKind.note,
            blocks:
                blocks ?? [FavoriteBlock(id: 'b1', type: 'text', text: text)]));

class _ConflictRepository extends FavoriteUiRepository {
  _ConflictRepository({this.inlineLatest = true, this.mixed = false})
      : super(initial: [_note(2, '原正文 v2')]);
  final bool inlineLatest, mixed;
  final List<({int? version, String text, String? title})> updates = [];
  final List<int> resolvedThrough = [];
  @override
  Future<FavoriteItem> updateNote(String id, String text,
      {int? expectedVersion, String? title, String? clientRequestID}) async {
    updates.add((version: expectedVersion, text: text, title: title));
    if (updates.length == 1) {
      final latest = _note(3, '服务器正文 v3',
          blocks: mixed
              ? const [
                  FavoriteBlock(id: 'b1', type: 'text', text: '服务器正文 v3'),
                  FavoriteBlock(id: 'b2', type: 'image', assetID: 'image-1'),
                ]
              : null);
      values[0] = latest;
      throw FavoriteApiException(20061, '收藏已被修改，请查看最新版本',
          currentItem: inlineLatest ? latest : null);
    }
    values[0] = _note(4, text);
    return values[0];
  }

  @override
  Future<void> resolveConflictingEdits(String itemID,
      {required int throughVersion}) async {
    resolvedThrough.add(throughVersion);
  }
}

Future<void> _openEditor(WidgetTester tester, _ConflictRepository repo) async {
  await tester.pumpWidget(favoriteUiHost(
      FavoriteDetailPage(repository: repo, item: repo.values[0])));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('favorite-detail-edit')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), '我的修改正文');
  await tester.tap(find.byKey(const ValueKey('favorite-note-save')));
  await tester.pumpAndSettle();
  expect(repo.updates, [(version: 2, text: '我的修改正文', title: '笔记版本 2')]);
  expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('favorite-note-save')))
          .onPressed,
      isNull);
}

void main() {
  for (final inline in [true, false]) {
    testWidgets(
        'conflict review ${inline ? 'uses currentItem' : 'loads latest detail'} and only the next Done saves v3',
        (tester) async {
      final repo = _ConflictRepository(inlineLatest: inline);
      addTearDown(repo.dispose);
      await _openEditor(tester, repo);
      final detailCalls = repo.detailCalls;
      await tester
          .tap(find.byKey(const ValueKey('favorite-note-review-conflict')));
      await tester.pumpAndSettle();
      expect(find.text('服务器正文 v3'), findsOneWidget);
      expect(find.text('我的修改正文'), findsNWidgets(2));
      expect(repo.detailCalls, detailCalls + (inline ? 0 : 1));
      expect(repo.updates.length, 1);
      expect(repo.resolvedThrough, isEmpty);
      await tester.tap(find.byKey(const ValueKey('favorite-conflict-accept')));
      await tester.pumpAndSettle();
      expect(repo.updates.length, 1);
      expect(repo.resolvedThrough, isEmpty);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '我的修改正文');
      await tester.tap(find.byKey(const ValueKey('favorite-note-save')));
      await tester.pumpAndSettle();
      expect(repo.updates.last, (version: 3, text: '我的修改正文', title: '笔记版本 3'));
      expect(repo.resolvedThrough, [2]);
      expect(find.byType(FavoriteNoteEditPage), findsNothing);
      expect(find.text('我的修改正文'), findsOneWidget);
    });
  }

  testWidgets('mixed latest note cannot accept a text-only replacement',
      (tester) async {
    final repo = _ConflictRepository(mixed: true);
    addTearDown(repo.dispose);
    await _openEditor(tester, repo);
    await tester
        .tap(find.byKey(const ValueKey('favorite-note-review-conflict')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('favorite-conflict-accept')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('favorite-conflict-cancel')));
    await tester.pumpAndSettle();
    expect(repo.updates.length, 1);
    expect(repo.resolvedThrough, isEmpty);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '我的修改正文');
  });

  testWidgets(
      'an open review hides both texts and blocks acceptance after account change',
      (tester) async {
    final repo = _ConflictRepository();
    addTearDown(repo.dispose);
    await _openEditor(tester, repo);
    await tester
        .tap(find.byKey(const ValueKey('favorite-note-review-conflict')));
    await tester.pumpAndSettle();
    repo.active = false;
    repo.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('服务器正文 v3'), findsNothing);
    expect(find.text('我的修改正文'), findsNothing);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('favorite-conflict-accept')))
            .onPressed,
        isNull);
    expect(repo.updates.length, 1);
    expect(repo.resolvedThrough, isEmpty);
  });

  testWidgets(
      'cloud notes above 2000 characters remain editable without truncation',
      (tester) async {
    final repo = FavoriteUiRepository();
    addTearDown(repo.dispose);
    final original = '${'中' * 3000}${'👨‍👩‍👧‍👦' * 100}';
    String? saved;
    await tester.pumpWidget(favoriteUiHost(Builder(
        builder: (context) => Scaffold(
            body: TextButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => FavoriteNoteEditPage(
                            repository: repo,
                            initialText: original,
                            onSave: (text) async => saved = text))),
                child: const Text('编辑长笔记'))))));
    await tester.tap(find.text('编辑长笔记'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        original);
    await tester.enterText(find.byType(TextField), '$original追加');
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '$original追加');
    await tester.tap(find.byKey(const ValueKey('favorite-note-save')));
    await tester.pumpAndSettle();
    expect(saved, '$original追加');
    expect(
        FavoriteNoteByteFormatter.byteLength(saved!), lessThanOrEqualTo(65536));
  });

  testWidgets('over-limit composing text stays visible but cannot be submitted',
      (tester) async {
    final repo = FavoriteUiRepository();
    addTearDown(repo.dispose);
    var saves = 0;
    await tester.pumpWidget(favoriteUiHost(
        FavoriteNoteEditPage(repository: repo, onSave: (_) async => saves++)));
    await tester.pumpAndSettle();
    final value = '中' * 21846;
    tester.testTextInput.updateEditingValue(TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
        composing: TextRange(start: 21845, end: 21846)));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        value);
    expect(
        tester
            .widget<TextButton>(
                find.byKey(const ValueKey('favorite-note-save')))
            .onPressed,
        isNull);
    expect(saves, 0);
    expect(find.text('65538 / 65536 字节'), findsOneWidget);
  });
}
