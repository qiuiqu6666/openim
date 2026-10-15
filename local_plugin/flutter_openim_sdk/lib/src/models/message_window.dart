/// Native coverage describes a bounded sequence interval, not a full prefix.
class MessageWindow {
  MessageWindow.fromJson(Map<String, dynamic> json)
      : version = json['version'] ?? 0,
        conversationID = json['conversationID'] ?? '',
        lowerBound = json['lowerBound'] ?? 0,
        targetWatermark = json['targetWatermark'] ?? 0,
        latestServerSeq = json['latestServerSeq'] ?? 0,
        source = json['source'] ?? 'local',
        readiness = json['readiness'] ??
            (json['publishable'] == true ? 'ready' : 'preparing'),
        coverageStatus = json['coverageStatus'] ??
            (json['publishable'] == true ? 'covered' : 'partial'),
        publishable = json['publishable'] == true,
        emptyConfirmed = json['emptyConfirmed'] == true,
        visibilityKey = json['visibilityKey'] ?? '',
        snapshotRevision = json['snapshotRevision'] ?? '',
        covered = _ranges(json['covered']),
        missing = _ranges(json['missing']);
  final int version, lowerBound, targetWatermark, latestServerSeq;
  final String conversationID,
      source,
      readiness,
      coverageStatus,
      visibilityKey,
      snapshotRevision;
  final bool publishable, emptyConfirmed;
  final List<(int, int)> covered, missing;
  bool get canPublish =>
      version == 1 &&
      publishable &&
      missing.isEmpty &&
      conversationID.isNotEmpty &&
      snapshotRevision.isNotEmpty &&
      visibilityKey.isNotEmpty &&
      readiness == 'ready' &&
      coverageStatus == 'covered' &&
      targetWatermark >= 0 &&
      lowerBound >= 1 &&
      (lowerBound > targetWatermark
          ? emptyConfirmed && covered.isEmpty
          : covered.length == 1 &&
              covered.single.$1 == lowerBound &&
              covered.single.$2 == targetWatermark);
  static List<(int, int)> _ranges(dynamic value) =>
      List.unmodifiable((value as List? ?? const [])
          .map((r) => ((r[0] as num).toInt(), (r[1] as num).toInt())));
  Map<String, dynamic> toJson() => {
        'version': version,
        'conversationID': conversationID,
        'lowerBound': lowerBound,
        'targetWatermark': targetWatermark,
        'latestServerSeq': latestServerSeq,
        'source': source,
        'readiness': readiness,
        'coverageStatus': coverageStatus,
        'publishable': publishable,
        'emptyConfirmed': emptyConfirmed,
        'visibilityKey': visibilityKey,
        'snapshotRevision': snapshotRevision,
        'covered': covered.map((r) => [r.$1, r.$2]).toList(),
        'missing': missing.map((r) => [r.$1, r.$2]).toList()
      };
}
