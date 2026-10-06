import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/editing/conversation_edit_action_bar.dart';
import 'package:openim/pages/conversation/editing/conversation_edit_tokens.dart';
import 'package:openim/pages/conversation/editing/conversation_selection_indicator.dart';
import 'package:openim_common/openim_common.dart';

Widget _host({required bool dark, required Widget child}) => MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN')],
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: Scaffold(body: Column(children: [child])),
    );

void main() {
  for (final dark in [false, true]) {
    testWidgets('edit actions follow selection and busy state ($dark)',
        (tester) async {
      final actions = <String>[];
      Future<void> pumpBar({required bool selected, bool busy = false}) =>
          tester.pumpWidget(_host(
            dark: dark,
            child: ConversationEditActionBar(
              hasSelection: selected,
              busy: busy,
              onMarkRead: () => actions.add('read'),
              onArchive: () => actions.add('archive'),
              onDelete: () => actions.add('delete'),
            ),
          ));

      await pumpBar(selected: false);
      expect(find.text('全部已读'), findsOneWidget);
      final barFinder = find.byType(ConversationEditActionBar);
      expect(tester.getSize(barFinder).height, 56);
      final material = tester.widget<Material>(find
          .descendant(of: barFinder, matching: find.byType(Material))
          .first);
      expect(material.color,
          dark ? AppTokens.backgroundDark : AppTokens.surfaceLight);
      final decorated = tester.widget<DecoratedBox>(find
          .descendant(of: barFinder, matching: find.byType(DecoratedBox))
          .first);
      final border = (decorated.decoration as BoxDecoration).border! as Border;
      expect(border.top.width, .6);
      expect(border.top.color, ConversationEditTokens.divider(dark: dark));
      final readButton = tester.widget<TextButton>(
          find.byKey(const ValueKey('conversation-edit-mark-read')));
      final archiveButton = tester.widget<TextButton>(
          find.byKey(const ValueKey('conversation-edit-archive')));
      final deleteButton = tester.widget<TextButton>(
          find.byKey(const ValueKey('conversation-edit-delete')));
      expect(readButton.onPressed, isNotNull);
      expect(archiveButton.onPressed, isNull);
      expect(deleteButton.onPressed, isNull);
      expect(tester.widget<Text>(find.text('删除')).style!.color,
          ConversationEditTokens.delete);
      await tester.tap(find.text('全部已读'));
      expect(actions, ['read']);

      await pumpBar(selected: true);
      expect(find.text('标记已读'), findsOneWidget);
      final enabledDelete = tester.widget<TextButton>(
          find.byKey(const ValueKey('conversation-edit-delete')));
      expect(enabledDelete.style!.foregroundColor!.resolve({}),
          ConversationEditTokens.delete);
      final widths = ['mark-read', 'archive', 'delete']
          .map((name) => tester
              .getSize(find.byKey(ValueKey('conversation-edit-$name')))
              .width)
          .toList();
      expect(widths[0], widths[1]);
      expect(widths[1], widths[2]);
      await tester.tap(find.text('归档'));
      await tester.tap(find.text('删除'));
      expect(actions, ['read', 'archive', 'delete']);

      await pumpBar(selected: true, busy: true);
      for (final button
          in tester.widgetList<TextButton>(find.byType(TextButton))) {
        expect(button.onPressed, isNull);
      }
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('selection indicator follows both themes ($dark)',
        (tester) async {
      for (final selected in [false, true]) {
        await tester.pumpWidget(_host(
          dark: dark,
          child: ConversationSelectionIndicator(selected: selected),
        ));
        final indicator = find.byType(ConversationSelectionIndicator);
        expect(tester.getSize(indicator), const Size(24, 24));
        final container = tester.widget<Container>(
            find.descendant(of: indicator, matching: find.byType(Container)));
        final decoration = container.decoration! as BoxDecoration;
        final border = decoration.border! as Border;
        expect(decoration.shape, BoxShape.circle);
        expect(border.top.width, 1.8);
        expect(border.top.color,
            selected ? AppTokens.accent : AppTokens.textSecondary(dark: dark));
        expect(decoration.color, selected ? AppTokens.accent : null);
        if (selected) {
          final icon = tester.widget<Icon>(find.byIcon(Icons.check));
          expect(icon.size, 16);
          expect(icon.color, AppTokens.onAccent);
        } else {
          expect(find.byIcon(Icons.check), findsNothing);
        }
        expect(tester.takeException(), isNull);
      }
    });
  }
}
