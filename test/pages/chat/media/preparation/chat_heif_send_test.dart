import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/media/chat_media_controller.dart';
import 'package:openim_common/openim_common.dart';
import 'package:package_info_plus/package_info_plus.dart';
// Uses the same platform contract as the shared compression helper.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

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
    expect(format, CompressFormat.jpeg);
    expect(targetPath, endsWith('.jpg'));
    await File(targetPath).writeAsBytes([0xff, 0xd8, 0xff]);
    return XFile(targetPath);
  }
}

class _Asset extends AssetEntity {
  const _Asset(this.source)
      : super(id: 'heif-photo', typeInt: 1, width: 10, height: 10);
  final File source;
  @override
  Future<File?> get file async => source;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdkChannel = MethodChannel('flutter_openim_sdk');
  setUpAll(() async {
    PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1',
        buildNumber: '1',
        buildSignature: '');
    await Config.init(() {});
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final extension in ['HEIC', 'heif']) {
      test('$platform $extension reaches SDK creation and upload as JPEG',
          () async {
        debugDefaultTargetPlatformOverride = platform;
        final root = await Directory.systemTemp.createTemp('chat-heif-');
        final oldPaths = PathProviderPlatform.instance;
        final oldCompression = FlutterImageCompressPlatform.instance;
        PathProviderPlatform.instance = _Paths(root.path);
        FlutterImageCompressPlatform.instance = _Compression();
        Config.cachePath = root.path;
        var sdkCreates = 0;
        var uploads = 0;
        final staged = <Message>[];
        final sent = <Message>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(sdkChannel, (call) async {
          if (call.method == 'createImageMessageFromFullPath') {
            sdkCreates++;
            final path = (call.arguments as Map)['imagePath'] as String;
            expect(path, endsWith('.jpg'));
            expect(await File(path).readAsBytes(), [0xff, 0xd8, 0xff]);
            return jsonEncode(Message(
                    clientMsgID: 'sdk-image',
                    contentType: MessageType.picture,
                    status: MessageStatus.sending,
                    pictureElem: PictureElem(
                        sourcePath: path,
                        sourcePicture: PictureInfo(
                            type: 'image/jpeg', width: 10, height: 10)))
                .toJson());
          }
          expect(call.method, 'uploadFile');
          uploads++;
          expect((call.arguments as Map)['contentType'], 'image/jpeg');
          return jsonEncode({'url': 'https://media.test/photo.jpg'});
        });
        final photo = await File('${root.path}/photo.$extension')
            .writeAsBytes([0, 0, 0, 24, 102, 116, 121, 112]);
        final media = ChatMediaController(
      chooseOriginal: () async => false,
            conversationID: () => 'chat',
            isClosed: () => false,
            sendingMuted: () => false,
            isInvalidGroup: () => false,
            voiceBusy: () => false,
            sendMessage: (message, {addToUI = true, resetInput = true}) async =>
                sent.add(message),
            stageMessage: staged.add,
            previewVoice: (_, __) async {},
            closeToolbox: () {},
            pickAssets: () async => [_Asset(photo)],
            onPreparationFailed: () => fail('HEIF preparation failed'));
        addTearDown(() async {
          media.close();
          debugDefaultTargetPlatformOverride = null;
          PathProviderPlatform.instance = oldPaths;
          FlutterImageCompressPlatform.instance = oldCompression;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(sdkChannel, null);
          await root.delete(recursive: true);
        });
        await media.onTapAlbum();
        expect(sdkCreates, 1);
        expect(uploads, 1);
        expect(staged.single.clientMsgID, 'sdk-image');
        expect(sent.single, staged.single);
      });
    }
  }
}
