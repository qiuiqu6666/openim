import 'group_features.dart';

class GroupFeatureCapabilities {
  const GroupFeatureCapabilities(
      {this.version = 0,
      this.cacheTTLSeconds = 300,
      this.live = const GroupLiveCapabilities(),
      this.sangong = const GroupGameCapabilities(),
      this.markSix = const GroupGameCapabilities()});
  final int version, cacheTTLSeconds;
  final GroupLiveCapabilities live;
  final GroupGameCapabilities sangong, markSix;
  factory GroupFeatureCapabilities.fromJson(Map<String, dynamic> json) =>
      GroupFeatureCapabilities(
          version:
              json['capabilityVersion'] is int ? json['capabilityVersion'] : 0,
          cacheTTLSeconds: json['cacheTTLSeconds'] is int
              ? (json['cacheTTLSeconds'] as int).clamp(0, 300)
              : 300,
          live: GroupLiveCapabilities.fromJson(json['live']),
          sangong: GroupGameCapabilities.fromJson(json['sangong']),
          markSix: GroupGameCapabilities.fromJson(json['markSix']));
}

class GroupLiveCapabilities {
  const GroupLiveCapabilities(
      {this.canConfigure = false,
      this.canManage = false,
      this.canPush = false,
      this.canTip = false,
      this.raw = const {}});
  final bool canConfigure, canManage, canPush, canTip;
  final Map<String, dynamic> raw;
  factory GroupLiveCapabilities.fromJson(dynamic value) {
    final map = featureMap(value);
    return GroupLiveCapabilities(
        canConfigure: map['canConfigure'] == true,
        canManage: map['canManage'] == true,
        canPush: map['canPush'] == true,
        canTip: map['canTip'] == true,
        raw: Map.unmodifiable(map));
  }
}

class GroupGameCapabilities {
  const GroupGameCapabilities(
      {this.canConfigure = false,
      this.canManage = false,
      this.canOpenAgent = false,
      this.canViewRebateHistory = false,
      this.tenantID = '',
      this.gameID = '',
      this.machineCode = '',
      this.raw = const {}});
  final bool canConfigure, canManage, canOpenAgent, canViewRebateHistory;
  final String tenantID, gameID, machineCode;
  final Map<String, dynamic> raw;
  factory GroupGameCapabilities.fromJson(dynamic value) {
    final map = featureMap(value);
    return GroupGameCapabilities(
        canConfigure: map['canConfigure'] == true,
        canManage: map['canManage'] == true,
        canOpenAgent: map['canOpenAgent'] == true,
        canViewRebateHistory: map['canViewRebateHistory'] == true,
        tenantID: featureString(map['tenantID']),
        gameID: featureString(map['gameID']),
        machineCode: featureString(map['machineCode']),
        raw: Map.unmodifiable(map));
  }

  bool get requiresTenantSelection => raw['requiresTenantSelection'] == true;
}
