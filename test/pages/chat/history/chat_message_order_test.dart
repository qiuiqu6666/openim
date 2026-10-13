import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/chat_history_loader.dart';

Message _message(String id, int? seq, {int time = 30}) =>
    Message(clientMsgID: id, seq: seq, sendTime: time);

void main() {
  test('same-second unknown sequences follow the persisted sequence range', () {
    final result = ChatHistoryLoader.merge([
      _message('known-30', 30),
      _message('live-zero', 0),
      _message('known-29', 29),
      _message('live-null', null),
    ]);
    expect(result.map((m) => m.clientMsgID),
        ['known-29', 'known-30', 'live-zero', 'live-null']);
  });

  test('unknown sequence does not place an older second after newer messages',
      () {
    final result = ChatHistoryLoader.merge([
      _message('newer', 3, time: 31),
      _message('old-unknown', 0),
    ]);
    expect(result.map((m) => m.clientMsgID), ['old-unknown', 'newer']);
  });

  test('equal unknown rows retain arrival order across history merges', () {
    final messages = List.generate(50, (i) => _message('live-$i', 0));
    final result =
        ChatHistoryLoader.merge([...messages, messages[2], messages[20]]);
    expect(
        result.map((m) => m.clientMsgID), messages.map((m) => m.clientMsgID));
  });

  test('a server sequence resolves provisional ordering for the same identity',
      () {
    final result = ChatHistoryLoader.merge([
      _message('known-30', 30),
      _message('provisional', 0),
      _message('provisional', 29),
    ]);
    expect(result.map((m) => m.clientMsgID), ['provisional', 'known-30']);
    expect(result.first.seq, 29);
  });
}
