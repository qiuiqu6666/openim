import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  testWidgets('horizontal swipe changes the full-screen picture',
      (tester) async {
    final image = File('openim_common/assets/images/ic_archive_99chat.png');
    expect(image.existsSync(), isTrue);
    final pages = <int>[];
    final saved = <int>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(tester.element(find.text('Open')))
                .push(MaterialPageRoute<void>(
              builder: (_) => MediaBrowser(
                sources: [
                  MediaSource(
                    thumbnail: '', file: image, tag: 'first',
                    senderName: '发送者', sentAt: DateTime(2026, 10, 1, 12, 29),
                  ),
                  MediaSource(
                    thumbnail: '', file: image, tag: 'second',
                    senderName: '发送者', sentAt: DateTime(2026, 10, 1, 12, 30),
                  ),
                ],
                initialIndex: 0,
                onPageChanged: pages.add,
                onSave: saved.add,
              ),
            )),
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1/2'), findsOneWidget);
    await tester.drag(find.byType(MediaBrowser), const Offset(-550, 0));
    await tester.pumpAndSettle();

    expect(pages, contains(1));
    expect(find.textContaining('2/2'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.download));
    expect(saved, [1]);
  });
}
