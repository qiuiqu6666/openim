import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/mine/settings/chat_background_local_service.dart';

void main() {
  test('background validity preserves typed values and checks local files',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('background-valid-');
    addTearDown(() => directory.delete(recursive: true));
    final file =
        await File('${directory.path}/background.jpg').writeAsBytes([1]);
    expect(await ChatBackgroundLocalService.isUsable(null), isFalse);
    expect(await ChatBackgroundLocalService.isUsable(''), isFalse);
    expect(await ChatBackgroundLocalService.isUsable('color:fff1f1f1'), isTrue);
    expect(await ChatBackgroundLocalService.isUsable('asset:background.png'),
        isTrue);
    expect(await ChatBackgroundLocalService.isUsable(file.path), isTrue);
    expect(
        await ChatBackgroundLocalService.isUsable('file:${file.path}'), isTrue);
    await file.delete();
    expect(await ChatBackgroundLocalService.isUsable('file:${file.path}'),
        isFalse);
  });
}
