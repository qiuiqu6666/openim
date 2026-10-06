import 'dart:async';
import 'dart:ui' show ImageByteFormat, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/stickers/personal_sticker_panel.dart';
import 'package:openim/pages/chat/stickers/personal_sticker_store.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

PersonalSticker _sticker(int index) => PersonalSticker.fromJson({
      'id': 'dice-panel-$index',
      'mediaType': 'image',
      'mediaURL': 'https://example.test/$index.png',
      'thumbnailURL': null,
      'mimeType': 'image/png',
      'sizeBytes': 10,
      'width': 50,
      'height': 50,
      'durationMs': null,
      'sortOrder': index,
      'version': 1,
      'createdAt': 1,
      'updatedAt': 1,
    });

class _PanelApi extends PersonalStickerApi {
  final cursors = <String?>[];

  @override
  Future<({List<PersonalSticker> items, String? nextCursor})> page(
      {String? cursor, int limit = 50}) async {
    cursors.add(cursor);
    return cursor == null
        ? (
            items: [for (var i = 1; i <= 3; i++) _sticker(i)],
            nextCursor: 'older'
          )
        : (items: [_sticker(4)], nextCursor: null);
  }
}

Finder get _dice => find.byKey(const ValueKey('dice-sticker-tile'));
Finder _personal(int value) =>
    find.byKey(ValueKey('sticker-dice-panel-$value'));

Future<void> _awaitDicePreview(WidgetTester tester) async {
  final raw = find.descendant(of: _dice, matching: find.byType(RawImage));
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
    if (raw.evaluate().length != 1) continue;
    final image = tester.widget<RawImage>(raw).image;
    if (image == null) continue;
    final pixels = await tester
        .runAsync(() => image.toByteData(format: ImageByteFormat.rawRgba));
    expect(pixels, isNotNull);
    final rgba = pixels!.buffer.asUint8List();
    expect([for (var i = 3; i < rgba.length; i += 4) rgba[i]],
        contains(greaterThan(0)));
    return;
  }
  fail('The dice panel did not show its actual WebP picture.');
}

Future<PersonalStickerStore> _store() async {
  SharedPreferences.setMockInitialValues({});
  await DataSp.init();
  await DataSp.putLoginCertificate(LoginCertificate.fromJson(
      {'userID': 'dice-panel-user', 'chatToken': 'dice-panel-test-token'}));
  final store = PersonalStickerStore(api: _PanelApi());
  await store.refresh();
  addTearDown(store.dispose);
  return store;
}

