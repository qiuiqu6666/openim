import 'dart:async';
import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/chat/chat_picture_view.dart';

class _PendingFile implements File {
  _PendingFile(this.path, this.result, this.onCheck);

  @override
  final String path;
  final Future<bool> result;
  final VoidCallback onCheck;

  @override
  Future<bool> exists() {
    onCheck();
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      'local checks survive rebuilds and ignore completion after leaving',
      (tester) async {
    final pending = Completer<bool>();
    var checks = 0;
    final message = Message()
      ..clientMsgID = 'pending-picture'
      ..contentType = MessageType.picture
      ..pictureElem = PictureElem(
        sourcePath: 'pending-original.jpg',
        sourcePicture: PictureInfo(width: 800, height: 400),
        snapshotPicture: PictureInfo(url: 'https://example.test/thumbnail.jpg'),
      );

    Widget page() => MaterialApp(
          builder: (context, child) {
            ScreenUtil.init(context, designSize: const Size(375, 812));
            return child!;
          },
          home: Scaffold(
            body: ChatPictureView(message: message, isISend: true),
          ),
        );

    await IOOverrides.runZoned(() async {
      await tester.pumpWidget(page());
      expect(checks, 1);
      // A local original should not start a remote download while its check runs.
      expect(find.byType(ExtendedImage), findsNothing);
      await tester.pumpWidget(page());
      expect(checks, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(true);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
        createFile: (path) =>
            _PendingFile(path, pending.future, () => checks++));
  });
}
