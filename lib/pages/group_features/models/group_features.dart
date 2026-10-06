import 'dart:convert';

Map<String, dynamic> featureMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};
String featureString(dynamic value) => value is String ? value.trim() : '';

/// Public group summary only. Personal roles and media credentials stay outside ex.
class GroupFeatures {
  const GroupFeatures(
      {this.schemaVersion = 1,
      this.revision = -1,
      this.live = const GroupLiveFeature(),
      this.sangong = const GroupGameFeature(),
      this.markSix = const GroupGameFeature(),
      this.raw = const {},
      this.valid = false});
  final int schemaVersion, revision;
  final bool valid;
  final GroupLiveFeature live;
  final GroupGameFeature sangong, markSix;
  final Map<String, dynamic> raw;

  factory GroupFeatures.fromEx(String? ex) {
    try {
      return GroupFeatures.fromJson(
          featureMap(jsonDecode(ex ?? ''))['groupFeatures']);
    } catch (_) {
      return const GroupFeatures();
    }
  }
  factory GroupFeatures.fromJson(dynamic value) {
    final map = featureMap(value);
    final revision = map['revision'];
    if (map['schemaVersion'] != 1 || revision is! int || revision < 0) {
      return const GroupFeatures();
    }
    final games = featureMap(map['games']);
    return GroupFeatures(
        schemaVersion: 1,
        revision: revision,
        valid: true,
        live: GroupLiveFeature.fromJson(map['live']),
        sangong: GroupGameFeature.fromJson(games['sangong']),
        markSix: GroupGameFeature.fromJson(games['markSix']),
        raw: Map.unmodifiable(map));
  }
}

class GroupLiveFeature {
  const GroupLiveFeature(
      {this.status = 'none',
      this.sessionID = '',
      this.roomName = '',
      this.description = '',
      this.anchorUserID = '',
      this.scheduledStartAt,
      this.raw = const {}});
  final String status, sessionID, roomName, description, anchorUserID;
  final DateTime? scheduledStartAt;
  final Map<String, dynamic> raw;
  bool get isActive =>
      sessionID.isNotEmpty &&
      const {'scheduled', 'ready', 'live'}.contains(status);
  String get label => switch (status) {
        'scheduled' => '待开播',
        'ready' => '有直播',
        'live' => '直播中',
        'ended' => '已结束',
        _ => '',
      };
  factory GroupLiveFeature.fromJson(dynamic value) {
    final map = featureMap(value);
    final status = featureString(map['status']);
    DateTime? time;
    final stamp = map['scheduledStartAt'];
    if (stamp is int && stamp >= 0) {
      time = DateTime.fromMillisecondsSinceEpoch(stamp);
    }
    if (stamp is String) time = DateTime.tryParse(stamp);
    return GroupLiveFeature(
        status: const {'none', 'scheduled', 'ready', 'live', 'ended'}
                .contains(status)
            ? status
            : 'none',
        sessionID: featureString(map['sessionID']),
        roomName: featureString(map['roomName']),
        description: featureString(map['description']),
        anchorUserID: featureString(map['anchorUserID']),
        scheduledStartAt: time,
        raw: Map.unmodifiable(map));
  }
}

class GroupGameFeature {
  const GroupGameFeature(
      {this.enabled = false,
      this.manageEntry = false,
      this.agentEntry = false,
      this.drawHistoryEntry = false,
      this.rebateHistoryEntry = false,
      this.tenantID = '',
      this.gameID = '',
      this.machineCode = '',
      this.raw = const {}});
  final bool enabled,
      manageEntry,
      agentEntry,
      drawHistoryEntry,
      rebateHistoryEntry;
  final String tenantID, gameID, machineCode;
  final Map<String, dynamic> raw;
  factory GroupGameFeature.fromJson(dynamic value) {
    final map = featureMap(value);
    return GroupGameFeature(
        enabled: map['enabled'] == true,
        manageEntry: map['manageEntry'] == true,
        agentEntry: map['agentEntry'] == true,
        drawHistoryEntry: map['drawHistoryEntry'] == true,
        rebateHistoryEntry: map['rebateHistoryEntry'] == true,
        tenantID: featureString(map['tenantID']),
        gameID: featureString(map['gameID']),
        machineCode: featureString(map['machineCode']),
        raw: Map.unmodifiable(map));
  }
}
