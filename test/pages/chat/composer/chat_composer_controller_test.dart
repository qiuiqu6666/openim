import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/composer/chat_composer_controller.dart';

class _ComposerHarness {
  _ComposerHarness({
    this.group = false,
    Future<void> Function(String, String)? persist,
    ComposerMemberPicker? picker,
    Future<Message> Function(ChatTextComposition)? createText,
    Future<FormattedTextResult?> Function(String)? editor,
    Future<Message> Function(FormattedTextResult, Message?)? createFormatted,
    Future<void> Function(Message)? transport,
    bool Function()? inactive,
  }) {
    composer = ChatComposerController(
      conversationID: () => 'conversation',
      currentUserID: () => 'me',
      isGroupChat: () => group,
      groupInfo: () => group ? GroupInfo(groupID: 'group') : null,
      sendingMuted: () => muted,
      persistDraft: persist ?? (id, draft) async => drafts.add((id, draft)),
      selectMembers: picker ?? (_, __) async => [],
      closeToolbox: () => toolboxClosed++,
      scrollBottom: () {},
      onTypingChanged: typing.add,
      showError: errors.add,
      reportDraftError: draftErrors.add,
      isSessionInactive: inactive,
      createTextMessage: createText ??
          (composition) async {
            compositions.add(composition);
            return Message()
              ..clientMsgID = 'composed'
              ..contentType = composition.mentions.isEmpty
                  ? MessageType.text
                  : MessageType.atText;
          },
      editFormattedText: editor,
      createFormattedMessage: createFormatted,
      sendMessage: (message) async {
        sent.add(message);
        composer.resetAfterSend(message);
        if (transport != null) await transport(message);
      },
    );
  }

  final bool group;
  bool muted = false;
  int toolboxClosed = 0;
  final drafts = <(String, String)>[];
  final typing = <bool>[];
  final errors = <String>[];
  final draftErrors = <Object>[];
  final compositions = <ChatTextComposition>[];
  final sent = <Message>[];
  late final ChatComposerController composer;

