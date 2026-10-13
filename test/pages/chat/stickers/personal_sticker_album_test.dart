import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/stickers/chat_sticker_controller.dart';
import 'package:openim/pages/chat/stickers/personal_sticker_media_picker.dart';
import 'package:openim/pages/chat/stickers/personal_sticker_management_page.dart';
import 'package:openim/pages/chat/stickers/personal_sticker_store.dart';
import 'package:openim_common/openim_common.dart';
// Replaces the application's native temporary directory for conversion tests.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

class _MediaFile extends Fake implements File {
  _MediaFile(this.path, this.size);
  @override
  final String path;
  final int size;
  @override
  Future<int> length() async => size;
}

class _Asset extends AssetEntity {
  _Asset(String name, int size)
      : original = _MediaFile('/cache/$name', size),
        super(id: name, typeInt: 1, width: 20, height: 20);
  final File original;
  @override
  Future<File?> get originFile async => original;
}

class _AlbumPicker extends AssetPickerDelegate {
  late Future<List<AssetEntity>?> Function() select;
  final picks = <AssetPickerConfig>[];

  @override
  Future<List<AssetEntity>?> pickAssets(
    BuildContext context, {
    Key? key,
    AssetPickerConfig pickerConfig = const AssetPickerConfig(),
    PermissionRequestOption? permissionRequestOption,
    bool useRootNavigator = true,
    RouteSettings? pageRouteSettings,
    AssetPickerPageRouteBuilder<List<AssetEntity>>? pageRouteBuilder,
  }) {
    expect(context.mounted, isTrue);
    picks.add(pickerConfig);
    return select();
  }
}

class _Api extends PersonalStickerApi {
  final urls = <String>[];
  @override
  Future<({List<PersonalSticker> items, String? nextCursor})> page(
          {String? cursor, int limit = 50}) async =>
      (items: <PersonalSticker>[], nextCursor: null);
  @override
  Future<PersonalSticker> create(String mediaURL, String requestID) async {
    urls.add(mediaURL);
    return PersonalSticker.fromJson({
      'id': requestID,
      'mediaType': 'image',
      'mediaURL': mediaURL,
      'mimeType': 'image/png',
      'sizeBytes': 100,
      'width': 20,
      'height': 20,
      'sortOrder': 0,
      'version': 1,
      'createdAt': 1,
      'updatedAt': 1,
    });
  }
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

class _Compression extends UnsupportedFlutterImageCompress {
  int calls = 0;
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
    calls++;
    expect(format, CompressFormat.jpeg);
    await File(targetPath).writeAsBytes([1, 2, 3]);
    return XFile(targetPath);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _AlbumPicker picker;
  late List<MethodCall> uploads;
  late _Api api;
  late ChatStickerController controller;

  List<AssetEntity> media(String name, {int size = 100}) =>
      [_Asset(name, size)];

