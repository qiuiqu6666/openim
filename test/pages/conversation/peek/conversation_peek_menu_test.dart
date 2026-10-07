import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/peek/conversation_peek_actions.dart';
import 'package:openim/pages/conversation/peek/conversation_peek_menu.dart';
import 'package:openim/pages/conversation/peek/conversation_peek_menu_icon.dart';
import 'package:openim_common/openim_common.dart';

ConversationPeekActions _actions(List<String> calls,
        {bool pinned = false,
        bool muted = false,
        bool archived = false,
        bool folders = true,
        bool remove = false,
        bool official = false}) =>
    ConversationPeekActions(
      onOpenChat: () => calls.add('open'),
      isPinned: pinned,
      isMuted: muted,
      isArchived: archived,
      isOfficialAccount: official,
      onArchive: () async {
        calls.add('archive');
      },
      onAddToFolder: folders
          ? () async {
              calls.add('folder');
            }
          : null,
      onRemoveFromFolder: remove
          ? () async {
              calls.add('remove');
            }
          : null,
      onTogglePin: () async {
        calls.add('pin');
      },
      onToggleMute: () async {
        calls.add('mute');
      },
      onDelete: () async {
        calls.add('delete');
      },
    );

Future<void> _pumpMenu(WidgetTester tester, ConversationPeekActions actions,
    {bool dark = false,
    bool enabled = true,
    Locale locale = const Locale('zh', 'CN'),
    required List<ConversationPeekAction> selections}) async {
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
    locale: locale,
    supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Scaffold(
        body: Center(
            child: ConversationPeekMenu(
      actions: actions,
      menuWidth: 180,
      itemVerticalPadding: 10,
      enabled: enabled,
      onSelected: selections.add,
    ))),
  ));
  await tester.pumpAndSettle();
}

List<String> _labels(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
        of: find.byType(ConversationPeekMenu), matching: find.byType(Text)))
    .map((text) => text.data!)
    .toList();

