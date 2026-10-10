import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/composer/chat_composer_controller.dart';

import '../../../support/unicode/unicode_samples.dart';

class _Harness {
  _Harness({ComposerMemberPicker? picker}) {
    composer = ChatComposerController(
      conversationID: () => 'chat',
      currentUserID: () => 'self',
      isGroupChat: () => true,
      groupInfo: () => GroupInfo(groupID: 'group'),
      sendingMuted: () => false,
      sendMessage: (message) async => sent.add(message),
      persistDraft: (_, value) async => drafts.add(value),
      selectMembers: picker ?? (_, __) async => [],
      closeToolbox: () {},
      scrollBottom: () {},
      onTypingChanged: (_) {},
      showError: (_) {},
      createTextMessage: (value) async {
        compositions.add(value);
        return Message(clientMsgID: 'created');
      },
    );
    composer.initialize(null);
    addTearDown(() async {
      composer.dispose();
      await composer.pendingDraftWrites;
    });
  }
  late final ChatComposerController composer;
  final drafts = <String>[];
  final sent = <Message>[];
  final compositions = <ChatTextComposition>[];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final sample in unicodeSamples) {
    test('IME/draft/send preserve exact ${sample.name}', () async {
      final h = _Harness();
      final raw = '\n ${sample.text} \n';
      final composing = TextEditingValue(
        text: raw,
        selection: TextSelection.collapsed(offset: raw.length),
        composing: TextRange(start: 2, end: 2 + sample.text.length),
      );
      h.composer.inputCtrl.value = composing;
      expect(h.composer.inputCtrl.value, composing);
      await h.composer.saveDraft();
      final saved = h.drafts.last;
      expect(jsonDecode(saved)['text'], raw);
      h.composer.restoreDraft(saved);
      expect(h.composer.inputCtrl.text, raw);
      expect(h.composer.inputCtrl.selection.baseOffset, raw.length);
      final quote = Message.fromJson({
        'clientMsgID': 'quoted',
        'contentType': MessageType.text,
        'textElem': {'content': sample.text}
      });
      h.composer.replyToMessage(quote);
      await h.composer.sendTextMsg();
      expect(h.compositions.single.text, raw);
      expect(h.compositions.single.quote!.textElem!.content, sample.text);
    });
  }

  test(
      'mention insertion never splits a sequence and identity survives IME cancellation',
      () async {
    final h = _Harness();
    const cluster = '\u{1F469}\u{1F3FD}\u200D\u{1F4BB}';
    h.composer.inputCtrl.value = const TextEditingValue(
        text: 'A${cluster}B', selection: TextSelection.collapsed(offset: 3));
    h.composer.mentionMessageSender(
        Message(sendID: 'user', senderNickname: '群$cluster友'));
    expect(h.composer.inputCtrl.text, 'A$cluster@群$cluster友 B');
    final original = h.composer.inputCtrl.text;
    h.composer.inputCtrl.value = const TextEditingValue(
        text: '临时组合文本', composing: TextRange(start: 0, end: 6));
    expect(h.composer.mentions['user'], '群$cluster友');
    h.composer.inputCtrl.value = TextEditingValue(text: original);
    expect(h.composer.mentions['user'], '群$cluster友');
    await h.composer.sendTextMsg();
    expect(h.compositions.single.mentions.single.atUserID, 'user');
  });

  test('mention picker waits for IME commit and ignores changed input',
      () async {
    final selected = Completer<List<GroupMembersInfo>?>();
    var opened = 0;
    final h = _Harness(picker: (_, __) {
      opened++;
      return selected.future;
    });
    h.composer.inputCtrl.value = const TextEditingValue(
        text: '@',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1));
    expect(opened, 0);
    h.composer.inputCtrl.value =
        h.composer.inputCtrl.value.copyWith(composing: TextRange.empty);
    expect(opened, 1);
    const next = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}';
    h.composer.inputCtrl.text = next;
    selected.complete([GroupMembersInfo(userID: 'target', nickname: '成员')]);
    await Future<void>.delayed(Duration.zero);
    expect(h.composer.inputCtrl.text, next);
    expect(h.composer.mentions, isEmpty);
  });
}