  Future<void> close() async {
    composer.dispose();
    await composer.pendingDraftWrites;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('draft writes serialize snapshots and continue after a failed write',
      () async {
    final first = Completer<void>();
    final writes = <(String, String)>[];
    final h = _ComposerHarness(persist: (id, draft) {
      writes.add((id, draft));
      return writes.length == 1 ? first.future : Future<void>.value();
    });
    h.composer.initialize('legacy plain draft');
    expect(h.composer.inputCtrl.text, 'legacy plain draft');
    expect(h.typing, isEmpty);
    h.composer.inputCtrl.text = 'first';
    unawaited(h.composer.saveDraft());
    h.composer.inputCtrl.text = 'second';
    final saved = h.composer.saveDraft();
    await Future<void>.delayed(Duration.zero);
    expect(writes, hasLength(1));
    expect(jsonDecode(writes.single.$2)['text'], 'first');
    first.completeError(StateError('temporary database failure'));
    await saved;
    expect(writes.map((entry) => jsonDecode(entry.$2)['text']),
        ['first', 'second']);
    expect(h.draftErrors, hasLength(1));
    await h.close();
  });

  testWidgets('dispose saves the final draft once and cancels pending timers',
      (tester) async {
    final h = _ComposerHarness();
    h.composer.initialize(null);
    h.composer.inputCtrl.text = 'unsaved input';
    h.composer.dispose();
    h.composer.dispose();
    await tester.pump(const Duration(seconds: 2));
    await h.composer.pendingDraftWrites;
    expect(h.drafts, hasLength(1));
    expect(jsonDecode(h.drafts.single.$2)['text'], 'unsaved input');
    expect(h.typing, [true, false]);
    expect(h.composer.isClosed, isTrue);
  });

  test(
      'mention insertion keeps user identity and quote when composing a message',
      () async {
    final h = _ComposerHarness(group: true);
    h.composer.initialize('hello world');
    h.composer.inputCtrl.selection =
        const TextSelection(baseOffset: 6, extentOffset: 11);
    final sender = Message()
      ..sendID = 'member-42'
      ..senderNickname = ' Alice ';
    h.composer.mentionMessageSender(sender);
    expect(h.composer.inputCtrl.text, 'hello @Alice ');
    expect(h.composer.mentions, {'member-42': 'Alice'});
    expect(h.toolboxClosed, 1);
    final quote = Message()..clientMsgID = 'quoted';
    h.composer.replyToMessage(quote);
    await h.composer.sendTextMsg();
    expect(h.compositions.single.mentions.single.atUserID, 'member-42');
    expect(h.compositions.single.mentions.single.groupNickname, 'Alice');
    expect(h.compositions.single.quote, same(quote));
    expect(h.composer.quotedMessage.value, isNull);
    expect(h.composer.inputCtrl.text, isEmpty);
    expect(h.composer.mentions, isEmpty);
    await h.close();
    expect(h.drafts.last.$2, '');
  });

  test('editing away a mention removes its hidden recipient', () async {
    final h = _ComposerHarness(group: true);
    h.composer.initialize(jsonEncode({
      'text': '@Alice hi',
      'mentions': {'alice': 'Alice'}
    }));
    h.composer.inputCtrl.text = 'ordinary text';
    await h.composer.sendTextMsg();
    expect(h.compositions.single.mentions, isEmpty);
    await h.close();
  });

  test('member picker completion after disposal cannot change input or focus',
      () async {
    final selection = Completer<List<GroupMembersInfo>?>();
    final h =
        _ComposerHarness(group: true, picker: (_, __) => selection.future);
    h.composer.initialize('@');
    final pending = h.composer.selectMentions(0);
    h.composer.dispose();
    selection.complete([GroupMembersInfo(userID: 'alice', nickname: 'Alice')]);
    await pending;
    await h.composer.pendingDraftWrites;
    expect(h.errors, isEmpty);
    expect(h.composer.mentions, isEmpty);
  });

  test('message creation completion after leaving cannot send to the old route',
      () async {
    final created = Completer<Message>();
    final h = _ComposerHarness(createText: (_) => created.future);
    h.composer.initialize('hello');
    final pending = h.composer.sendTextMsg();
    h.composer.dispose();
    created.complete(Message()..contentType = MessageType.text);
    await pending;
    await h.composer.pendingDraftWrites;
    expect(h.sent, isEmpty);
  });

  test('formatted composition preserves entities and the original quote',
      () async {
    final result = (
      text: 'bold',
      entities: [RichMessageInfo(type: 'bold', offset: 0, length: 4)]
    );
    FormattedTextResult? composed;
    Message? quoted;
    final h = _ComposerHarness(
      editor: (_) async => result,
      createFormatted: (value, quote) async {
        composed = value;
        quoted = quote;
        return Message()..contentType = MessageType.advancedText;
      },
    );
    h.composer.initialize('draft');
    final quote = Message()..clientMsgID = 'quote';
    h.composer.replyToMessage(quote);
    await h.composer.onTapFormattedText();
    expect(composed?.entities.single.type, 'bold');
    expect(quoted, same(quote));
    expect(h.composer.inputCtrl.text, isEmpty);
    expect(h.composer.quotedMessage.value, isNull);
    await h.close();
  });

  test('new input and quote survive an earlier composition completing',
      () async {
    final created = Completer<Message>();
    final h = _ComposerHarness(createText: (_) => created.future);
    h.composer.initialize('first');
    h.composer.replyToMessage(Message()..clientMsgID = 'first-quote');
    final pending = h.composer.sendTextMsg();
    h.composer.inputCtrl.text = 'second';
    final nextQuote = Message()..clientMsgID = 'next-quote';
    h.composer.replyToMessage(nextQuote);
    created.complete(Message()..contentType = MessageType.text);
    await pending;
    expect(h.sent, hasLength(1));
    expect(h.composer.inputCtrl.text, 'second');
    expect(h.composer.quotedMessage.value, same(nextQuote));
    await h.close();
    expect(jsonDecode(h.drafts.last.$2)['text'], 'second');
  });

  test('repeated send cannot create the same draft twice', () async {
    final created = Completer<Message>();
    var creations = 0;
    final h = _ComposerHarness(createText: (_) {
      creations++;
      return created.future;
    });
    h.composer.initialize('draft');
    final first = h.composer.sendTextMsg();
    final duplicate = h.composer.sendTextMsg();
    expect(creations, 1);
    created.complete(Message()..contentType = MessageType.text);
    await Future.wait([first, duplicate]);
    expect(h.sent, hasLength(1));
    await h.close();
  });

  test('pending delivery allows the next draft to be composed and submitted',
      () async {
    final network = Completer<void>();
    final h = _ComposerHarness(transport: (_) => network.future);
    h.composer.initialize('first');
    final first = h.composer.sendTextMsg();
    await Future<void>.delayed(Duration.zero);
    expect(h.composer.inputCtrl.text, isEmpty);
    h.composer.inputCtrl.text = 'second';
    final second = h.composer.sendTextMsg();
    await Future<void>.delayed(Duration.zero);
    expect(h.compositions.map((c) => c.text), ['first', 'second']);
    expect(h.sent, hasLength(2));
    network.complete();
    await Future.wait([first, second]);
    await h.close();
  });

  test('unrelated forwarded text and retries do not own the current draft',
      () async {
    final h = _ComposerHarness();
    h.composer.initialize('unsent draft');
    final quote = Message()..clientMsgID = 'quote';
    h.composer.replyToMessage(quote);
    h.composer.resetAfterSend(Message()..contentType = MessageType.text);
    expect(h.composer.inputCtrl.text, 'unsent draft');
    expect(h.composer.quotedMessage.value, same(quote));
    await h.close();
  });

  test('creation failure retains the draft and releases the submission lock',
      () async {
    var creations = 0;
    final h = _ComposerHarness(createText: (_) async {
      if (++creations == 1) throw StateError('native creation failed');
      return Message()..contentType = MessageType.text;
    });
    h.composer.initialize('draft');
    await h.composer.sendTextMsg();
    expect(h.composer.inputCtrl.text, 'draft');
    expect(h.errors, hasLength(1));
    await h.composer.sendTextMsg();
    expect(h.sent, hasLength(1));
    expect(h.composer.inputCtrl.text, isEmpty);
    await h.close();
  });

  test('a changed session or mute state stops an outstanding composition',
      () async {
    for (final sessionChanged in [false, true]) {
      final created = Completer<Message>();
      var inactive = false;
      final h = _ComposerHarness(
          createText: (_) => created.future, inactive: () => inactive);
      h.composer.initialize('draft');
      final pending = h.composer.sendTextMsg();
      if (sessionChanged) {
        inactive = true;
      } else {
        h.muted = true;
      }
      created.complete(Message()..contentType = MessageType.text);
      await pending;
      expect(h.sent, isEmpty);
      expect(h.composer.inputCtrl.text, 'draft');
      await h.close();
    }
  });

  test('formatted creation cannot clear input edited after opening the editor',
      () async {
    final created = Completer<Message>();
    final h = _ComposerHarness(
      editor: (_) async => (text: 'formatted', entities: <RichMessageInfo>[]),
      createFormatted: (_, __) => created.future,
    );
    h.composer.initialize('original draft');
    final pending = h.composer.onTapFormattedText();
    await Future<void>.delayed(Duration.zero);
    h.composer.inputCtrl.text = 'next draft';
    final quote = Message()..clientMsgID = 'new quote';
    h.composer.replyToMessage(quote);
    created.complete(Message()..contentType = MessageType.advancedText);
    await pending;
    expect(h.composer.inputCtrl.text, 'next draft');
    expect(h.composer.quotedMessage.value, same(quote));
    await h.close();
  });
}
