import 'package:hive/hive.dart';

part 'call_records.g.dart';

@HiveType(typeId: 4)
class CallRecords {
  @HiveField(1)
  String userID;
  @HiveField(2)
  String nickname;
  @HiveField(3)
  String? faceURL;
  @HiveField(4)
  String type;
  @HiveField(5)
  bool success;
  @HiveField(6)
  bool incomingCall;
  @HiveField(7)
  int date;
  @HiveField(8)
  int duration;
  @HiveField(9)
  String? roomID;
  @HiveField(10)
  String? state;
  @HiveField(11)
  String roomType;
  @HiveField(12)
  String groupID;
  @HiveField(13)
  List<String> participantUserIDs;
  @HiveField(14)
  int endedAt;
  @HiveField(15)
  int updatedAt;

  CallRecords({
    required this.userID,
    required this.nickname,
    this.faceURL,
    required this.type,
    required this.success,
    required this.incomingCall,
    required this.date,
    required this.duration,
    this.roomID,
    this.state,
    this.roomType = 'single',
    this.groupID = '',
    this.participantUserIDs = const [],
    this.endedAt = 0,
    this.updatedAt = 0,
  });

  CallRecords.fromJson(Map<String, dynamic> json)
      : userID = json['userID'],
        nickname = json['nickname'],
        faceURL = json['faceURL'],
        type = json['type'],
        success = json['success'],
        incomingCall = json['incomingCall'],
        date = json['date'],
        duration = json['duration'],
        roomID = json['roomID'],
        state = json['state'],
        roomType = json['roomType'] ?? 'single',
        groupID = json['groupID'] ?? '',
        participantUserIDs =
            List<String>.from(json['participantUserIDs'] ?? []),
        endedAt = json['endedAt'] ?? 0,
        updatedAt = json['updatedAt'] ?? 0;

  String get callID => roomID ?? '';
  int get startedAt => timestampMilliseconds;

  /// Keep the historic local terminal names compatible with the Chat contract.
  String get status {
    if (success) return 'completed';
    if (const {'completed', 'missed', 'rejected', 'cancelled'}
        .contains(state)) {
      return state!;
    }
    if (const {'reject', 'beRejected'}.contains(state)) return 'rejected';
    if (state == 'timeout') return 'missed';
    if (const {'cancel', 'beCanceled'}.contains(state)) return 'cancelled';
    return incomingCall ? 'missed' : 'cancelled';
  }

  /// Legacy records did not distinguish a declined call from an unanswered one.
  /// Keep incoming legacy failures in Missed; explicit local declines stay in All.
  bool get isMissed =>
      incomingCall &&
      !success &&
      (state == null ||
          state!.trim().isEmpty ||
          const {'timeout', 'beCanceled', 'missed'}.contains(state));

  String get recordKey {
    final room = roomID?.trim() ?? '';
    if (room.isNotEmpty) return 'room:$room';
    return 'legacy:$userID:$date:$type:$incomingCall';
  }

  /// New records use milliseconds; accept historical Unix seconds as well.
  int get timestampMilliseconds =>
      date > 0 && date < 1000000000000 ? date * 1000 : date;

  CallRecords copy() => CallRecords.fromJson(toJson());

  Map<String, dynamic> toJson() {
    return {
      'userID': userID,
      'nickname': nickname,
      'faceURL': faceURL,
      'type': type,
      'success': success,
      'incomingCall': incomingCall,
      'date': date,
      'duration': duration,
      'roomID': roomID,
      'state': state,
      'roomType': roomType,
      'groupID': groupID,
      'participantUserIDs': List<String>.of(participantUserIDs),
      'endedAt': endedAt,
      'updatedAt': updatedAt,
    };
  }
}
