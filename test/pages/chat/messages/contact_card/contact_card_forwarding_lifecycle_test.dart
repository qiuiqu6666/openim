import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/messages/chat_delivery_controller.dart';
import 'package:openim/pages/chat/messages/forwarding/chat_forwarding_controller.dart';
import 'package:openim/pages/contacts/select_contacts/select_contacts_logic.dart';
import 'package:openim/services/favorite_send_coordinator.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sdkChannel = MethodChannel('flutter_openim_sdk');
const _target = 'im_contact-card-target';
const _account = '2138014845';

enum _Entry { card, recommendation }

Future<void> _login(String owner, String token) async {
  await DataSp.putLoginCertificate(LoginCertificate.fromJson({
    'userID': owner,
    'chatToken': token,
    'imToken': 'im-$token',
  }));
}

Future<void> _flush() async {
  for (var index = 0; index < 4; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _CardFixture {
  _CardFixture() {
    delivery = ChatDeliveryController(
      messageList: <Message>[].obs,
      accountID: 'owner-A',
      // Deliberately keep delivery active when only DataSp or SDK changes.
      // These tests must exercise the card operation's own captured guard.
      currentAccountID: () => 'owner-A',
      conversation: () => ConversationInfo(
          conversationID: 'current-chat', userID: 'current-peer'),
      isClosed: () => closed,
      groupStatus: () => null,
      scrollBottom: () {},
      resetInput: (_) {},
      sendRaw: (message, target) async {
        sends.add((message: message, target: target));
        return onSend == null ? receipt(message) : await onSend!(message);
      },
    );
    controller = ChatForwardingController(
      delivery: delivery,
      messages: () => [],
      isClosed: () => closed,
      isGroupChat: () => false,
      nickname: () => 'Current peer',
      faceUrl: () => 'https://example.test/peer.png',
      canForward: (_) => true,
      closeToolbox: () => toolboxCloses++,
      showToast: toasts.add,
      selectCardContacts: (
          {required action,
          sharedContact,
          cardRecipientName,
          cardRecipientFaceURL,
          cardRecipientIsGroup,
          ex}) async {
        pickerActions.add(action);
        if (action == SelAction.carte) {
          expect(cardRecipientName, 'Current peer');
          expect(cardRecipientFaceURL, 'https://example.test/peer.png');
          expect(cardRecipientIsGroup, isFalse);
        } else {
          expect(sharedContact?.userID, _target);
          expect(ex, '[${StrRes.carte}]Card friend');
        }
        return onPick == null ? selection(action) : await onPick!();
      },
      createCardExtension: (userID) async {
        extensionTargets.add(userID);
        return onExtension == null ? extension : await onExtension!();
      },
    );
  }

  final card = UserInfo(
      userID: _target,
      nickname: 'Card friend',
      faceURL: 'https://example.test/card.png');
  final toasts = <String>[];
  final pickerActions = <SelAction>[];
  final extensionTargets = <String>[];
  final nativeCalls = <MethodCall>[];
  final sends = <({Message message, FavoriteTarget target})>[];
  late final ChatDeliveryController delivery;
  late final ChatForwardingController controller;
  bool closed = false;
  String? remark;
  int toolboxCloses = 0, serial = 0;
  Future<dynamic> Function()? onPick;
  Future<String> Function()? onExtension;
  Future<Object?> Function(MethodCall)? onNative;
  Future<Message> Function(Message)? onSend;

  String get extension => jsonEncode({
        'inviteCode': 'fi_card',
        ...contactCardIdentityFields(_target, _account),
      });

  dynamic selection(SelAction action) => action == SelAction.carte
      ? card
      : {
          'checkedList': [
            UserInfo(userID: 'recipient-user'),
            GroupInfo(groupID: 'recipient-group')
          ],
          'customEx': remark,
        };

  Future<void> run(_Entry entry) => entry == _Entry.card
      ? controller.onTapCard()
      : controller.recommendFriendCarte(card);

  Message receipt(Message message) => Message.fromJson({
        ...message.toJson(),
        'status': MessageStatus.succeeded,
      });

  String nativeResult(MethodCall call) {
    final args = call.arguments as Map;
    return jsonEncode({
      'clientMsgID': 'card-operation-${++serial}',
      'sendID': 'owner-A',
      'status': MessageStatus.sending,
      'contentType': call.method == 'createCardMessage'
          ? MessageType.card
          : MessageType.text,
      if (call.method == 'createCardMessage') 'cardElem': args['cardMessage'],
      if (call.method == 'createTextMessage')
        'textElem': {'content': args['text']},
    });
  }

  Future<Object?> native(MethodCall call) async {
    nativeCalls.add(call);
    expect(call.method, anyOf('createCardMessage', 'createTextMessage'));
    return onNative == null ? nativeResult(call) : await onNative!(call);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _CardFixture fixture;
  late String previousSDKOwner;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // The SDK's owner is a late field until native login has completed.
  setUpAll(() => OpenIM.iMManager.userID = '');

  setUp(() async {
    Get.testMode = true;
    previousSDKOwner = OpenIM.iMManager.userID;
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await _login('owner-A', 'token-A');
    OpenIM.iMManager.userID = 'owner-A';
    fixture = _CardFixture();
    messenger.setMockMethodCallHandler(_sdkChannel, fixture.native);
  });
  tearDown(() async {
    fixture.delivery.close();
    messenger.setMockMethodCallHandler(_sdkChannel, null);
    OpenIM.iMManager.userID = previousSDKOwner;
    await DataSp.removeLoginCertificate();
    Get.reset();
  });

  for (final entry in _Entry.values) {
    for (final error in [(20201, 'risk limited'), (20020, 'too frequent')]) {
      test('$entry stops silently when the invitation is limited: $error',
          () async {
        fixture.onExtension = () async => throw error;
        await fixture.run(entry);
        expect(fixture.nativeCalls, isEmpty);
        expect(fixture.sends, isEmpty);
        expect(fixture.toasts, isEmpty);
        expect(fixture.extensionTargets, [_target]);
      });
    }
    for (final invalidation in ['closed', 'account', 'token', 'SDK']) {
      test(
          '$entry captures the login session before opening its picker: $invalidation',
          () async {
        final picker = Completer<dynamic>();
        fixture.onPick = () => picker.future;
        final pending = fixture.run(entry);
        await _flush();
        expect(fixture.pickerActions, hasLength(1));
        switch (invalidation) {
          case 'closed':
            fixture.closed = true;
          case 'account':
            await _login('owner-B', 'token-A');
          case 'token':
            await _login('owner-A', 'token-B');
          case 'SDK':
            OpenIM.iMManager.userID = 'owner-B';
        }
        picker.complete(fixture.selection(fixture.pickerActions.single));
        await pending;
        expect(fixture.extensionTargets, isEmpty);
        expect(fixture.nativeCalls, isEmpty);
        expect(fixture.sends, isEmpty);
        expect(fixture.toasts, isEmpty);
      });
    }

    for (final throws in [false, true]) {
      test(
          '$entry ignores a late extension ${throws ? 'error' : 'result'} after token change',
          () async {
        final extension = Completer<String>();
        fixture.onExtension = () => extension.future;
        final pending = fixture.run(entry);
        await _flush();
        expect(fixture.extensionTargets, [_target]);
        await _login('owner-A', 'token-B');
        if (throws) {
          extension.completeError(StateError('Invite failed after logout'));
        } else {
          extension.complete(fixture.extension);
        }
        await pending;
        expect(fixture.nativeCalls, isEmpty);
        expect(fixture.sends, isEmpty);
        expect(fixture.toasts, isEmpty);
      });

      test(
          '$entry ignores a late SDK card ${throws ? 'error' : 'result'} after closing',
          () async {
        final native = Completer<Object?>();
        fixture.onNative = (_) => native.future;
        final pending = fixture.run(entry);
        await _flush();
        expect(fixture.nativeCalls.map((call) => call.method),
            ['createCardMessage']);
        fixture.closed = true;
        if (throws) {
          native.completeError(PlatformException(code: 'CARD_BUILD_FAILED'));
        } else {
          native.complete(fixture.nativeResult(fixture.nativeCalls.single));
        }
        await pending;
        expect(fixture.sends, isEmpty);
        expect(fixture.toasts, isEmpty);
      });
    }

    for (final stage in ['picker', 'extension', 'SDK']) {
      test(
          '$entry catches a current-session $stage error and reports failure once',
          () async {
        switch (stage) {
          case 'picker':
            fixture.onPick = () async => throw StateError('Picker failed');
          case 'extension':
            fixture.onExtension = () async => throw StateError('Invite failed');
          case 'SDK':
            fixture.onNative =
                (_) async => throw PlatformException(code: 'CARD_BUILD_FAILED');
        }
        await fixture.run(entry);
        expect(fixture.sends, isEmpty);
        expect(fixture.toasts, [StrRes.sendFailed]);
      });
    }
  }

  test(
      'closing while a recommendation remark is built stops cards without an uncaught error',
      () async {
    fixture.remark = 'Please meet this friend';
    final native = Completer<Object?>();
    fixture.onNative = (_) => native.future;
    final pending = fixture.run(_Entry.recommendation);
    await _flush();
    expect(
        fixture.nativeCalls.map((call) => call.method), ['createTextMessage']);
    fixture.closed = true;
    native.completeError(PlatformException(code: 'TEXT_BUILD_FAILED'));
    await pending;
    expect(fixture.extensionTargets, isEmpty);
    expect(fixture.sends, isEmpty);
    expect(fixture.toasts, isEmpty);
  });

  for (final withRemark in [false, true]) {
    test(
        'recommendation awaits ${withRemark ? 'remark' : 'card'} delivery and stops the next operation on session change',
        () async {
      if (withRemark) {
        fixture.remark = 'Please meet this friend';
      }
      final send = Completer<Message>();
      fixture.onSend = (_) => send.future;
      var completed = false;
      final pending =
          fixture.run(_Entry.recommendation).then((_) => completed = true);
      await _flush();
      expect(fixture.sends, hasLength(1));
      expect(completed, isFalse);
      await _login('owner-B', 'token-B');
      send.complete(fixture.receipt(fixture.sends.single.message));
      await pending;
      expect(fixture.sends, hasLength(1));
      expect(fixture.nativeCalls, hasLength(1));
      expect(fixture.extensionTargets, withRemark ? isEmpty : [_target]);
      expect(fixture.toasts, isEmpty);
    });
  }

  test(
      'direct card keeps its SDK identity, display snapshot and original chat recipient',
      () async {
    await fixture.run(_Entry.card);
    expect(fixture.toolboxCloses, 1);
    expect(fixture.pickerActions, [SelAction.carte]);
    expect(fixture.extensionTargets, [_target]);
    final sent = fixture.sends.single;
    expect(sent.message.cardElem?.userID, _target);
    expect(contactCardAccount(_target, sent.message.cardElem?.ex), _account);
    expect(friendCardInviteCode(sent.message.cardElem?.ex), 'fi_card');
    expect(sent.target.userID, 'current-peer');
    expect(sent.target.groupID, isNull);
    expect(fixture.toasts, isEmpty);
  });

  test(
      'recommendation retains remark order and sends the original card to user and group',
      () async {
    fixture.remark = 'Please meet this friend';
    await fixture.run(_Entry.recommendation);
    expect(fixture.pickerActions, [SelAction.recommend]);
    expect(fixture.sends.map((send) => send.message.contentType), [
      MessageType.text,
      MessageType.card,
      MessageType.text,
      MessageType.card
    ]);
    expect(fixture.sends.take(2).map((send) => send.target.userID),
        everyElement('recipient-user'));
    expect(fixture.sends.skip(2).map((send) => send.target.groupID),
        everyElement('recipient-group'));
    for (final sent in fixture.sends
        .where((send) => send.message.contentType == MessageType.card)) {
      expect(sent.message.cardElem?.userID, _target);
      expect(contactCardAccount(_target, sent.message.cardElem?.ex), _account);
      expect(friendCardInviteCode(sent.message.cardElem?.ex), 'fi_card');
    }
    expect(fixture.toasts, isEmpty);
  });
}
