import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/home/home_quick_actions.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  test('popup constraints respect safe width and keyboard', () {
    final constraints = homeQuickMenuConstraints(const MediaQueryData(
      size: Size(220, 400),
      padding: EdgeInsets.fromLTRB(12, 24, 12, 16),
      viewInsets: EdgeInsets.only(bottom: 120),
    ));
    expect(constraints.maxWidth, 172);
    expect(constraints.minWidth, 172);
    expect(constraints.maxHeight, closeTo(140.4, .01));
  });

  for (final dark in [false, true]) {
    testWidgets('quick menu preserves selection and dismissal ($dark)',
        (tester) async {
      final anchor = GlobalKey();
      final selected = <String>[];
      final actions = [
        HomeQuickAction(
          id: 'addFriend',
          title: '添加好友',
          subtitle: '通过账号/手机号搜索好友',
          onTap: () => selected.add('addFriend'),
        ),
        HomeQuickAction(
          id: 'addGroup',
          title: '添加群聊',
          subtitle: '通过群号搜索群聊',
          onTap: () => selected.add('addGroup'),
        ),
        HomeQuickAction(
          id: 'createGroup',
          title: '创建群聊',
          subtitle: '发起多人聊天',
          onTap: () => selected.add('createGroup'),
        ),
      ];
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        home: Builder(builder: (context) {
          return Scaffold(
            appBar: AppBar(actions: [
              IconButton(
                key: anchor,
                icon: const Icon(Icons.add),
                onPressed: () => showHomeQuickActions(
                  context: context,
                  anchor: anchor,
                  actions: actions,
                ),
              ),
            ]),
          );
        }),
      ));
      await tester.tap(find.byKey(anchor));
      await tester.pumpAndSettle();
      expect(find.text('通过账号/手机号搜索好友'), findsOneWidget);
      expect(find.text('发起多人聊天'), findsOneWidget);
      final tile = find.byType(HomeQuickActionTile).first;
      final title = tester
          .widget<Text>(find.descendant(of: tile, matching: find.text('添加好友')));
      expect(title.style?.color,
          dark ? AppTokens.onAccent : HomeQuickActionTokens.titleLight);
      final menuMaterial =
          tester.widgetList<Material>(find.byType(Material)).firstWhere(
                (material) => material.shape is HomeQuickMenuShape,
              );
      expect(menuMaterial.color,
          dark ? HomeQuickActionTokens.menuDark : AppTokens.surfaceLight);
      expect(tester.getSize(find.byType(HomeQuickActionTile).first).width,
          HomeQuickActionTokens.maxWidth - AppTokens.s4 * 2);
      await tester.tap(find.text('添加群聊'));
      await tester.pumpAndSettle();
      expect(selected, ['addGroup']);
      expect(find.byType(HomeQuickActionTile), findsNothing);

      await tester.tap(find.byKey(anchor));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 250));
      await tester.pumpAndSettle();
      expect(selected, ['addGroup']);
      expect(find.byType(HomeQuickActionTile), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
