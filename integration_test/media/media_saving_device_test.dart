import 'dart:async';
import 'dart:io';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:openim/pages/chat/media/preview/chat_picture_renditions.dart';
import 'package:openim/pages/chat/media/video/chat_video_preparation.dart';
import 'package:openim_common/src/widgets/media_browser/on_demand_image.dart';
import 'package:openim_common/src/widgets/media_browser/on_demand_video.dart';
import 'package:openim_common/src/widgets/media_browser/viewer_image_provider.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

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
    await done.future.timeout(const Duration(seconds: 15));
  } finally {
    stream.removeListener(listener);
    await provider.evict();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final results = <String, Object?>{};
  testWidgets('native media sizing, shared disk cache and explicit downloads',
      (tester) async {
    final temp = await Directory.systemTemp.createTemp('media-device-');
    final source = File('${temp.path}/source.jpg');
    final pixels = img.Image(width: 2400, height: 1800);
    for (var y = 0; y < pixels.height; y++) {
      for (var x = 0; x < pixels.width; x++) {
        pixels.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
      }
    }
    await source.writeAsBytes(img.encodeJpg(pixels, quality: 95));
    final tiers = await ChatPictureRenditions.create(source.path);
    expect(tiers, isNotNull);
    expect(tiers!.thumbnail.width, 640);
    expect(tiers.preview.width, 1600);
    expect(tiers.thumbnail.length, lessThan(await source.length()));
    results['imageBytes'] = {
      'original': await source.length(),
      'preview': tiers.preview.length,
      'thumbnail': tiers.thumbnail.length,
    };
    final bytes = await File(tiers.thumbnail.path).readAsBytes();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <String, int>{};
    server.listen((request) async {
      final path = request.uri.path;
      requests[path] = (requests[path] ?? 0) + 1;
      request.response.headers.contentType = ContentType('image', 'jpeg');
      request.response.add(bytes);
      await request.response.close();
    });
    final base = 'http://127.0.0.1:${server.port}';
    try {
      // Real platform path_provider and encoded disk cache, no mocked channel.
      await decode(
          ExtendedNetworkImageProvider('$base/shared.jpg', cache: true));
      await decode(ViewerImageProvider('$base/shared.jpg'));
      await decode(ViewerImageProvider('$base/shared.jpg'));
      expect(requests['/shared.jpg'], 1);
      await decode(ViewerImageProvider('$base/reverse.jpg'));
      await decode(
          ExtendedNetworkImageProvider('$base/reverse.jpg', cache: true));
      expect(requests['/reverse.jpg'], 1);
      for (final brightness in Brightness.values) {
        final suffix = brightness.name;
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
              body: OnDemandImage(
            key: ValueKey(suffix),
            preview: (_) =>
                Image(image: ViewerImageProvider('$base/preview-$suffix.jpg')),
            original: (_) =>
                Image(image: ViewerImageProvider('$base/original-$suffix.jpg')),
          )),
        ));
        await tester.pumpAndSettle();
        expect(requests['/original-$suffix.jpg'], isNull);
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
        // Wait for native HTTP and image decode, not just animation frames.
        for (var i = 0;
            i < 50 && requests['/original-$suffix.jpg'] == null;
            i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(requests['/original-$suffix.jpg'], 1);
      }
      var players = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: OnDemandVideo(
        autoPlay: false,
        poster: const Text('poster'),
        player: (_) {
          players++;
          return const Text('player');
        },
      ))));
      await tester.pump(const Duration(seconds: 2));
      expect(players, 0);
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(players, 1);
      results['requests'] = requests;
      results['deferredVideoPlayer'] = true;
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await server.close(force: true);
      await tiers.dispose();
      await temp.delete(recursive: true);
    }
    binding.reportData = {'results': results, 'completed': true};
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets('native 720p video preparation preserves source', (tester) async {
    binding.reportData = {'results': results, 'completed': false};
    const fixture = String.fromEnvironment('MEDIA_VIDEO_FIXTURE');
    expect(fixture, isNotEmpty,
        reason: 'Explicit loopback video fixture required');
    final temp = await Directory.systemTemp.createTemp('media-video-');
    final source = File('${temp.path}/input.mp4');
    final client = HttpClient();
    File? output;
    try {
      final response = await (await client.getUrl(Uri.parse(fixture))).close();
      expect(response.statusCode, 200);
      await response.pipe(source.openWrite());
      final originalBytes = await source.length();
      expect((await prepareChatVideo(source, ChatVideoQuality.original)).path,
          source.path);
      output = await prepareChatVideo(source, ChatVideoQuality.standard);
      final info = await VideoCompress.getMediaInfo(output.path);
      expect(output.path, isNot(source.path));
      expect(await output.length(), lessThan(originalBytes));
      final player = VideoPlayerController.file(output);
      late Size decodedSize;
      try {
        await player.initialize();
        decodedSize = player.value.size;
        expect(decodedSize.width, 1280);
        expect(decodedSize.height, 720);
        expect(player.value.duration.inMilliseconds, greaterThan(3500));
      } finally {
        await player.dispose();
      }
      expect(await source.length(), originalBytes);
      results['video'] = {
        'originalBytes': originalBytes,
        'compressedBytes': await output.length(),
        'width': decodedSize.width,
        'height': decodedSize.height,
        'compressorReportedWidth': info.width,
        'compressorReportedHeight': info.height,
        'duration': info.duration
      };
      binding.reportData = {'results': results, 'completed': true};
    } finally {
      client.close(force: true);
      if (output != null && output.path != source.path && await output.exists())
        await output.delete();
      await temp.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
