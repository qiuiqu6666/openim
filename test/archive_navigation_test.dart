import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';

void main() {
  testWidgets('archive navigation survives unread badge updates',
      (tester) async {
    final unread = 1.obs;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PersistentTabView(
          tabs: [
            PersistentTabConfig(
              screen: Scaffold(
                body: ListTile(
                  title: const Text('归档'),
                  onTap: () => Navigator.of(tester.element(find.text('归档')))
                      .push(MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('归档会话')),
                  )),
                ),
              ),
              item: ItemConfig(
                icon: Obx(() => Badge(
                      label: Text('${unread.value}'),
                      child: const Icon(Icons.chat_bubble_outline),
                    )),
                title: '消息',
              ),
            ),
            PersistentTabConfig(
              screen: const Scaffold(body: Text('其他')),
              item: ItemConfig(icon: const Icon(Icons.person), title: '我的'),
            ),
          ],
          navBarBuilder: (config) => Style1BottomNavBar(navBarConfig: config),
        ),
      ),
    ));

    await tester.tap(find.text('归档'));
    await tester.pumpAndSettle();
    expect(find.text('归档会话'), findsOneWidget);

    unread.value = 2;
    await tester.pumpAndSettle();
    expect(find.text('归档会话'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