void main() {
  test(
      'optional operations are omitted and callbacks run only when coordinated',
      () async {
    final calls = <String>[];
    final actions =
        ConversationPeekActions(onOpenChat: () => calls.add('open'));
    expect(actions.menuItems, isEmpty);
    expect(actions.itemCount, 0);
    expect(actions.dividerCount, 0);
    expect(actions.callbackFor(ConversationPeekAction.delete), isNull);
    await actions.invoke(ConversationPeekAction.delete);
    expect(calls, isEmpty);
    await actions.invoke(ConversationPeekAction.openChat);
    expect(calls, ['open']);
  });

  test('coordinated operation failures reach the caller for feedback',
      () async {
    final actions = ConversationPeekActions(
      onOpenChat: () {},
      onTogglePin: () async {
        throw StateError('置顶失败');
      },
    );
    await expectLater(
        actions.invoke(ConversationPeekAction.togglePin), throwsStateError);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'menu matches reference geometry, state labels and colors ($dark)',
        (tester) async {
      final calls = <String>[];
      final selections = <ConversationPeekAction>[];
      final actions =
          _actions(calls, pinned: dark, muted: dark, archived: dark);
      await _pumpMenu(tester, actions, dark: dark, selections: selections);
      expect(
          _labels(tester),
          dark
              ? ['取消归档', '添加至分组', '取消置顶', '取消免打扰', '删除']
              : ['归档', '添加至分组', '置顶', '静音', '删除']);
      expect(actions.itemCount, 5);
      expect(actions.dividerCount, 1);
      final card = tester.widget<Container>(
          find.byKey(const ValueKey('conversation-peek-menu')));
      final decoration = card.decoration! as BoxDecoration;
      expect(
          tester
              .getSize(find.byKey(const ValueKey('conversation-peek-menu')))
              .width,
          180);
      expect(decoration.color,
          dark ? AppTokens.backgroundDark : AppTokens.surfaceLight);
      expect(decoration.borderRadius, BorderRadius.circular(16));
      expect(decoration.boxShadow!.single.blurRadius, 20);
      expect(decoration.boxShadow!.single.offset, const Offset(0, 6));
      expect(decoration.boxShadow!.single.color,
          const Color(0xFF000000).withValues(alpha: .14));
      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.height, 1);
      expect(divider.thickness, .5);
      expect(divider.color, const Color(0xFF000000).withValues(alpha: .08));
      final icons = tester.widgetList<ConversationPeekMenuIcon>(
          find.byType(ConversationPeekMenuIcon));
      expect(icons.map((icon) => icon.action), actions.menuItems);
      expect(
          icons
              .singleWhere(
                  (icon) => icon.action == ConversationPeekAction.toggleMute)
              .isMuted,
          dark);
      for (final icon in icons) {
        expect(icon.size, 20);
      }
      final delete = tester.widget<Text>(find.text('删除'));
      expect(delete.style!.fontSize, 15);
      expect(delete.style!.color, const Color(0xFFFF3B30));
      final archiveItem = tester.widget<InkWell>(
          find.byKey(const ValueKey('conversation-peek-action-archive')));
      expect((archiveItem.child! as Padding).padding,
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10));
      expect(
          tester
              .getSize(find
                  .byKey(const ValueKey('conversation-peek-action-archive')))
              .width,
          180);
      await tester
          .tap(find.byKey(const ValueKey('conversation-peek-action-archive')));
      await tester.pump();
      expect(selections, [ConversationPeekAction.archive]);
      expect(calls, isEmpty);
      await actions.invoke(selections.single);
      expect(calls, ['archive']);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'archive scope omits folder actions while preserving source order',
      (tester) async {
    final actions = _actions([], archived: true, folders: false);
    await _pumpMenu(tester, actions, selections: []);
    expect(_labels(tester), ['取消归档', '置顶', '静音', '删除']);
    expect(actions.itemCount, 4);
    expect(actions.dividerCount, 1);
    expect(find.text('标记为未读'), findsNothing);
    expect(find.text('标记为已读'), findsNothing);
  });

  testWidgets('selected folder membership adds remove immediately after add',
      (tester) async {
    final calls = <String>[];
    final selections = <ConversationPeekAction>[];
    final actions = _actions(calls, remove: true);
    await _pumpMenu(tester, actions, selections: selections);
    expect(_labels(tester), ['归档', '添加至分组', '移出分组', '置顶', '静音', '删除']);
    expect(actions.organizationItemCount, 3);
    await tester.tap(find.text('移出分组'));
    await tester.pump();
    expect(selections, [ConversationPeekAction.removeFromFolder]);
    expect(calls, isEmpty);
    await actions.invoke(selections.single);
    expect(calls, ['remove']);
  });

  testWidgets('disabled menu cannot dispatch operations', (tester) async {
    final calls = <String>[];
    final selections = <ConversationPeekAction>[];
    await _pumpMenu(tester, _actions(calls),
        enabled: false, selections: selections);
    await tester.tap(find.text('删除'));
    await tester.pump();
    expect(selections, isEmpty);
    expect(calls, isEmpty);
    expect(
        tester
            .widget<InkWell>(
                find.byKey(const ValueKey('conversation-peek-action-delete')))
            .onTap,
        isNull);
  });

  testWidgets('official account has only the destructive delete action',
      (tester) async {
    final actions = _actions([], official: true);
    await _pumpMenu(tester, actions, selections: []);
    expect(_labels(tester), ['删除']);
    expect(actions.itemCount, 1);
    expect(actions.dividerCount, 0);
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('English labels preserve the same action order', (tester) async {
    await _pumpMenu(
        tester, _actions([], archived: true, pinned: true, muted: true),
        locale: const Locale('en', 'US'), selections: []);
    expect(_labels(tester),
        ['Unarchive', 'Add to folder', 'Unpin', 'Unmute', 'Delete']);
  });
}
