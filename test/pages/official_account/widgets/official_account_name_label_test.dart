import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/official_account/models/official_account.dart';
import 'package:openim/pages/official_account/widgets/official_account_name_label.dart';

Finder get _badge => find.byWidgetPredicate((widget) =>
    widget is Image &&
    widget.image is AssetImage &&
    (widget.image as AssetImage)
        .assetName
        .endsWith('official_account_verified.png'));

Future<void> _mount(WidgetTester tester, OfficialAccountNameLabel label,
        {Brightness brightness = Brightness.light,
        double width = 160,
        double textScale = 1}) =>
    tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Center(child: SizedBox(width: width, child: label)),
        ),
      ),
    ));

void main() {
  testWidgets(
      'stable official identity stays verified and preserves the remark',
      (tester) async {
    for (final id in ['assistant', '99Message', '99Pay']) {
      for (final ex in [null, '{broken']) {
        await _mount(tester,
            OfficialAccountNameLabel(name: '我的官方账号', userID: id, ex: ex));
        expect(_badge, findsOneWidget);
        expect(find.text('我的官方账号'), findsOneWidget);
      }
    }
    await _mount(
        tester,
        const OfficialAccountNameLabel(
            name: '公告',
            userID: 'notice-alias',
            ex: '{"accountType":"official","officialRole":"message"}'));
    expect(_badge, findsOneWidget);
  });

  testWidgets('ordinary lookalike names and group metadata cannot earn a badge',
      (tester) async {
    for (final label in [
      const OfficialAccountNameLabel(name: '99Message', userID: 'ordinary'),
      const OfficialAccountNameLabel(name: 'AI助理', userID: 'ordinary'),
      const OfficialAccountNameLabel(
          name: '99Pay',
          userID: 'ordinary',
          ex: '{"accountType":"user","officialRole":"pay"}'),
      const OfficialAccountNameLabel(
          name: '99Pay',
          userID: '99Pay',
          isSingleChat: false,
          ex: '{"accountType":"official"}'),
      const OfficialAccountNameLabel(
          name: 'AI助理', userID: 'assistant', isSingleChat: false),
    ]) {
      await _mount(tester, label);
      expect(_badge, findsNothing);
      expect(find.text(label.name), findsOneWidget);
    }
  });

  testWidgets('resolved identity cannot cross into a different user',
      (tester) async {
    const account = OfficialAccount(
        userID: 'notice-alias', role: OfficialAccountRole.message);
    await _mount(
        tester,
        const OfficialAccountNameLabel(
            name: '公告', userID: 'notice-alias', account: account));
    expect(_badge, findsOneWidget);
    await _mount(
        tester,
        const OfficialAccountNameLabel(
            name: '公告', userID: 'different-user', account: account));
    expect(_badge, findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('long large-text names retain their badge ${brightness.name}',
        (tester) async {
      await _mount(
          tester,
          const OfficialAccountNameLabel(
              name: '这是一个很长的官方账号备注名称',
              userID: '99Message',
              style: TextStyle(fontSize: 16)),
          brightness: brightness,
          width: 100,
          textScale: 2);
      final label = tester.getRect(find.byType(OfficialAccountNameLabel));
      final badge = tester.getRect(_badge);
      expect(label.contains(badge.center), isTrue);
      expect(badge.right, lessThanOrEqualTo(label.right));
      expect(tester.takeException(), isNull);
    });
  }
}
