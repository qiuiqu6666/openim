import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/ai_assistant/streaming/assistant_stream_chunk.dart';
import 'package:openim/pages/ai_assistant/streaming/assistant_stream_state.dart';

AssistantStreamChunk _chunk(int index, String text,
        {String id = 'stream', bool end = false}) =>
    AssistantStreamChunk(streamID: id, index: index, text: text, end: end);

Message _message(Object data, {String description = 'assistantStream'}) =>
    Message(
        contentType: MessageType.custom,
        customElem:
            CustomElem(description: description, data: jsonEncode(data)));

void main() {
  test('parses only strict assistantStream custom JSON deltas', () {
    final chunk = AssistantStreamChunk.tryParse(_message({
      'streamID': 'turn',
      'index': 0,
      'text': '新文字\n',
      'end': false,
    }));
    expect(chunk?.streamID, 'turn');
    expect(chunk?.index, 0);
    expect(chunk?.text, '新文字\n');
    expect(chunk?.end, isFalse);
    for (final payload in [
      'plain text',
      [],
      {'streamID': '', 'index': 0, 'text': '', 'end': false},
      {'streamID': 'x', 'index': -1, 'text': '', 'end': false},
      {'streamID': 'x', 'index': 0.5, 'text': '', 'end': false},
      {'streamID': 'x', 'index': '0', 'text': '', 'end': false},
      {'streamID': 'x', 'index': 0, 'text': null, 'end': false},
      {'streamID': 'x', 'index': 0, 'text': '', 'end': 1},
    ]) {
      expect(AssistantStreamChunk.tryParse(_message(payload)), isNull);
    }
    expect(
        AssistantStreamChunk.tryParse(_message({
          'streamID': 'turn',
          'index': 0,
          'text': 'x',
          'end': false,
        }, description: 'image')),
        isNull);
    expect(
        AssistantStreamChunk.tryParse(Message(
            contentType: MessageType.custom,
            customElem: CustomElem(description: 'assistantStream', data: '{'))),
        isNull);
  });

  test(
      'buffers gaps, drains index order and completes only at a contiguous end',
      () {
    final state = AssistantStreamState();
    addTearDown(state.dispose);
    var changes = 0;
    state.addListener(() => changes++);
    state.accept(_chunk(2, 'C', end: true));
    expect(state.snapshots.single.text, isEmpty);
    expect(state.snapshots.single.ended, isFalse);
    expect(changes, 1);
    state.accept(_chunk(0, 'A'));
    expect(state.snapshots.single.text, 'A');
    expect(state.snapshots.single.ended, isFalse);
    state.accept(_chunk(1, 'B'));
    expect(state.snapshots.single.text, 'ABC');
    expect(state.snapshots.single.ended, isTrue);
    expect(changes, 3);
  });

  test(
      'duplicate buffered and consumed indices never repeat text or notifications',
      () {
    final state = AssistantStreamState();
    addTearDown(state.dispose);
    var changes = 0;
    state.addListener(() => changes++);
    state.accept(_chunk(1, 'B'));
    expect(state.accept(_chunk(1, 'changed B')), isNull);
    expect(changes, 1);
    state.accept(_chunk(0, 'A'));
    expect(state.accept(_chunk(0, 'changed A')), isNull);
    expect(state.snapshots.single.text, 'AB');
    expect(changes, 2);
    state.accept(_chunk(2, '', end: true));
    expect(state.snapshots.single.ended, isTrue);
    expect(state.accept(_chunk(3, 'extra')), isNull);
    expect(changes, 3);
    expect(state.snapshots.single.text, 'AB');
  });

  test('concurrent streams keep first arrival order and immutable snapshots',
      () {
    final state = AssistantStreamState();
    addTearDown(state.dispose);
    state.accept(_chunk(1, 'later', id: 'second-turn'));
    state.accept(_chunk(0, 'first', id: 'first-turn'));
    final previous = state.snapshots;
    expect(
        previous.map((value) => value.streamID), ['second-turn', 'first-turn']);
    expect(() => previous.clear(), throwsUnsupportedError);
    state.accept(_chunk(0, 'second ', id: 'second-turn'));
    expect(previous.first.text, isEmpty);
    expect(state.snapshots.first.text, 'second later');
    expect(state.snapshots.last.text, 'first');
  });

  test(
      'end preserves the transient stream until the authoritative final message',
      () {
    final state = AssistantStreamState();
    addTearDown(state.dispose);
    state.accept(_chunk(0, 'draft', end: true));
    expect(state.snapshots.single.text, 'draft');
    final finalMessage =
        Message(contentType: MessageType.text, ex: '{"streamID":"stream"}');
    expect(state.markFinalMessage(finalMessage), isTrue);
    expect(state.snapshots, isEmpty);
    expect(state.isFinalized('stream'), isTrue);
    expect(state.accept(_chunk(0, 'late')), isNull);
  });

  test(
      'a final before its deltas records a tombstone without a false visible update',
      () {
    final state = AssistantStreamState();
    addTearDown(state.dispose);
    var changes = 0;
    state.addListener(() => changes++);
    expect(
        state.markFinalMessage(Message(
            contentType: MessageType.text, ex: '{"streamID":"stream"}')),
        isFalse);
    expect(state.accept(_chunk(0, 'late')), isNull);
    expect(state.snapshots, isEmpty);
    expect(changes, 0);
  });

  test('malformed or nonfinal message ex does not remove a live stream', () {
    final state = AssistantStreamState();
    addTearDown(state.dispose);
    state.accept(_chunk(0, 'live'));
    for (final message in [
      Message(contentType: MessageType.text, ex: '{'),
      Message(contentType: MessageType.text, ex: '{"streamID":4}'),
      Message(contentType: MessageType.text, ex: '{"streamID":""}'),
      Message(contentType: MessageType.custom, ex: '{"streamID":"stream"}'),
    ]) {
      expect(state.markFinalMessage(message), isFalse);
    }
    expect(state.snapshots.single.text, 'live');
  });

  test('clear resets route data and dispose rejects delayed updates', () {
    final state = AssistantStreamState();
    state.accept(_chunk(0, 'old'));
    state.markFinal('completed');
    state.clear();
    expect(state.snapshots, isEmpty);
    expect(state.isFinalized('completed'), isFalse);
    state.accept(_chunk(0, 'new', id: 'completed'));
    expect(state.snapshots.single.text, 'new');
    state.dispose();
    expect(state.isDisposed, isTrue);
    expect(state.snapshots, isEmpty);
    expect(state.accept(_chunk(0, 'late')), isNull);
    expect(state.markFinal('late'), isFalse);
    state.clear();
    state.dispose();
  });
}
