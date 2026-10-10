import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/mark_six/data/mark_six_controller.dart';
import 'package:openim/pages/group_features/mark_six/data/mark_six_repository.dart';
import 'package:openim/pages/group_features/mark_six/widgets/mark_six_latest_card.dart';
import 'package:openim/pages/group_features/mark_six/widgets/mark_six_style.dart';

import '../mark_six_fixtures.dart';

Future<void> _mount(WidgetTester tester, Widget child,
        {Size size = const Size(396.5, 165.8),
        Brightness brightness = Brightness.light,
        double textScale = 1}) =>
    tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: Center(
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: SizedBox.fromSize(size: size, child: child),
          ),
        ),
      ),
    ));

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('preview error fits the reported transition size / $brightness',
        (tester) async {
      final controller =
          MarkSixController(MarkSixRepository(markSixContext(MarkSixFakeApi())))
            ..error = '返回数据格式无效，请重试';
      addTearDown(controller.dispose);
      await _mount(
          tester, MarkSixLatestCard(controller: controller, preview: true),
          brightness: brightness);
      expect(tester.takeException(), isNull);
      final retry = find.widgetWithText(FilledButton, '重试');
      expect(retry.hitTestable(), findsOneWidget);
      final bounds = tester.getRect(find.byType(MarkSixLatestCard));
      expect(bounds.contains(tester.getRect(retry).bottomRight), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final compact in [false, true]) {
    testWidgets('large text can scroll to retry in a short area / $compact',
        (tester) async {
      var retries = 0;
      const message = '开奖数据暂时无法获取，请检查网络连接后重试。';
      await _mount(
          tester,
          MarkSixEmpty(
              message: message, compact: compact, onRetry: () => retries++),
          size: const Size(260, 118),
          textScale: 2);
      expect(tester.takeException(), isNull);
      expect(find.text(message), findsOneWidget);
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重试'));
      expect(retries, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty message also fits bounded and unbounded layouts',
      (tester) async {
    const empty = MarkSixEmpty(message: '暂无开奖数据');
    await _mount(tester, empty, size: const Size(260, 56), textScale: 2);
    expect(tester.takeException(), isNull);
    await _mount(tester, const SingleChildScrollView(child: empty));
    expect(find.text('暂无开奖数据'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
