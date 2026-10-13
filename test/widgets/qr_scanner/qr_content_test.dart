import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/widgets/qr_scanner/content/qr_content.dart';
import 'package:openim/widgets/qr_scanner/content/qr_content_actions.dart';
import 'package:openim/widgets/qr_scanner/content/qr_content_sheet.dart';

class _Actions extends QrContentActions {
  final copied = <String>[];
  final opened = <Uri>[];
  final contacts = <String>[];
  @override
  Future<void> copy(String value) async {
    copied.add(value);
  }

  @override
  Future<bool> openBrowser(Uri uri) async {
    opened.add(uri);
    return true;
  }

  @override
  Future<void> exportContact(String value, Rect origin) async {
    contacts.add(value);
  }
}

void main() {
  test('HTTP URLs are actions; unknown schemes and JSON remain raw text', () {
    expect(
        QrContent.parse('https://example.test/a?q=1').kind, QrContentKind.url);
    for (final raw in [
      'javascript:alert(1)',
      'file:///a',
      'https://user:pass@example.test',
      '99chat-login:v2:unknown',
      '{"action":"login","token":"fixture"}',
      '{malformed}'
    ]) {
      final c = QrContent.parse(raw);
      expect(c.kind, QrContentKind.unknown);
      expect(c.raw, raw);
      expect(c.url, isNull);
    }
    expect(QrContent.parse('ordinary text').kind, QrContentKind.text);
  });
  test('Wi-Fi escaping and contact formats are preserved', () {
    final wifi =
        QrContent.parse(r'WIFI:T:WPA;S:Office\;East;P:p\:a\;ss\\word;;');
    expect(wifi.kind, QrContentKind.wifi);
    expect(wifi.ssid, 'Office;East');
    expect(wifi.password, r'p:a;ss\word');
    expect(QrContent.parse('WIFI:T:unknown;S:example;;').kind,
        QrContentKind.unknown);
    expect(
        QrContent.parse('BEGIN:VCARD\nVERSION:3.0\nFN:Alice\nEND:VCARD').kind,
        QrContentKind.contact);
    expect(
        QrContent.parse('MECARD:N:Alice;TEL:123;;').vcard, contains('TEL:123'));
  });
  for (final dark in [false, true]) {
    testWidgets(
        'URL requires browser action and supports ${dark ? "dark" : "light"} theme',
        (tester) async {
      final actions = _Actions();
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          home: RepaintBoundary(
              key: key,
              child: Scaffold(
                  body: Builder(
                      builder: (context) => TextButton(
                          onPressed: () => showQrContent(
                              context, 'https://example.test/path?q=fixture',
                              actions: actions),
                          child: const Text('Scan')))))));
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();
      expect(actions.opened, isEmpty);
      await tester.tap(find.byKey(const ValueKey('qr-open-browser')));
      await tester.pumpAndSettle();
      expect(actions.opened.single.toString(),
          'https://example.test/path?q=fixture');
      await tester.tap(find.byKey(const ValueKey('qr-copy-raw')));
      await tester.pumpAndSettle();
      expect(actions.copied.single, 'https://example.test/path?q=fixture');
      expect(tester.takeException(), isNull);
      final output = Platform.environment['QR_CONTENT_PREVIEW'];
      if (output != null) {
        await tester.runAsync(() async {
          final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
              find.byType(RepaintBoundary).first);
          final img = await boundary.toImage();
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/qr-content-${dark ? "dark" : "light"}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          img.dispose();
        });
      }
    });
  }
  testWidgets('unknown JSON exposes the exact original and copy only',
      (tester) async {
    const raw = ' {"unknown":true,"value":"测试"} ';
    final actions = _Actions();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: QrContentSheet(
                content: QrContent.parse(raw), actions: actions))));
    expect(find.byKey(const ValueKey('qr-open-browser')), findsNothing);
    expect(
        tester
            .widget<SelectableText>(find.byKey(const ValueKey('qr-raw-text')))
            .data,
        raw);
    await tester.tap(find.byKey(const ValueKey('qr-copy-raw')));
    await tester.pumpAndSettle();
    expect(actions.copied, [raw]);
    expect(actions.opened, isEmpty);
  });
  testWidgets('Wi-Fi and contact actions never run automatically',
      (tester) async {
    final actions = _Actions();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: QrContentSheet(
                content: QrContent.parse('WIFI:T:WPA;S:Fixture;P:secret;;'),
                actions: actions))));
    expect(actions.copied, isEmpty);
    await tester.tap(find.text('Copy password'));
    await tester.pumpAndSettle();
    expect(actions.copied, ['secret']);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: QrContentSheet(
                content: QrContent.parse('MECARD:N:Alice;TEL:123;;'),
                actions: actions))));
    expect(actions.contacts, isEmpty);
    await tester.tap(find.text('Export contact'));
    await tester.pumpAndSettle();
    expect(actions.contacts.single, contains('BEGIN:VCARD'));
  });
}