  void galleryTest(String description, Future<void> Function(WidgetTester) body,
      {Widget Function()? home}) {
    testWidgets(description, (tester) async {
      try {
        await tester
            .pumpWidget(GetMaterialApp(home: home?.call() ?? const SizedBox()));
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        Get.reset();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Future<void> login(String name) async {
    await DataSp.putLoginCertificate(LoginCertificate.fromJson(
        {'userID': name, 'chatToken': '$name-token'}));
  }

  setUp(() async {
    picker = _AlbumPicker();
    AssetPicker.setPickerDelegate(picker);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await login('first');
    uploads = [];
    picker.select = () async => media('photo.png');
    messenger.setMockMethodCallHandler(sdk, (call) async {
      expect(call.method, 'uploadFile');
      uploads.add(call);
      return {'url': 'https://example.test/sticker.png'};
    });
    api = _Api();
    controller = ChatStickerController(
      isClosed: () => false,
      sendingMuted: () => false,
      isInvalidGroup: () => false,
      sendMessage: (_) async {},
      closeToolbox: () {},
      stickerStore: PersonalStickerStore(api: api),
    );
  });

  tearDown(() {
    controller.close();
    AssetPicker.setPickerDelegate(const AssetPickerDelegate());
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(sdk, null);
  });

  galleryTest('management plus tile opens app album and updates the collection',
      (tester) async {
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('management-add-tile')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
    expect(picker.picks.single.maxAssets, 1);
    expect(picker.picks.single.requestType, RequestType.common);
    expect(api.urls, hasLength(1));
    expect(find.text('添加的单个表情 (1)'), findsOneWidget);
  },
      home: () => PersonalStickerManagementPage(
            store: controller.personalStickers,
            onAdd: controller.addPersonalSticker,
          ));

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    galleryTest('$platform opens app album and saves the selected photo',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.runAsync(controller.addPersonalSticker);
      expect(picker.picks.single.maxAssets, 1);
      expect(picker.picks.single.requestType, RequestType.common);
      expect(uploads.single.arguments['filePath'], '/cache/photo.png');
      expect(api.urls, ['https://example.test/sticker.png']);
      expect(
          controller.personalStickers.items.single.mediaURL, api.urls.single);
    });
  }

  galleryTest(
      'cancel leaves the collection unchanged and allows another attempt',
      (tester) async {
    picker.select = () async => null;
    await controller.addPersonalSticker();
    expect(uploads, isEmpty);
    expect(api.urls, isEmpty);
    picker.select = () async => media('photo.png');
    await tester.runAsync(controller.addPersonalSticker);
    expect(picker.picks, hasLength(2));
    expect(api.urls, hasLength(1));
  });

  galleryTest('double tap opens only one app album and uploads once',
      (tester) async {
    await tester.runAsync(() async {
      final pending = Completer<List<AssetEntity>?>();
      picker.select = () => pending.future;
      final first = controller.addPersonalSticker();
      await controller.addPersonalSticker();
      pending.complete(media('photo.png'));
      await first;
    });
    expect(picker.picks, hasLength(1));
    expect(uploads, hasLength(1));
    expect(api.urls, hasLength(1));
  });

  for (final close in [true, false]) {
    galleryTest(
        'late gallery result is ignored after ${close ? 'close' : 'account switch'}',
        (_) async {
      final pending = Completer<List<AssetEntity>?>();
      picker.select = () => pending.future;
      final add = controller.addPersonalSticker();
      if (close) {
        controller.close();
      } else {
        await login('second');
      }
      pending.complete(media('photo.png'));
      await add;
      expect(uploads, isEmpty);
      expect(api.urls, isEmpty);
    });
  }

  galleryTest('late upload cannot add an old photo to the new account',
      (tester) async {
    messenger.setMockMethodCallHandler(sdk, (_) async {
      await login('second');
      return {'url': 'https://example.test/old.png'};
    });
    await tester.runAsync(controller.addPersonalSticker);
    expect(api.urls, isEmpty);
  });

  galleryTest('GIF is kept intact and unsupported gallery media is rejected',
      (_) async {
    picker.select = () async => media('animation.GIF');
    final file = await pickPersonalStickerMedia(context: Get.context);
    expect(file!.path, '/cache/animation.GIF');
    picker.select = () async => media('movie.mov');
    await expectLater(
        pickPersonalStickerMedia(context: Get.context), throwsStateError);
  });

  galleryTest('HEIC conversion produces a JPEG with the converted upload size',
      (tester) async {
    await tester.runAsync(() async {
      final root =
          await Directory.systemTemp.createTemp('sticker-import-test-');
      final originalPaths = PathProviderPlatform.instance;
      final originalCompression = FlutterImageCompressPlatform.instance;
      final compression = _Compression();
      PathProviderPlatform.instance = _Paths(root.path);
      FlutterImageCompressPlatform.instance = compression;
      try {
        picker.select = () async => media('photo.HEIC');
        final file = await pickPersonalStickerMedia(context: Get.context);
        expect(file!.extension, 'jpg');
        expect(file.size, 3);
        expect(compression.calls, 1);
      } finally {
        PathProviderPlatform.instance = originalPaths;
        FlutterImageCompressPlatform.instance = originalCompression;
        await root.delete(recursive: true);
      }
    });
  });
}
