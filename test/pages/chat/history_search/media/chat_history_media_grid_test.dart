import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history_search/media/chat_history_media_grid.dart';
import 'package:openim/pages/chat/media/chat_picture_gallery.dart';

import '../../../../support/media/deferred_thumbnail_http.dart';

void main() {
  for (final thumbnail in ['https://example.test/thumb.png', null, '  ']) {
    testWidgets(
        'grid only requests thumbnail ($thumbnail), tap retains big image',
        (tester) async {
      final client = DeferredThumbnailHttpClient()..install();
      final message = Message()
        ..clientMsgID = 'photo'
        ..contentType = MessageType.picture
        ..pictureElem = PictureElem(
          sourcePath: File('assets/ai/11.webp').absolute.path,
          snapshotPicture: PictureInfo(url: thumbnail),
          bigPicture: PictureInfo(url: 'https://example.test/big.png'),
          sourcePicture: PictureInfo(url: 'https://example.test/original.png'),
        );
      Message? tapped;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChatHistoryMediaGrid(
            messages: [message],
            onTap: (value) => tapped = value,
            footer: const SizedBox.shrink(),
          ),
        ),
      ));
      await tester.pump();
      if (thumbnail?.trim().isNotEmpty == true) {
        final provider = tester.widget<Image>(find.byType(Image)).image;
        final network =
            provider is ResizeImage ? provider.imageProvider : provider;
        expect(network, isA<NetworkImage>());
        expect((network as NetworkImage).url, thumbnail);
        expect(client.requests, 1);
      } else {
        expect(find.byType(Image), findsNothing);
        expect(client.requests, 0);
      }
      await tester.tap(find.byType(InkWell));
      expect(tapped, same(message));
      final gallery = await ChatPictureGallery.fromMessages([tapped!], tapped!);
      expect(gallery.sources.single.previewUrl, 'https://example.test/big.png');
      expect(gallery.sources.single.deferOriginal, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      DeferredThumbnailHttpClient.restore();
    });
  }
}
