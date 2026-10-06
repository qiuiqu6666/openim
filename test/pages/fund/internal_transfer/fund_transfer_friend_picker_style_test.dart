import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/fund/internal_transfer/presentation/fund_transfer_friend_picker_tokens.dart';
import 'package:openim_common/openim_common.dart';

import 'fund_transfer_friend_picker_test.dart'
    show openPicker, friend, friendRow;

const _previewDir = String.fromEnvironment('FUND_RECIPIENT_PICKER_PREVIEW_DIR');

Finder _key(String key) => find.byKey(ValueKey(key));

void _viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

double _contrast(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final light = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final dark = foregroundLuminance < backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  return (light + .05) / (dark + .05);
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.locale = const Locale('zh', 'CN');
  });
  tearDown(() {
    Styles.isDark = false;
    Get.reset();
  });

  setUpAll(() async {
    if (_previewDir.isEmpty) return;
    for (final font in [
      (name: 'RecipientPreviewCjk', path: 'C:/Windows/Fonts/msyh.ttc'),
      (
        name: 'MaterialIcons',
        path:
            'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
      ),
    ]) {
      final bytes = await File(font.path).readAsBytes();
      await (FontLoader(font.name)
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        '${brightness.name} applies matching surfaces and readable text',
        (tester) async {
      _viewport(tester, const Size(375, 812));
      await openPicker(
        tester,
        (_, __) async => [
          friend('qiu', '秋啊', account: 'qiu-public'),
          friend('lin', '小林', account: 'lin-public'),
        ],
        brightness: brightness,
      );
      final page = _key('fund-transfer-friend-picker');
      final colors = FundTransferFriendPickerColors.of(tester.element(page));
      final scaffold = tester.widget<Scaffold>(page);
      final search =
          tester.widget<SearchBox>(_key('fund-transfer-friend-search'));
      final title = tester.widget<Text>(find.text('选择收款人'));
      final row = tester.widget<ListTile>(friendRow('qiu'));
      final subtitle = row.subtitle! as Text;
      expect(scaffold.backgroundColor, colors.page);
      expect(row.tileColor, colors.page);
      expect(title.style!.color, colors.text);
      expect(search.backgroundColor, colors.searchFill);
      expect(search.textStyle!.color, colors.text);
      expect(search.hintStyle!.color, colors.secondary);
      expect((search.searchIcon! as Icon).color, colors.secondary);
      expect((search.clearIcon! as Icon).color, colors.secondary);
      expect(subtitle.style!.color, colors.secondary);
      expect(
          tester.widget<Divider>(find.byType(Divider)).color, colors.separator);
      for (final combination in [
        (colors.text, colors.page),
        (colors.secondary, colors.page),
        (colors.secondary, colors.searchFill),
        (colors.actionText, colors.page),
      ]) {
        expect(_contrast(combination.$1, combination.$2),
            greaterThanOrEqualTo(4.5));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('${brightness.name} loading and retry use the wallet palette',
        (tester) async {
      final pending = Completer<List<ISUserInfo>>();
      await openPicker(tester, (_, __) => pending.future,
          brightness: brightness);
      final colors = FundTransferFriendPickerColors.of(
          tester.element(_key('fund-transfer-friend-picker')));
      final loading = tester.widget<LinearProgressIndicator>(
          _key('fund-transfer-friend-loading'));
      expect(loading.color, colors.accent);
      expect(loading.backgroundColor, colors.searchFill);
      pending.completeError(StateError('private backend failure'));
      await tester.pumpAndSettle();
      final retry =
          tester.widget<TextButton>(_key('fund-transfer-friend-retry'));
      expect(retry.style!.foregroundColor!.resolve({}), colors.actionText);
      expect(find.text('private backend failure'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '${brightness.name} empty message keeps readable secondary text',
        (tester) async {
      await openPicker(tester, (_, __) async => [], brightness: brightness);
      final colors = FundTransferFriendPickerColors.of(
          tester.element(_key('fund-transfer-friend-picker')));
      final message = tester.widget<Text>(find.text('未找到相关好友'));
      expect(message.style!.color, colors.secondary);
      expect(_contrast(message.style!.color!, colors.page),
          greaterThanOrEqualTo(4.5));
      expect(tester.takeException(), isNull);
    });

    for (final keyboard in [
      EdgeInsets.zero,
      const EdgeInsets.only(bottom: 280)
    ]) {
      testWidgets(
          '${brightness.name} 320px and 2x text fits with keyboard=${keyboard.bottom}',
          (tester) async {
        _viewport(tester, const Size(320, 740));
        await openPicker(
          tester,
          (_, __) async => [
            for (var index = 0; index < 12; index++)
              friend('person-$index', '好友$index', account: 'public-$index'),
          ],
          brightness: brightness,
          textScale: 2,
          keyboard: keyboard,
        );
        final field = find.byType(TextField);
        final fieldRect = tester.getRect(field);
        expect(fieldRect.left, greaterThanOrEqualTo(0));
        expect(fieldRect.right, lessThanOrEqualTo(320));
        expect(fieldRect.bottom, lessThanOrEqualTo(740 - keyboard.bottom));
        expect(tester.takeException(), isNull);
        await tester.enterText(field, 'public-11');
        await tester.pumpAndSettle();
        expect(friendRow('person-11'), findsOneWidget);
        final rowRect = tester.getRect(friendRow('person-11'));
        expect(rowRect.height, greaterThanOrEqualTo(48));
        expect(rowRect.bottom, lessThanOrEqualTo(740 - keyboard.bottom));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('export recipient picker ${brightness.name}',
        skip: _previewDir.isEmpty, (tester) async {
      _viewport(tester, const Size(375, 812));
      Styles.isDark = brightness == Brightness.dark;
      final boundaryKey = GlobalKey();
      await openPicker(
        tester,
        (_, __) async => [
          friend('99Message', '99Message'),
          friend('99Pay', '99Pay'),
          friend('assistant', 'AI助理'),
          friend('qiu', '秋啊'),
          friend('lin', '小林', account: 'lin-public'),
        ],
        brightness: brightness,
        boundaryKey: boundaryKey,
        fontFamily: 'RecipientPreviewCjk',
      );
      await tester.pumpAndSettle();
      expect(friendRow('99Message'), findsNothing);
      final render = boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(_previewDir).create(recursive: true);
        await File('$_previewDir/recipient-picker-${brightness.name}.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
}
