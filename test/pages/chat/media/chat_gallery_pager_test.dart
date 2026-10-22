import 'dart:async';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/media/chat_gallery_pager.dart';
import 'package:openim/pages/chat/media/chat_picture_gallery.dart';

Message picture(String id) => Message(
    clientMsgID: id,
    contentType: MessageType.picture,
    pictureElem: PictureElem(
        sourcePicture: PictureInfo(url: 'https://example.test/$id.png')));
void main() {
  test('deduplicates append and preserves selected/action indexes', () async {
    final selected = picture('selected');
    final gallery = await ChatPictureGallery.fromMessages([selected], selected);
    final original = gallery.sources.first;
    final pager = ChatGalleryPager(
        gallery: gallery,
        conversationID: 'c',
        isCurrent: () => true,
        query: (page, count) async => [selected, picture('older')]);
    expect(await pager.load(), false);
    expect(gallery.sources.length, 2);
    expect(identical(original, gallery.sources.first), true);
    expect(gallery.messageAt(0)!.clientMsgID, 'selected');
    expect(gallery.messageAt(1)!.clientMsgID, 'older');
    expect(() => gallery.sources.clear(), throwsUnsupportedError);
  });
  test('deduplicates in-flight loads and discards stale account response',
      () async {
    final pending = Completer<List<Message>>();
    var current = true, calls = 0;
    final gallery = ChatPictureGallery(sources: [], initialIndex: 0);
    final pager = ChatGalleryPager(
        gallery: gallery,
        conversationID: 'c',
        isCurrent: () => current,
        query: (_, __) {
          calls++;
          return pending.future;
        });
    final a = pager.load(), b = pager.load();
    expect(calls, 1);
    current = false;
    pending.complete([picture('late')]);
    await Future.wait([a, b]);
    expect(gallery.sources, isEmpty);
  });
  test('full duplicate server page terminates and failures retry same page',
      () async {
    var fail = true;
    final pages = <int>[];
    final gallery = ChatPictureGallery(sources: [], initialIndex: 0);
    final pager = ChatGalleryPager(
        gallery: gallery,
        conversationID: 'c',
        isCurrent: () => true,
        query: (page, count) async {
          pages.add(page);
          if (fail) {
            fail = false;
            throw StateError('offline');
          }
          return List.generate(count, (i) => picture('$i'));
        });
    await expectLater(pager.load(), throwsStateError);
    expect(await pager.load(), true);
    expect(await pager.load(), false);
    expect(pages, [1, 1, 2]);
    expect(gallery.sources.length, 30);
  });
}
