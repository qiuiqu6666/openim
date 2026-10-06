import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/stickers/builtin/chat_builtin_sticker.dart';
import 'package:openim/pages/chat/stickers/builtin/chat_builtin_sticker_panel.dart';
import 'package:openim_common/openim_common.dart' show ChatComposerTokens;

Finder _tile(ChatBuiltinSticker sticker) =>
    find.byKey(ValueKey('builtin-sticker-${sticker.id}'));

Future<void> _mount(WidgetTester tester,
    {Brightness brightness = Brightness.light,
    required Future<void> Function(ChatBuiltinSticker) onSend}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: Scaffold(
      body: SizedBox(
        height: 400,
        child: ChatBuiltinStickerPanel(onSend: onSend),
      ),
    ),
  ));
  final images = tester.widgetList<Image>(find.byType(Image)).toList();
  await tester.runAsync(() async {
    for (final image in images) {
      await precacheImage(image.image, tester.element(find.byType(Scaffold)));
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
        'bundled images preserve transparency in four columns / $brightness',
        (tester) async {
      final sent = <ChatBuiltinSticker>[];
      await _mount(tester,
          brightness: brightness, onSend: (sticker) async => sent.add(sticker));
      final stickers = ChatBuiltinStickerCatalog.stickers;
      final first = tester.getRect(_tile(stickers.first));
      for (var index = 1; index < 4; index++) {
        final rect = tester.getRect(_tile(stickers[index]));
        expect(rect.top, first.top);
        expect(rect.left, greaterThan(first.left));
      }
      expect(tester.getRect(_tile(stickers[4])).top, greaterThan(first.bottom));
      final panel = find.byType(ChatBuiltinStickerPanel);
      final background =
          find.descendant(of: panel, matching: find.byType(ColoredBox)).first;
      expect(tester.widget<ColoredBox>(background).color,
          ChatComposerTokens.surface(dark: brightness == Brightness.dark));
      for (final image in tester.widgetList<Image>(find.byType(Image))) {
        expect(image.fit, BoxFit.contain);
        expect(image.color, isNull);
        expect((image.image as AssetImage).assetName,
            startsWith(ChatBuiltinStickerCatalog.assetDirectory));
      }
      expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      expect(find.byTooltip('管理表情'), findsNothing);
      expect(find.text('添加的单个表情'), findsNothing);
      await tester.tap(_tile(stickers.first));
      await tester.pumpAndSettle();
      expect(sent, [stickers.first]);
      await tester.scrollUntilVisible(_tile(stickers.last), 150,
          scrollable:
              find.descendant(of: panel, matching: find.byType(Scrollable)));
      await tester.tap(_tile(stickers.last));
      await tester.pumpAndSettle();
      expect(sent, [stickers.first, stickers.last]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'pending send blocks repeated and other sticker taps until complete',
      (tester) async {
    final gate = Completer<void>();
    final sent = <ChatBuiltinSticker>[];
    final semantics = tester.ensureSemantics();
    try {
      await _mount(tester, onSend: (sticker) {
        sent.add(sticker);
        return sent.length == 1 ? gate.future : Future.value();
      });
      final first = ChatBuiltinStickerCatalog.stickers.first;
      final second = ChatBuiltinStickerCatalog.stickers[1];
      expect(tester.getSemantics(_tile(first)).flagsCollection.isEnabled,
          Tristate.isTrue);
      await tester.tap(_tile(first));
      await tester.tap(_tile(first));
      await tester.tap(_tile(second));
      await tester.pump();
      expect(sent, [first]);
      expect(tester.getSemantics(_tile(second)).flagsCollection.isEnabled,
          Tristate.isFalse);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(_tile(second));
      await tester.pumpAndSettle();
      expect(sent, [first, second]);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('failed send shows a friendly error and permits retry',
      (tester) async {
    var calls = 0;
    await _mount(tester, onSend: (_) async {
      if (++calls == 1) throw StateError('transport details');
    });
    final tile = _tile(ChatBuiltinStickerCatalog.stickers.first);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('发送失败，请重试'), findsOneWidget);
    expect(find.textContaining('transport details'), findsNothing);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'completion after closing the panel does not show an error or update state',
      (tester) async {
    final gate = Completer<void>();
    await _mount(tester, onSend: (_) => gate.future);
    await tester.tap(_tile(ChatBuiltinStickerCatalog.stickers.first));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    gate.completeError(StateError('late failure'));
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
