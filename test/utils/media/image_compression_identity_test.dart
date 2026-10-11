import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';
// Test replaces the path-provider platform already used by the application.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:openim_common/openim_common.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationCachePath() async => path;
}

class _Compression extends UnsupportedFlutterImageCompress {
  @override
  Future<XFile?> compressAndGetFile(String path, String targetPath,
      {int minWidth = 1920,
      int minHeight = 1080,
      int inSampleSize = 1,
      int quality = 95,
      int rotate = 0,
      bool autoCorrectionAngle = true,
      CompressFormat format = CompressFormat.jpeg,
      bool keepExif = false,
      int numberOfRetries = 5}) async {
    await File(path).copy(targetPath);
    return XFile(targetPath);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'overlapping photos with identical names never overwrite prepared upload',
      () async {
    final root = await Directory.systemTemp.createTemp('compression-test-');
    final paths = PathProviderPlatform.instance;
    final compression = FlutterImageCompressPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
    FlutterImageCompressPlatform.instance = _Compression();
    addTearDown(() async {
      PathProviderPlatform.instance = paths;
      FlutterImageCompressPlatform.instance = compression;
      await root.delete(recursive: true);
    });
    final inputs = <File>[];
    for (var i = 0; i < 2; i++) {
      final dir = await Directory('${root.path}/$i').create();
      inputs.add(await File('${dir.path}/same.jpg').writeAsBytes([i, 2, 3]));
    }
    final outputs =
        await Future.wait(inputs.map(IMUtils.compressImageAndGetFile));
    expect(outputs[0]!.path, isNot(outputs[1]!.path));
    expect(await outputs[0]!.readAsBytes(), [0, 2, 3]);
    expect(await outputs[1]!.readAsBytes(), [1, 2, 3]);
  });
}
