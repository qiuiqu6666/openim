part of 'call_records.dart';

class CallRecordsAdapter extends TypeAdapter<CallRecords> {
  @override
  final int typeId = 4;

  @override
  CallRecords read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CallRecords(
      userID: fields[1] as String,
      nickname: fields[2] as String,
      faceURL: fields[3] as String?,
      type: fields[4] as String,
      success: fields[5] as bool,
      incomingCall: fields[6] as bool,
      date: fields[7] as int,
      duration: fields[8] as int,
      roomID: fields[9] as String?,
      state: fields[10] as String?,
      roomType: fields[11] as String? ?? 'single',
      groupID: fields[12] as String? ?? '',
      participantUserIDs: (fields[13] as List?)?.cast<String>() ?? const [],
      endedAt: fields[14] as int? ?? 0,
      updatedAt: fields[15] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, CallRecords obj) {
    writer
      ..writeByte(15)
      ..writeByte(1)
      ..write(obj.userID)
      ..writeByte(2)
      ..write(obj.nickname)
      ..writeByte(3)
      ..write(obj.faceURL)
      ..writeByte(4)
      ..write(obj.type)
      ..writeByte(5)
      ..write(obj.success)
      ..writeByte(6)
      ..write(obj.incomingCall)
      ..writeByte(7)
      ..write(obj.date)
      ..writeByte(8)
      ..write(obj.duration)
      ..writeByte(9)
      ..write(obj.roomID)
      ..writeByte(10)
      ..write(obj.state)
      ..writeByte(11)
      ..write(obj.roomType)
      ..writeByte(12)
      ..write(obj.groupID)
      ..writeByte(13)
      ..write(obj.participantUserIDs)
      ..writeByte(14)
      ..write(obj.endedAt)
      ..writeByte(15)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallRecordsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
