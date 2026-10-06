import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

Message _custom(String? data, {int type = MessageType.custom}) => Message(
      contentType: type,
      customElem: CustomElem(data: data),
    );

String _envelope(Object? value, {Object? version = 1, Object? type = 906}) =>
    jsonEncode({
      'customType': type,
      'data': {'version': version, 'value': value},
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Get.addTranslations(TranslationService().keys);
    Get.locale = const Locale('zh', 'CN');
  });
  tearDown(Get.reset);

  test('each fixed result survives the SDK JSON round trip', () {
    expect(CustomMessageType.dice, 906);
    for (var value = 1; value <= 6; value++) {
      final dice = DiceMessageData(value: value);
      expect(dice.toJson(), {
        'customType': 906,
        'data': {'version': 1, 'value': value},
      });
      final message = Message.fromJson(_custom(dice.encode()).toJson());
      expect(message.isDiceType, isTrue);
      expect(message.isEmojiType, isFalse);
      expect(DiceMessageData.tryParse(message.customElem!.data)!.value, value);
      expect(IMUtils.parseMsg(message), '[骰子] $value点');
      expect(IMUtils.parseCustomMessage(message), {
        'viewType': 906,
        'version': 1,
        'value': value,
      });
    }
  });

  test('invalid outgoing values are rejected before encoding', () {
    for (final value in [-1, 0, 7, 100]) {
      expect(() => DiceMessageData(value: value), throwsRangeError);
    }
  });

  test('invalid incoming data never invents a random result', () {
    for (final data in <String?>[
      null,
      '',
      'not json',
      'null',
      '[]',
      '4',
      jsonEncode({'value': 4, 'version': 1}),
      jsonEncode({'customType': 906}),
      jsonEncode({'customType': 906, 'data': 4}),
      _envelope(null),
      _envelope(0),
      _envelope(7),
      _envelope('4'),
      _envelope(4.0),
      _envelope(4, version: null),
      _envelope(4, version: '1'),
      _envelope(4, version: 1.0),
      _envelope(4, version: 2),
      _envelope(4, type: 902),
      _envelope(4, type: '906'),
      _envelope(4, type: 906.0),
    ]) {
      expect(DiceMessageData.tryParse(data), isNull, reason: '$data');
    }
  });

  test('malformed dice keeps a safe label without a made-up point', () {
    for (final data in [_envelope(9), _envelope(3, version: 2)]) {
      final message = _custom(data);
      expect(message.isDiceType, isTrue);
      expect(IMUtils.parseMsg(message), '[骰子]');
      expect(IMUtils.parseCustomMessage(message), {'viewType': 906});
    }
    expect(_custom('{').isDiceType, isFalse);
    expect(_custom(_envelope(4), type: MessageType.customFace).isDiceType,
        isFalse);
    expect(_custom(_envelope(4, type: '906')).isDiceType, isFalse);
    expect(_custom(_envelope(4, type: 906.0)).isDiceType, isFalse);
  });

  test('English summary and existing emoji summaries remain distinct',
      () async {
    Get.locale = const Locale('en', 'US');
    expect(IMUtils.parseMsg(_custom(_envelope(6))), '[Dice] 6 points');
    final emoji = _custom(jsonEncode({
      'customType': CustomMessageType.emoji,
      'data': {'url': 'https://sticker.test/existing.png'},
    }));
    expect(emoji.isDiceType, isFalse);
    expect(emoji.isEmojiType, isTrue);
    expect(IMUtils.parseMsg(emoji), '[${StrRes.emoji}]');
    expect(IMUtils.parseMsg(Message(contentType: MessageType.customFace)),
        '[${StrRes.emoji}]');
  });

  test('SDK custom message creation sends the persisted point and description',
      () async {
    const channel = MethodChannel('flutter_openim_sdk');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      expect(call.method, 'createCustomMessage');
      final arguments = call.arguments as Map;
      expect(arguments['extension'], '');
      expect(arguments['description'], '[骰子] 4点');
      final data = arguments['data'] as String;
      expect(DiceMessageData.tryParse(data)!.value, 4);
      return jsonEncode(_custom(data).toJson());
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final message =
        await OpenIM.iMManager.messageManager.createDiceMessage(value: 4);
    expect(DiceMessageData.tryParse(message.customElem!.data)!.value, 4);
    expect(calls, hasLength(1));
    expect(() => OpenIM.iMManager.messageManager.createDiceMessage(value: 7),
        throwsRangeError);
    expect(calls, hasLength(1));
  });
}
