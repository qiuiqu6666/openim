import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/stickers/builtin/chat_builtin_sticker.dart';
import 'package:openim/pages/chat/stickers/builtin/chat_builtin_sticker_sender.dart';
import 'package:openim/pages/chat/stickers/chat_sticker_controller.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _url = 'https://sticker.test/object/99chat.png?signature=fresh';
final _sticker = ChatBuiltinStickerCatalog.stickers.first;

ByteData _bytes() => ByteData.sublistView(Uint8List.fromList([4, 5, 6]));

Message _face(String data) => Message(
      clientMsgID: 'face',
      contentType: MessageType.customFace,
      status: MessageStatus.succeeded,
      faceElem: FaceElem(index: -1, data: data),
    );

class _Bundle extends CachingAssetBundle {
  final keys = <String>[];
  Future<ByteData> Function()? loader;

  @override
  Future<ByteData> load(String key) {
    keys.add(key);
    return loader?.call() ?? Future.value(_bytes());
  }
}

class _Fixture {
  _Fixture(this.directory) {
    sender = ChatBuiltinStickerSender(
      isClosed: () => closed,
      sendingMuted: () => muted,
      isInvalidGroup: () => invalidGroup,
      sendMessage: (message) async {
        sent.add(message);
        await delivery?.call();
      },
      bundle: bundle,
      cacheDirectory: () async => directory,
      upload: ({required id, required filePath, required fileName}) async {
        uploads.add((id: id, path: filePath, name: fileName));
        uploadedBytes.add(await File(filePath).readAsBytes());
        return await upload?.call() ?? {'url': _url};
      },
      createFace: (data) async {
        faceData.add(data);
        return await createFace?.call(data) ?? _face(data);
      },
      warmImage: ({required url, required bytes}) async {
        warmed.add((url: url, bytes: bytes.toList()));
        await warmImage?.call();
      },
      sessionKey: () => session,
    );
  }

  final Directory directory;
  final bundle = _Bundle();
  late final ChatBuiltinStickerSender sender;
  final uploads = <({String id, String path, String name})>[];
  final uploadedBytes = <List<int>>[];
  final faceData = <String>[];
  final sent = <Message>[];
  final warmed = <({String url, List<int> bytes})>[];
  Future<Object?> Function()? upload;
  Future<Message> Function(String)? createFace;
  Future<void> Function()? delivery;
  Future<void> Function()? warmImage;
  Object? session = ('self', 'original-token');
  bool closed = false, muted = false, invalidGroup = false;

  Future<void> expectNoTemporaryFiles() async {
    expect(await directory.list().toList(), isEmpty);
  }
}

