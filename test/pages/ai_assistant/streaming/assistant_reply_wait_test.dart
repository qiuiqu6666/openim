import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/ai_assistant/streaming/assistant_stream_chunk.dart';
import 'package:openim/pages/ai_assistant/streaming/assistant_stream_state.dart';

AssistantStreamChunk _chunk(int index, String text,
        {String id = 'stream', bool end = false}) =>
    AssistantStreamChunk(streamID: id, index: index, text: text, end: end);

Message _reply({String? id, int type = MessageType.text}) => Message(
    contentType: type, ex: id == null ? null : jsonEncode({'streamID': id}));

void main() {
  late AssistantStreamState state;

  setUp(() => state = AssistantStreamState());
  tearDown(() => state.dispose());

  test('sending immediately creates one stable waiting row for merged requests',
      () {
    var changes = 0;
    state.addListener(() => changes++);
    final first = state.beginReply();
    expect(first, isNotNull);
    final row = state.snapshots.single;
    expect(row.waiting, isTrue);
    expect(row.text, isEmpty);
    expect(row.ended, isFalse);
    expect(row.presentationID, row.rowID);
    expect(row.presentationID, isNotEmpty);
    expect(changes, 1);

    final second = state.beginReply();
    expect(second, isNot(first));
    expect(state.snapshots.single.presentationID, row.presentationID);
    expect(changes, 1);
    expect(() => state.snapshots.clear(), throwsUnsupportedError);
  });

  test('a failed send cancels only its token and keeps the other waiting send',
      () {
    final first = state.beginReply();
    final second = state.beginReply();
    final identity = state.snapshots.single.presentationID;
    state.cancelReply(first);
    state.cancelReply(first);
    state.cancelReply(null);
    state.cancelReply(-1);
    expect(state.snapshots.single.presentationID, identity);
    expect(state.snapshots.single.waiting, isTrue);
    state.cancelReply(second);
    expect(state.snapshots, isEmpty);
  });

  test('cancelled or cleared old tokens cannot cancel a later waiting row', () {
    final old = state.beginReply();
    state.cancelReply(old);
    final later = state.beginReply();
    state.cancelReply(old);
    expect(state.snapshots.single.waiting, isTrue);
    state.clear();
    final afterClear = state.beginReply();
    expect(afterClear, isNot(later));
    state.cancelReply(later);
    expect(state.snapshots.single.waiting, isTrue);
  });

  test('the first stream replaces merged waiting with the same row identity',
      () {
    final first = state.beginReply();
    final second = state.beginReply();
    final identity = state.snapshots.single.presentationID;
    final reply = state.accept(_chunk(0, 'first segment'))!;
    expect(state.snapshots, hasLength(1));
    expect(reply.streamID, 'stream');
    expect(reply.presentationID, identity);
    expect(reply.waiting, isFalse);
    expect(reply.text, 'first segment');
    state.cancelReply(first);
    state.cancelReply(second);
    expect(state.snapshots.single.text, 'first segment');
    state.accept(_chunk(1, ' and next', end: true));
    expect(state.snapshots.single.presentationID, identity);
  });

  test('out of order first arrival keeps waiting until contiguous text exists',
      () {
    state.beginReply();
    final identity = state.snapshots.single.presentationID;
    final buffered = state.accept(_chunk(2, 'C', end: true))!;
    expect(buffered.waiting, isTrue);
    expect(buffered.text, isEmpty);
    expect(buffered.presentationID, identity);
    state.accept(_chunk(0, 'A'));
    expect(state.snapshots.single.waiting, isFalse);
    expect(state.snapshots.single.text, 'A');
    state.accept(_chunk(1, 'B'));
    expect(state.snapshots.single.text, 'ABC');
    expect(state.snapshots.single.ended, isTrue);
    expect(state.snapshots.single.presentationID, identity);
  });

  test('empty chunks preserve waiting only when a local send started it', () {
    state.beginReply();
    final identity = state.snapshots.single.presentationID;
    state.accept(_chunk(0, ''));
    expect(state.snapshots.single.waiting, isTrue);
    expect(state.accept(_chunk(1, '')), isNull);
    expect(state.snapshots.single.waiting, isTrue);
    state.accept(_chunk(2, 'body'));
    expect(state.snapshots.single.waiting, isFalse);
    expect(state.snapshots.single.presentationID, identity);

    state.clear();
    final unsolicited = state.accept(_chunk(1, 'later'))!;
    expect(unsolicited.text, isEmpty);
    expect(unsolicited.waiting, isFalse);
    expect(unsolicited.rowID, isNull);
    expect(unsolicited.presentationID, unsolicited.streamID);
  });

  test(
      'existing stream deltas and its final cannot finish a newer waiting send',
      () {
    state.beginReply();
    state.accept(_chunk(0, 'old body', id: 'old'));
    state.beginReply();
    final waiting = state.snapshots.last.presentationID;
    state.accept(_chunk(1, ' grows', id: 'old'));
    expect(state.snapshots.last.presentationID, waiting);
    expect(state.snapshots.last.waiting, isTrue);
    state.receivedReply(_reply(id: 'old'));
    expect(state.snapshots.single.presentationID, waiting);
    state.receivedReply(_reply(id: 'old'));
    expect(state.snapshots.single.waiting, isTrue);
    state.accept(_chunk(0, 'new body', id: 'new'));
    expect(state.snapshots.single.presentationID, waiting);
    expect(state.snapshots.single.waiting, isFalse);
  });

  test('live final without earlier deltas ends waiting and rejects late deltas',
      () {
    state.beginReply();
    state.receivedReply(_reply(id: 'new-final'));
    expect(state.snapshots, isEmpty);
    expect(state.isFinalized('new-final'), isTrue);
    expect(state.accept(_chunk(0, 'late', id: 'new-final')), isNull);
  });

  test('ordinary text and pictures finish waiting but typing and deltas do not',
      () {
    state.beginReply();
    state.receivedReply(_reply(type: MessageType.typing));
    expect(state.snapshots.single.waiting, isTrue);
    state.receivedReply(Message(
        contentType: MessageType.custom,
        customElem: CustomElem(
            description: AssistantStreamChunk.description, data: '{}')));
    expect(state.snapshots.single.waiting, isTrue);
    state.receivedReply(_reply());
    expect(state.snapshots, isEmpty);
    state.beginReply();
    state.receivedReply(_reply(type: MessageType.picture));
    expect(state.snapshots, isEmpty);
  });

  test('history reconciliation never consumes waiting for a newer request', () {
    state.beginReply();
    final identity = state.snapshots.single.presentationID;
    expect(state.markFinalMessage(_reply(id: 'historical')), isFalse);
    expect(state.snapshots.single.presentationID, identity);
    expect(state.snapshots.single.waiting, isTrue);
    state.receivedReply(_reply(id: 'historical'));
    expect(state.snapshots.single.waiting, isTrue);
    state.accept(_chunk(0, 'current', id: 'current'));
    state.beginReply();
    final nextIdentity = state.snapshots.last.presentationID;
    expect(state.markFinalMessage(_reply(id: 'current')), isTrue);
    expect(state.snapshots.single.presentationID, nextIdentity);
  });

  for (final type in [MessageType.text, MessageType.picture]) {
    test('reply without stream ID retires adopted empty waiting ($type)', () {
      state.accept(_chunk(0, 'another active reply', id: 'active'));
      state.beginReply();
      state.accept(_chunk(0, '', id: 'empty'));
      expect(state.snapshots.last.waiting, isTrue);
      var changes = 0;
      state.addListener(() => changes++);

      state.receivedReply(_reply(type: type));

      expect(state.snapshots.single.streamID, 'active');
      expect(state.snapshots.single.text, 'another active reply');
      expect(state.isFinalized('empty'), isTrue);
      expect(state.accept(_chunk(1, 'late', id: 'empty')), isNull);
      expect(changes, 1);
    });
  }

  test('clear and dispose remove waiting and disposal rejects later changes',
      () {
    var changes = 0;
    state.addListener(() => changes++);
    final token = state.beginReply();
    state.clear();
    expect(state.snapshots, isEmpty);
    expect(changes, 2);
    state.beginReply();
    state.accept(_chunk(0, '', id: 'buffered'));
    state.dispose();
    expect(state.snapshots, isEmpty);
    expect(state.beginReply(), isNull);
    state.cancelReply(token);
    state.receivedReply(_reply(id: 'final'));
    expect(state.accept(_chunk(0, 'late')), isNull);
    expect(state.markFinalMessage(_reply(id: 'final')), isFalse);
  });
}
