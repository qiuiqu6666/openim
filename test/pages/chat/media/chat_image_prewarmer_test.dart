import 'dart:async';
import 'package:flutter/painting.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/media/chat_image_prewarmer.dart';
import 'package:openim_common/media_preloading.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

Message picture(int index) => Message()
  ..clientMsgID = '$index'
  ..contentType = MessageType.picture
  ..pictureElem = PictureElem(
    sourcePicture: PictureInfo(url: 'https://images.test/$index/original'),
    bigPicture: PictureInfo(url: 'https://images.test/$index/clear'),
    snapshotPicture: PictureInfo(url: 'https://images.test/$index/thumb'),
  );

class ControlledImage extends ViewerImageProvider {
  ControlledImage(super.url);
  final stream = Completer<void>();
  bool cancelled = false;
  @override
  Future<void> prefetchEncoded() => stream.future;
  @override
  ImageStreamCompleter loadImage(
          ViewerImageProvider key, ImageDecoderCallback decode) =>
      throw StateError('Speculative work must not decode pixels');
  @override
  void cancel() {
    cancelled = true;
    super.cancel();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
  });

  test('visible first, bounded neighbors, no original or private image', () {
    final messages = List.generate(20, picture);
    final urls = ChatImagePrewarmer.candidates(messages, ['8', '9']);
    expect(urls.take(4), [
      'https://images.test/8/thumb',
      'https://images.test/8/clear',
      'https://images.test/9/thumb',
      'https://images.test/9/clear'
    ]);
    expect(urls.length, 12);
    expect(urls.any((u) => u.endsWith('/original')), isFalse);
    expect(
        ChatImagePrewarmer.candidates(messages, List.generate(20, (i) => '$i'))
            .length,
        16);
    messages[8].attachedInfoElem = AttachedInfoElem(isPrivateChat: true);
    expect(
        ChatImagePrewarmer.candidates(messages, ['8'])
            .any((u) => u.contains('/8/')),
        isFalse);
    expect(ChatImagePrewarmer.candidates(messages, []), isEmpty);
  });

  test('missing source URL never prefetches the gallery original fallback', () {
    final message = picture(0);
    message.pictureElem!.sourcePicture = null;
    final urls = ChatImagePrewarmer.candidates([message], ['0']);
    expect(urls.first, 'https://images.test/0/thumb');
    expect(urls, isNot(contains('https://images.test/0/clear')));
  });

  testWidgets(
      'single concurrency, scroll pause, resume, cached completion and exit',
      (tester) async {
    final requests = <ControlledImage>[];
    final warmer = ChatImagePrewarmer(createImage: (url) {
      final image = ControlledImage(url);
      requests.add(image);
      return image;
    });
    final messages = [picture(0)];
    warmer.update(messages, ['0']);
    await tester.pump(const Duration(milliseconds: 249));
    expect(requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(requests, hasLength(1));
    warmer.setScrolling(true);
    requests.first.stream.complete();
    await tester.pump(const Duration(seconds: 1));
    expect(requests, hasLength(1));
    warmer.setScrolling(false);
    await tester.pump(const Duration(milliseconds: 250));
    expect(requests, hasLength(2));
    requests.last.stream.complete();
    await tester.pump();
    warmer.update(messages, ['0']);
    await tester.pump(const Duration(milliseconds: 250));
    expect(requests, hasLength(2));
    warmer.update([picture(1)], ['1']);
    await tester.pump(const Duration(milliseconds: 250));
    warmer.dispose();
    expect(requests.last.cancelled, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(requests, hasLength(3));
  });

  testWidgets('covered route cancels work and resumes with current viewport',
      (tester) async {
    final requests = <ControlledImage>[];
    final warmer = ChatImagePrewarmer(createImage: (url) {
      final image = ControlledImage(url);
      requests.add(image);
      return image;
    });
    warmer.update([picture(0)], ['0']);
    await tester.pump(const Duration(milliseconds: 250));
    warmer.setActive(false);
    expect(requests.single.cancelled, isTrue);
    warmer.update([picture(1)], ['1']);
    await tester.pump(const Duration(seconds: 1));
    expect(requests, hasLength(1));
    warmer.setActive(true);
    await tester.pump(const Duration(milliseconds: 250));
    expect(requests.last.url, 'https://images.test/1/thumb');
    warmer.dispose();
  });
}
