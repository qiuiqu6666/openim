import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/pages/group_features/mark_six/widgets/mark_six_prediction_copy.dart';

void main() {
  setUp(configureEasyLoadingInteractions);
  tearDown(() async {
    await EasyLoading.dismiss(animation: false);
  });
  final cases = <String, (List<String>, String)>{
    'special': (['04', '19', '32'], '04.19.32'),
    'zodiac': (['猪', '狗', '羊'], '猪.狗.羊'),
    'fiveElement': (['水', '火', '土'], '水.火.土'),
    'head': (['4', '2', '3'], '4头2头3头'),
    'tail': (['6', '8', '0'], '6尾8尾0尾'),
    'parity': (['双'], '双'),
    'size': (['小'], '小'),
    'sumParity': (['单'], '单'),
    'wave': (['红', '蓝'], '红 蓝'),
    'zuhe': (['小单', '小双'], '小单 小双'),
  };
  for (final dark in [false, true]) {
    for (final entry in cases.entries) {
      testWidgets('${entry.key} tap copies betting format dark=$dark',
          (tester) async {
        String? copied;
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null));
        await tester.pumpWidget(MaterialApp(
            builder: EasyLoading.init(),
            theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light),
            home: Scaffold(
                body: MarkSixPredictionCopy(
                    attribute: entry.key,
                    label: '测试',
                    values: entry.value.$1,
                    child: Text(entry.value.$1.join(' '))))));
        final target = find.byType(InkWell);
        expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(copied, entry.value.$2);
        expect(find.text('测试预测已复制'), findsOneWidget);
        expect(EasyLoading.isShow, isTrue);
        expect(find.byType(SnackBar), findsNothing);
        await EasyLoading.dismiss(animation: false);
        await tester.pumpAndSettle();
      });
    }
  }
  testWidgets('empty values do not copy', (tester) async {
    await tester.pumpWidget(MaterialApp(
        builder: EasyLoading.init(),
        home: Scaffold(
            body: MarkSixPredictionCopy(
                attribute: 'special',
                label: '特码',
                values: [],
                child: Text('—')))));
    expect(find.byType(InkWell), findsNothing);
  });
  testWidgets('clipboard failure shows retry feedback', (tester) async {
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        throw PlatformException(code: 'unavailable');
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(MaterialApp(
        builder: EasyLoading.init(),
        home: Scaffold(
            body: MarkSixPredictionCopy(
                attribute: 'special',
                label: '特码',
                values: ['04'],
                child: Text('04')))));
    await tester.tap(find.text('04'));
    await tester.pumpAndSettle();
    expect(find.text('复制失败，请重试'), findsOneWidget);
    expect(EasyLoading.isShow, isTrue);
    expect(find.byType(SnackBar), findsNothing);
    await EasyLoading.dismiss(animation: false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
