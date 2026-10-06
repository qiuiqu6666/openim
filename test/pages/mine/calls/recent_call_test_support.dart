import 'package:hive/hive.dart';
import 'package:openim_common/openim_common.dart';

class RecentCallMemoryBox implements Box {
  final backingMap = <dynamic, dynamic>{};
  int writes = 0;
  @override
  bool isOpen = true;
  Future<void> Function(dynamic key, dynamic value)? beforePut;

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => backingMap[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    await beforePut?.call(key, value);
    backingMap[key] = value;
    writes++;
  }
  @override
  Future<void> close() async => isOpen = false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CallRecords callFixture({
  String room = 'room-1',
  String peer = 'peer-1',
  String nickname = '阿明',
  String type = 'audio',
  bool incoming = false,
  bool success = true,
  String? state = 'hangup',
  int duration = 73,
  int? date,
}) => CallRecords(
  roomID: room,
  userID: peer,
  nickname: nickname,
  type: type,
  incomingCall: incoming,
  success: success,
  state: state,
  duration: duration,
  date: date ?? DateTime(2026, 10, 5, 13, 45).millisecondsSinceEpoch,
);

