enum LiveStatus {
  scheduled,
  authorized,
  live,
  ended,
  banned,
  unknown;

  static LiveStatus parse(Object? value) => values.firstWhere(
      (status) => status.name.toUpperCase() == value?.toString().toUpperCase(),
      orElse: () => unknown);
  bool get active => this == scheduled || this == authorized || this == live;
  String get label => switch (this) {
        scheduled => '待开播',
        authorized => '有直播',
        live => '直播中',
        ended => '直播已结束',
        banned => '直播已关闭',
        unknown => '状态未知',
      };
}

String liveString(Map<String, dynamic> json, String key) =>
    json[key]?.toString().trim() ?? '';

String _text(Map<String, dynamic> json, String key, {bool required = false}) {
  final value = json[key];
  if (value != null && value is! String) {
    throw FormatException('直播接口的 $key 格式不正确');
  }
  final text = (value as String? ?? '').trim();
  if (required && text.isEmpty) {
    throw FormatException('直播接口未返回 $key');
  }
  return text;
}

DateTime? _date(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null || value == '') return null;
  if (value is! String) throw FormatException('直播接口的 $key 时间格式不正确');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('直播接口的 $key 时间格式不正确');
  return parsed;
}

String _httpSource(Map<String, dynamic> json, String key) {
  final value = _text(json, key);
  if (value.isEmpty) return value;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'https' && uri.scheme != 'http')) {
    throw FormatException('直播接口的 $key 播放地址格式不正确');
  }
  return value;
}

class LiveSession {
  const LiveSession(
      {required this.id,
      required this.groupID,
      required this.status,
      this.roomName = '',
      this.description = '',
      this.anchorID = '',
      this.version = 0,
      this.scheduledAt,
      this.expireAt,
      this.endReason = '',
      this.imSyncStatus = ''});
  factory LiveSession.fromJson(Map<String, dynamic> json) {
    final status = LiveStatus.parse(json['status']);
    final version = json['version'];
    final sync = _text(json, 'imSyncStatus');
    final name = _text(json, 'roomName', required: true);
    final description = _text(json, 'description');
    final scheduled = _date(json, 'scheduledStartAt');
    if (status == LiveStatus.unknown ||
        version is! int ||
        version < 1 ||
        name.runes.length > 10 ||
        description.runes.length > 30 ||
        (status == LiveStatus.scheduled && scheduled == null) ||
        (sync.isNotEmpty && sync != 'synced' && sync != 'pending')) {
      throw const FormatException('直播接口返回的场次信息不完整或格式不正确');
    }
    return LiveSession(
        id: _text(json, 'liveSessionId', required: true),
        groupID: _text(json, 'groupId', required: true),
        status: status,
        roomName: name,
        description: description,
        anchorID: _text(json, 'anchorUserId', required: true),
        version: version,
        scheduledAt: scheduled,
        expireAt: _date(json, 'expireAt'),
        endReason: _text(json, 'endReason'),
        imSyncStatus: sync);
  }
  final String id,
      groupID,
      roomName,
      description,
      anchorID,
      endReason,
      imSyncStatus;
  final LiveStatus status;
  final int version;
  final DateTime? scheduledAt, expireAt;
  Map<String, dynamic> toJson() => {
        'liveSessionId': id,
        'groupId': groupID,
        'status': status.name.toUpperCase(),
        'roomName': roomName,
        'description': description,
        'anchorUserId': anchorID,
        'version': version,
        'scheduledStartAt': scheduledAt?.toUtc().toIso8601String(),
        'expireAt': expireAt?.toUtc().toIso8601String(),
        'endReason': endReason,
        if (imSyncStatus.isNotEmpty) 'imSyncStatus': imSyncStatus,
      };
}

class LivePlayInfo {
  const LivePlayInfo(
      {required this.id,
      required this.roomName,
      required this.protocol,
      required this.playURL,
      this.flvURL = '',
      this.hlsURL = '',
      this.anchorID = '',
      this.expiresAt});
  factory LivePlayInfo.fromJson(Map<String, dynamic> json) => LivePlayInfo(
      id: _text(json, 'liveSessionId', required: true),
      roomName: _text(json, 'roomName'),
      protocol: _text(json, 'protocol'),
      playURL: _httpSource(json, 'playUrl'),
      flvURL: _httpSource(json, 'fallbackFlvUrl'),
      hlsURL: _httpSource(json, 'fallbackHlsUrl'),
      anchorID: _text(json, 'anchorUserId'),
      expiresAt: _date(json, 'expiresAt'));
  final String id, roomName, protocol, playURL, flvURL, hlsURL, anchorID;
  final DateTime? expiresAt;
  List<Uri> get supportedSources {
    final result = <Uri>[];
    final rtc = protocol.toLowerCase().contains('webrtc') ||
        protocol.toLowerCase().contains('trtc') ||
        protocol.toLowerCase() == 'leb';
    for (final value in [if (!rtc) playURL, flvURL, hlsURL]) {
      final uri = Uri.tryParse(value);
      if (uri != null &&
          uri.host.isNotEmpty &&
          (uri.scheme == 'https' || uri.scheme == 'http') &&
          !result.contains(uri)) {
        result.add(uri);
      }
    }
    return List.unmodifiable(result);
  }
}

class LivePushInfo {
  const LivePushInfo(
      {required this.server,
      required this.key,
      this.expiresAt,
      this.hint = ''});
  factory LivePushInfo.fromJson(Map<String, dynamic> json) {
    final server = _text(json, 'rtmpServer', required: true);
    final uri = Uri.tryParse(server);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'rtmp' && uri.scheme != 'rtmps')) {
      throw const FormatException('直播接口返回的推流地址格式不正确');
    }
    return LivePushInfo(
        server: server,
        key: _text(json, 'streamKey', required: true),
        hint: _text(json, 'obsHint'),
        expiresAt: _date(json, 'expiresAt'));
  }
  final String server, key, hint;
  final DateTime? expiresAt;
  String get combinedURL => '${server.replaceFirst(RegExp(r'/+$'), '')}/$key';
}
