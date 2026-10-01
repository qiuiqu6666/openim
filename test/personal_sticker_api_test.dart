import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/personal_sticker_store.dart';

void main() {
  test('sticker API uses account endpoints and parses GIF and video', () async {
    final requests = <RequestOptions>[];
    final client = Dio();
    client.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options);
      final item = {
        'id': 'st_1',
        'mediaType': 'video',
        'mediaURL': 'https://example.test/object/u/a.mp4',
        'thumbnailURL': 'https://example.test/object/u/a.jpg',
        'mimeType': 'video/mp4',
        'sizeBytes': 1000,
        'width': 320,
        'height': 240,
        'durationMs': 2000,
        'sortOrder': 0,
        'version': 1,
        'createdAt': 1,
        'updatedAt': 1,
      };
      final data = options.method == 'GET'
          ? {
              'items': [item],
              'nextCursor': 'next'
            }
          : options.method == 'POST'
              ? {'item': item}
              : <String, dynamic>{};
      handler.resolve(Response(
          requestOptions: options, data: {'errCode': 0, 'data': data}));
    }));

    final api = PersonalStickerApi(client: client);
    final page = await api.page(limit: 50);
    expect(page.items.single.isVideo, isTrue);
    expect(page.items.single.previewURL, endsWith('a.jpg'));
    expect(page.nextCursor, 'next');

    await api.create('https://example.test/object/u/a.mp4', 'request-id');
    await api.delete('st_1');
    await api.reorder(['st_1']);

    expect(requests.map((r) => r.method), ['GET', 'POST', 'DELETE', 'PUT']);
    expect(requests.every((r) => r.path.contains('/chat/stickers')), isTrue);
    expect(requests[1].data, {
      'mediaURL': 'https://example.test/object/u/a.mp4',
      'clientRequestID': 'request-id'
    });
    expect(requests[3].data, {
      'ids': ['st_1']
    });
  });
}
