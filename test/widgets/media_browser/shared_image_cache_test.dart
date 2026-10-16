import 'dart:async';
import 'dart:io';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/utils/media/shared_image_disk_cache.dart';
import 'package:openim_common/src/widgets/media_browser/viewer_image_provider.dart';
import '../../support/performance/viewer_test_cache.dart';

class _RealHttp extends HttpOverrides {}

Future<void> decode(ImageProvider provider) async {
  final done = Completer<void>();
  final stream = provider.resolve(ImageConfiguration.empty);
  final listener = ImageStreamListener((info, _) {
    info.dispose();
    if (!done.isCompleted) done.complete();
  }, onError: (Object error, StackTrace? stack) {
    if (!done.isCompleted) done.completeError(error, stack);
  });
  stream.addListener(listener);
  try {
    await done.future.timeout(const Duration(seconds: 5));
  } finally {
    stream.removeListener(listener);
    await provider.evict();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final viewerFirst in [false, true]) {
    test('bubble and viewer share one download, viewerFirst=$viewerFirst',
        () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final temp = await Directory.systemTemp.createTemp('shared-image-test');
        const channel = MethodChannel('plugins.flutter.io/path_provider');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => temp.path);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var requests = 0;
        final bytes =
            await File('openim_common/assets/images/ic_archive_99chat.png')
                .readAsBytes();
        server.listen((request) async {
          requests++;
          request.response.add(bytes);
          await request.response.close();
        });
        final url = 'http://127.0.0.1:${server.port}/same.png';
        final shared =
            SharedImageDiskCache(temporaryDirectory: () async => temp);
        ViewerImageProvider viewer() => ViewerImageProvider(url,
            sharedCache: shared, cache: ViewerTestCache());
        final bubble =
            ExtendedNetworkImageProvider(url, cache: true, retries: 0);
        try {
          if (viewerFirst) {
            await decode(viewer());
            await decode(bubble);
          } else {
            await decode(bubble);
            await decode(viewer());
          }
          await decode(viewer());
          expect(requests, 1);
          // Different transformed content must still require its own request.
          await decode(ViewerImageProvider('$url?different-thumbnail',
              sharedCache: shared, cache: ViewerTestCache()));
          expect(requests, 2);
        } finally {
          await server.close(force: true);
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
          await temp.delete(recursive: true);
        }
      }, _RealHttp());
    });
  }
  test('canceled cache writes leave neither partial nor completed entries',
      () async {
    final temp = await Directory.systemTemp.createTemp('cancel-image-cache');
    final shared = SharedImageDiskCache(temporaryDirectory: () async => temp);
    var checks = 0;
    try {
      await shared.write('image', Uint8List.fromList([1, 2, 3]),
          isCurrent: () => ++checks == 1);
      expect(await shared.read('image'), isNull);
      expect(await temp.list(recursive: true).where((f) => f is File).toList(),
          isEmpty);
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
