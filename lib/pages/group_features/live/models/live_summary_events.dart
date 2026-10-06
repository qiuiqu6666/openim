import '../../models/group_feature_context.dart';

/// Group revisions order public summaries; they never become live DTO versions.
class LiveSummaryEvents {
  LiveSummaryEvents(GroupFeatures initial)
      : _revision = initial.revision,
        _fingerprint = initial.valid ? _key(initial.live) : null;
  int _revision;
  String? _fingerprint;

  GroupLiveFeature? accept(Map<String, dynamic> event, String groupID) {
    final target = event['groupID'];
    if (target != null && target != groupID) return null;
    final data = featureMap(event['data']);
    final features =
        GroupFeatures.fromJson(event['groupFeatures'] ?? data['groupFeatures']);
    if (!features.valid || features.revision <= _revision) return null;
    _revision = features.revision;
    final fingerprint = _key(features.live);
    if (fingerprint == _fingerprint) return null;
    _fingerprint = fingerprint;
    return features.live;
  }

  static String _key(GroupLiveFeature live) => [
        live.sessionID,
        live.status,
        live.roomName,
        live.description,
        live.anchorUserID,
        live.scheduledStartAt?.toIso8601String() ?? ''
      ].join('\u0000');
}

String liveSummaryStopReason(GroupLiveFeature live, String sessionID) {
  if (live.sessionID.isNotEmpty && live.sessionID != sessionID) {
    return '直播场次已变化，请重新进入';
  }
  return switch (live.status) {
    'scheduled' => '直播尚未开始，请稍候',
    'ready' => '直播准备中，请稍候…',
    _ => '直播已结束'
  };
}
