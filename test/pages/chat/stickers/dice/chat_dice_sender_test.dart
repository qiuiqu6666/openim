import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/messages/chat_delivery_controller.dart';
import 'package:openim/pages/chat/stickers/chat_sticker_controller.dart';
import 'package:openim/pages/chat/stickers/dice/chat_dice_sender.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

Message _dice(int value) => Message(
      clientMsgID: 'dice-$value',
      contentType: MessageType.custom,
      customElem: CustomElem(data: DiceMessageData(value: value).encode()),
    );

class _Fixture {
  _Fixture() {
    sender = ChatDiceSender(
      isClosed: () => closed,
      sendingMuted: () => muted,
      isInvalidGroup: () => invalidGroup,
      sessionKey: () => session,
      randomInt: (max) {
        expect(max, 6);
        rolls++;
        return randomValue;
      },
      createDice: (value) async {
        values.add(value);
        return await create?.call(value) ?? _dice(value);
      },
      sendMessage: (message) async {
        sent.add(message);
        await deliver?.call(message);
      },
    );
  }

  late final ChatDiceSender sender;
  Object? session = ('self', 'token');
  bool closed = false, muted = false, invalidGroup = false;
  int rolls = 0, randomValue = 3;
  final values = <int>[];
  final sent = <Message>[];
  Future<Message> Function(int)? create;
  Future<void> Function(Message)? deliver;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rolls only once and serializes the result before delivery', () async {
    final f = _Fixture();
    await f.sender.send();
    expect(f.rolls, 1);
    expect(f.values, [4]);
    final persisted = Message.fromJson(f.sent.single.toJson());
    expect(DiceMessageData.tryParse(persisted.customElem!.data)!.value, 4);
    expect(f.rolls, 1);
  });

  test('failed message retry reuses its SDK ID and fixed result', () async {
    final timeline = <Message>[].obs;
    final attempts = <({String? id, String? data})>[];
    var resets = 0, rolls = 0;
    final delivery = ChatDeliveryController(
      messageList: timeline,
      conversation: () => ConversationInfo(
        conversationID: 'single_peer',
        userID: 'peer',
      ),
      isClosed: () => false,
      groupStatus: () => null,
      scrollBottom: () {},
      resetInput: (_) => resets++,
      accountID: 'self',
      currentAccountID: () => 'self',
      sendRaw: (message, target) async {
        attempts.add((id: message.clientMsgID, data: message.customElem?.data));
        expect(target.userID, 'peer');
        if (attempts.length == 1) throw StateError('offline');
        return Message.fromJson(message.toJson())
          ..status = MessageStatus.succeeded;
      },
    );
    addTearDown(delivery.close);
    final sender = ChatDiceSender(
      isClosed: () => false,
      sendingMuted: () => false,
      isInvalidGroup: () => false,
      sessionKey: () => ('self', 'token'),
      randomInt: (_) {
        rolls++;
        return 4;
      },
      createDice: (value) async => _dice(value),
      sendMessage: (message) => delivery.send(message, resetInput: false),
    );
    addTearDown(sender.close);
    await sender.send();
    expect(timeline.single.status, MessageStatus.failed);
    final persisted = timeline.single;
    await delivery.send(persisted, addToUI: false, resetInput: false);
    expect(persisted.status, MessageStatus.succeeded);
    expect(attempts, hasLength(2));
    expect(attempts.first, attempts.last);
    expect(DiceMessageData.tryParse(attempts.last.data)!.value, 5);
    expect(rolls, 1);
    expect(resets, 0);
    expect(timeline, hasLength(1));
  });

  for (final phase in ['creation', 'delivery']) {
    test('double taps during $phase share one roll and operation', () async {
      final f = _Fixture();
      final gate = Completer<void>();
      final entered = Completer<void>();
      if (phase == 'creation') {
        f.create = (value) async {
          entered.complete();
          await gate.future;
          return _dice(value);
        };
      } else {
        f.deliver = (_) async {
          entered.complete();
          await gate.future;
        };
      }
      final first = f.sender.send();
      await entered.future;
      final repeated = f.sender.send();
      expect(repeated, same(first));
      expect(f.rolls, 1);
      expect(f.values, [4]);
      gate.complete();
      await Future.wait([first, repeated]);
      expect(f.sent, hasLength(1));
    });
  }

  test('separate completed sends can generate a new roll', () async {
    final f = _Fixture();
    await f.sender.send();
    f.randomValue = 0;
    await f.sender.send();
    expect(f.rolls, 2);
    expect(f.values, [4, 1]);
    expect(f.sent, hasLength(2));
  });

  for (final reason in [
    'muted',
    'left group',
    'closed',
    'account',
    'logged out'
  ]) {
    test('$reason at entry does not roll, create or send', () async {
      final f = _Fixture();
      switch (reason) {
        case 'muted':
          f.muted = true;
        case 'left group':
          f.invalidGroup = true;
        case 'closed':
          f.closed = true;
        case 'account':
          f.session = ('other', 'token');
        case 'logged out':
          f.session = null;
      }
      await f.sender.send();
      expect(f.rolls, 0);
      expect(f.values, isEmpty);
      expect(f.sent, isEmpty);
    });

    test('$reason during SDK creation cancels delivery quietly', () async {
      final f = _Fixture();
      final gate = Completer<Message>();
      final entered = Completer<void>();
      f.create = (_) {
        entered.complete();
        return gate.future;
      };
      final work = f.sender.send();
      await entered.future;
      switch (reason) {
        case 'muted':
          f.muted = true;
        case 'left group':
          f.invalidGroup = true;
        case 'closed':
          f.sender.close();
        case 'account':
          f.session = ('self', 'new token');
        case 'logged out':
          f.session = null;
      }
      gate.complete(_dice(4));
      await work;
      expect(f.rolls, 1);
      expect(f.sent, isEmpty);
    });
  }

  test('an ownerless sender cannot acquire a later login', () async {
    Object? session;
    final sender = ChatDiceSender(
      isClosed: () => false,
      sendingMuted: () => false,
      isInvalidGroup: () => false,
      sessionKey: () => session,
      sendMessage: (_) async => fail('must not send'),
      randomInt: (_) => throw StateError('must not roll'),
      createDice: (_) async => throw StateError('must not create'),
    );
    session = ('self', 'later login');
    await sender.send();
  });

  for (final invalid in [-1, 6]) {
    test('invalid random index $invalid never reaches SDK creation', () async {
      final f = _Fixture()..randomValue = invalid;
      await expectLater(f.sender.send(), throwsFormatException);
      expect(f.values, isEmpty);
      expect(f.sent, isEmpty);
    });
  }

  test('creation failure reports a friendly error and releases the tap guard',
      () async {
    final f = _Fixture();
    f.create = (_) async => throw StateError('private SDK detail');
    await expectLater(
      f.sender.send(),
      throwsA(isA<FormatException>().having(
        (error) => error.message,
        'friendly error',
        '表情发送失败，请重试',
      )),
    );
    expect(f.sent, isEmpty);
    f.create = null;
    await f.sender.send();
    expect(f.sent, hasLength(1));
  });

  test('late failures after close stay quiet', () async {
    final f = _Fixture();
    final gate = Completer<Message>();
    f.create = (_) => gate.future;
    final work = f.sender.send();
    f.sender.close();
    gate.completeError(StateError('private SDK detail'));
    await work;
    expect(f.sent, isEmpty);
  });

  test(
      'default controller creates custom dice without upload or draft callback',
      () async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'self',
      'chatToken': 'chat-token',
      'imToken': 'im-token',
    }));
    OpenIM.iMManager.userID = 'self';
    OpenIM.iMManager.token = 'im-token';
    Get.addTranslations(TranslationService().keys);
    Get.locale = const Locale('zh', 'CN');
    addTearDown(Get.reset);
    const channel = MethodChannel('flutter_openim_sdk');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      expect(call.method, 'createCustomMessage');
      final data = (call.arguments as Map)['data'] as String;
      final dice = DiceMessageData.tryParse(data)!;
      expect(dice.value, inInclusiveRange(1, 6));
      return jsonEncode(_dice(dice.value).toJson());
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    var personalSends = 0, draftPreservingSends = 0, panelCloses = 0;
    final controller = ChatStickerController(
      isClosed: () => false,
      sendingMuted: () => false,
      isInvalidGroup: () => false,
      sendMessage: (_) async => personalSends++,
      sendBuiltinMessage: (message) async {
        draftPreservingSends++;
        expect(message.isDiceType, isTrue);
        expect(ChatStickerController.messageStickerURL(message), isNull);
      },
      closeToolbox: () => panelCloses++,
    );
    addTearDown(controller.close);
    await controller.sendDice();
    expect(methods, ['createCustomMessage']);
    expect(personalSends, 0);
    expect(draftPreservingSends, 1);
    expect(panelCloses, 0);
    controller.close();
    await controller.sendDice();
    expect(methods, hasLength(1));
  });
}