Future<void> _mount(WidgetTester tester, PersonalStickerStore store,
    {Future<void> Function()? onSendDice,
    Future<void> Function(PersonalSticker)? onSend,
    Brightness brightness = Brightness.light,
    double width = 375}) async {
  tester.view.physicalSize = Size(width, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: SizedBox(
          height: 300,
          child: PersonalStickerPanel(
            store: store,
            onAdd: () async {},
            onSend: onSend ?? (_) async {},
            onSendDice: onSendDice,
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  if (onSendDice != null) await _awaitDicePreview(tester);
}

void main() {
  testWidgets('dice entry follows add tile without replacing personal stickers',
      (tester) async {
    final store = await _store();
    await _mount(tester, store, onSendDice: () async {});
    expect(_dice, findsOneWidget);
    expect(find.byTooltip('掷骰子'), findsOneWidget);
    final preview = tester.widget<ChatDiceSticker>(
        find.descendant(of: _dice, matching: find.byType(ChatDiceSticker)));
    expect(preview.value, 1);
    expect(preview.animate, isFalse);
    final add = tester.getRect(find.byKey(const ValueKey('sticker-add-tile')));
    final dice = tester.getRect(_dice);
    expect(dice.top, closeTo(add.top, .1));
    expect(dice.left, greaterThan(add.left));
    expect(tester.getRect(_personal(1)).left, greaterThan(dice.left));
    expect(tester.getRect(_personal(3)).top, greaterThan(dice.bottom));
    expect(store.items.map((item) => item.id),
        ['dice-panel-1', 'dice-panel-2', 'dice-panel-3']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('optional dice callback preserves the original personal grid',
      (tester) async {
    final store = await _store();
    final sent = <String>[];
    await _mount(tester, store, onSend: (item) async => sent.add(item.id));
    expect(_dice, findsNothing);
    expect(find.byType(ChatDiceSticker), findsNothing);
    final add = tester.getRect(find.byKey(const ValueKey('sticker-add-tile')));
    expect(tester.getRect(_personal(1)).top, closeTo(add.top, .1));
    expect(tester.getRect(_personal(3)).top, closeTo(add.top, .1));
    await tester.tap(_personal(3));
    await tester.pumpAndSettle();
    expect(sent, ['dice-panel-3']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pending dice send rejects repeated and personal sticker taps',
      (tester) async {
    final store = await _store();
    final pending = Completer<void>();
    var diceCalls = 0;
    final personal = <String>[];
    await _mount(tester, store,
        onSendDice: () {
          diceCalls++;
          return pending.future;
        },
        onSend: (item) async => personal.add(item.id));
    await tester.tap(_dice);
    await tester.tap(_dice);
    await tester.tap(_personal(1));
    await tester.pump();
    expect(diceCalls, 1);
    expect(personal, isEmpty);
    expect(tester.widget<InkWell>(_dice).onTap, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(_personal(1));
    await tester.pumpAndSettle();
    expect(personal, ['dice-panel-1']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pending personal sticker send also prevents a dice send',
      (tester) async {
    final store = await _store();
    final pending = Completer<void>();
    var diceCalls = 0;
    var personalCalls = 0;
    await _mount(tester, store,
        onSendDice: () async => diceCalls++,
        onSend: (_) {
          personalCalls++;
          return pending.future;
        });
    await tester.tap(_personal(1));
    await tester.tap(_dice);
    await tester.pump();
    expect(personalCalls, 1);
    expect(diceCalls, 0);
    expect(tester.widget<InkWell>(_dice).onTap, isNull);
    pending.complete();
    await tester.pumpAndSettle();
    await tester.tap(_dice);
    await tester.pumpAndSettle();
    expect(diceCalls, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed dice send shows feedback and allows retry',
      (tester) async {
    final store = await _store();
    var calls = 0;
    await _mount(tester, store, onSendDice: () async {
      if (++calls == 1) throw StateError('发送失败');
    });
    await tester.tap(_dice);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.widget<InkWell>(_dice).onTap, isNotNull);
    await tester.tap(_dice);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final fails in [false, true]) {
    testWidgets('pending dice completion after dispose is safe / error $fails',
        (tester) async {
      final store = await _store();
      final pending = Completer<void>();
      await _mount(tester, store, onSendDice: () => pending.future);
      await tester.tap(_dice);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      if (fails) {
        pending.completeError(StateError('late send failure'));
      } else {
        pending.complete();
      }
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('dice offset keeps load more and appended personal item correct',
      (tester) async {
    final store = await _store();
    final sent = <String>[];
    await _mount(tester, store,
        onSendDice: () async {}, onSend: (item) async => sent.add(item.id));
    final api = store.api as _PanelApi;
    expect(api.cursors, [null]);
    await tester.tap(find.byTooltip('加载更多'));
    await tester.pumpAndSettle();
    expect(api.cursors, [null, 'older']);
    expect(find.byTooltip('加载更多'), findsNothing);
    expect(_dice, findsOneWidget);
    for (var value = 1; value <= 4; value++) {
      await tester.tap(_personal(value));
      await tester.pumpAndSettle();
    }
    expect(
        sent, ['dice-panel-1', 'dice-panel-2', 'dice-panel-3', 'dice-panel-4']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final brightness in Brightness.values) {
    testWidgets('dice is an accessible button at 320 width / $brightness',
        (tester) async {
      final store = await _store();
      final semantics = tester.ensureSemantics();
      try {
        await _mount(tester, store,
            onSendDice: () async {}, brightness: brightness, width: 320);
        final node = tester.getSemantics(_dice);
        expect(node.flagsCollection.isButton, isTrue);
        expect(node.label, contains('掷骰子'));
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        final tile = tester.getRect(_dice);
        expect(tile.left, greaterThanOrEqualTo(0));
        expect(tile.right, lessThanOrEqualTo(320));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        semantics.dispose();
      }
    });
  }
}