Future<_Fixture> _fixture() async {
  final directory = await Directory.systemTemp.createTemp('openim-builtin-');
  final fixture = _Fixture(directory);
  addTearDown(() async {
    fixture.sender.close();
    final resolved = directory.absolute.path;
    final prefix =
        '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}openim-builtin-';
    if (!resolved.startsWith(prefix)) {
      throw StateError('Unexpected test directory: $resolved');
    }
    if (await directory.exists()) await directory.delete(recursive: true);
  });
  return fixture;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('uploads actual asset bytes then delivers a collectable URL face',
      () async {
    final f = await _fixture();
    final padded = Uint8List.fromList([99, 4, 5, 6, 88]);
    f.bundle.loader = () async => ByteData.view(padded.buffer, 1, 3);
    f.upload = () async => jsonEncode({'url': ' $_url '});
    await f.sender.send(_sticker);

    expect(f.bundle.keys, [_sticker.assetPath]);
    expect(f.uploadedBytes.single, [4, 5, 6]);
    expect(f.warmed.single.url, _url);
    expect(f.warmed.single.bytes, [4, 5, 6]);
    expect(f.uploads.single.name, _sticker.fileName);
    expect(f.uploads.single.id, isNotEmpty);
    expect(f.uploads.single.path, startsWith(f.directory.path));
    final payload = StickerImageData.tryParse(f.faceData.single)!;
    expect(payload.url, _url);
    expect(payload.width, _sticker.width);
    expect(payload.height, _sticker.height);
    expect(f.faceData.single, isNot(contains(_sticker.assetPath)));
    final received = Message.fromJson(f.sent.single.toJson());
    expect(ChatStickerController.messageStickerURL(received), _url);
    await f.expectNoTemporaryFiles();
  });

  test('deduplicates pending clicks and gets a fresh URL for the next send',
      () async {
    final f = await _fixture();
    final gate = Completer<Object?>();
    final entered = Completer<void>();
    f.upload = () {
      entered.complete();
      return gate.future;
    };
    final first = f.sender.send(_sticker);
    final repeated = f.sender.send(_sticker);
    expect(repeated, same(first));
    await entered.future;
    expect(f.uploads, hasLength(1));
    gate.complete({'url': _url});
    await Future.wait([first, repeated]);
    f.upload = () async => {'url': 'https://sticker.test/object/fresh.png'};
    await f.sender.send(_sticker);
    expect(f.uploads, hasLength(2));
    expect(f.uploads.map((call) => call.path).toSet(), hasLength(2));
    expect(f.uploads.map((call) => call.id).toSet(), hasLength(2));
    expect(f.sent, hasLength(2));
    expect(StickerImageData.tryParse(f.faceData.last)!.url,
        'https://sticker.test/object/fresh.png');
    await f.expectNoTemporaryFiles();
  });

  for (final response in <Object?>[
    {'url': 'file:///private/local.png'},
    {'url': _sticker.assetPath},
    {'url': 'https:'},
    {'url': '  '},
    {'url': 1},
    {
      'data': {'url': _url}
    },
    'not json',
    null,
  ]) {
    test('rejects an unusable upload response: $response', () async {
      final f = await _fixture();
      // Null is itself an invalid SDK response, rather than the fixture default.
      f.upload = () async => response;
      final sender = ChatBuiltinStickerSender(
        isClosed: () => false,
        sendingMuted: () => false,
        isInvalidGroup: () => false,
        sendMessage: (message) async => f.sent.add(message),
        bundle: f.bundle,
        cacheDirectory: () async => f.directory,
        sessionKey: () => 'self',
        upload: ({required id, required filePath, required fileName}) async =>
            response,
        createFace: (data) async {
          f.faceData.add(data);
          return _face(data);
        },
      );
      await expectLater(sender.send(_sticker), throwsFormatException);
      expect(f.faceData, isEmpty);
      expect(f.sent, isEmpty);
      await f.expectNoTemporaryFiles();
    });
  }

  test('unregistered assets and empty bytes never reach the SDK', () async {
    final f = await _fixture();
    await expectLater(
        f.sender.send(ChatBuiltinSticker(
          id: _sticker.id,
          fileName: '../outside.png',
          label: 'other',
        )),
        throwsFormatException);
    expect(f.bundle.keys, isEmpty);
    f.bundle.loader = () async => ByteData(0);
    await expectLater(f.sender.send(_sticker), throwsFormatException);
    expect(f.uploads, isEmpty);
    expect(f.sent, isEmpty);
    await f.expectNoTemporaryFiles();
  });

  for (final phase in ['asset', 'upload', 'warm', 'face']) {
    for (final reason in ['account', 'closed', 'muted', 'left group']) {
      test('$reason during $phase cancels the old operation quietly', () async {
        final f = await _fixture();
        final entered = Completer<void>();
        final gate = Completer<void>();
        Future<void> wait() {
          entered.complete();
          return gate.future;
        }

        if (phase == 'asset') {
          f.bundle.loader = () async {
            await wait();
            return _bytes();
          };
        } else if (phase == 'upload') {
          f.upload = () async {
            await wait();
            return {'url': _url};
          };
        } else if (phase == 'warm') {
          f.warmImage = wait;
        } else {
          f.createFace = (data) async {
            await wait();
            return _face(data);
          };
        }
        final pending = f.sender.send(_sticker);
        await entered.future;
        switch (reason) {
          case 'account':
            f.session = ('self', 'replacement-token');
          case 'closed':
            f.sender.close();
          case 'muted':
            f.muted = true;
          case 'left group':
            f.invalidGroup = true;
        }
        gate.complete();
        await pending;
        expect(f.sent, isEmpty);
        expect(f.uploads, hasLength(phase == 'asset' ? 0 : 1));
        expect(f.faceData, hasLength(phase == 'face' ? 1 : 0));
        await f.expectNoTemporaryFiles();
      });
    }
  }

  test('cache warm-up failure preserves ordinary URL delivery', () async {
    final f = await _fixture();
    f.warmImage = () async => throw StateError('image cache unavailable');
    await f.sender.send(_sticker);
    expect(f.sent, hasLength(1));
    expect(ChatStickerController.messageStickerURL(f.sent.single), _url);
    await f.expectNoTemporaryFiles();
  });

  test('stale failures stay quiet; active failures permit retry', () async {
    final f = await _fixture();
    final entered = Completer<void>();
    final gate = Completer<Object?>();
    f.upload = () {
      entered.complete();
      return gate.future;
    };
    final pending = f.sender.send(_sticker);
    await entered.future;
    f.closed = true;
    gate.completeError(StateError('server detail'));
    await pending;
    expect(f.sent, isEmpty);
    await f.expectNoTemporaryFiles();

    final retry = await _fixture();
    retry.upload = () async => throw StateError('private server detail');
    await expectLater(
      retry.sender.send(_sticker),
      throwsA(isA<FormatException>().having(
        (error) => error.message,
        'friendly error',
        '表情发送失败，请重试',
      )),
    );
    retry.upload = () async => {'url': _url};
    await retry.sender.send(_sticker);
    expect(retry.sent, hasLength(1));
    await retry.expectNoTemporaryFiles();
  });

  test('blocked entry does no IO and a new click after unmute can send',
      () async {
    final f = await _fixture();
    f.muted = true;
    await f.sender.send(_sticker);
    expect(f.bundle.keys, isEmpty);
    f.muted = false;
    await f.sender.send(_sticker);
    expect(f.sent, hasLength(1));
    await f.expectNoTemporaryFiles();
  });

  test(
      'default SDK integration uploads bundled PNG and preserves builtin callback',
      () async {
    final f = await _fixture();
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'self',
      'chatToken': 'chat-token',
      'imToken': 'im-token',
    }));
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.token = 'im-token';
    Config.cachePath = f.directory.path;
    final methods = <String>[];
    final uploadedFiles = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      final args = call.arguments as Map;
      if (call.method == 'uploadFile') {
        expect(args['name'], _sticker.fileName);
        expect(args['contentType'], 'image/png');
        final file = File(args['filePath'] as String);
        uploadedFiles.add(file.path);
        // Actual bundled asset, including its PNG header, reaches uploadFile.
        expect((await file.readAsBytes()).take(8),
            [137, 80, 78, 71, 13, 10, 26, 10]);
        return jsonEncode({'url': _url});
      }
      if (call.method == 'createFaceMessage') {
        expect(args['index'], -1);
        final data = args['data'] as String;
        final payload = StickerImageData.tryParse(data)!;
        expect(payload.url, _url);
        expect(payload.width, 240);
        expect(payload.height, 240);
        return jsonEncode(_face(data).toJson());
      }
      throw StateError('Unexpected SDK call ${call.method}');
    });
    var personalSends = 0, builtinSends = 0, panelCloses = 0;
    final controller = ChatStickerController(
      isClosed: () => false,
      sendingMuted: () => false,
      isInvalidGroup: () => false,
      sendMessage: (_) async => personalSends++,
      sendBuiltinMessage: (message) async {
        builtinSends++;
        expect(ChatStickerController.messageStickerURL(message), _url);
      },
      closeToolbox: () => panelCloses++,
    );
    addTearDown(controller.close);
    await controller.sendBuiltinSticker(_sticker);
    expect(methods, ['uploadFile', 'createFaceMessage']);
    expect(personalSends, 0);
    expect(builtinSends, 1);
    expect(panelCloses, 0);
    expect(await File(uploadedFiles.single).exists(), isFalse);
  });
}
