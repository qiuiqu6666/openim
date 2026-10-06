/// Wire models for the device-sync receive-only Chat protocol.
const deviceSyncPartSize = 4 * 1024 * 1024;

enum DeviceSyncMediaKind { image, video }

enum DeviceSyncMediaState { done, upload, resume, conflict }

void deviceSyncValidateID(String value) {
  final match = RegExp(r'^[A-Za-z0-9._-]{1,128}$').firstMatch(value);
  if (match?.group(0) != value) throw ArgumentError('Invalid device-sync ID');
}

class DeviceSyncDevice {
  const DeviceSyncDevice(
      {required this.deviceID,
      required this.deviceName,
      required this.platform});
  final String deviceID, deviceName, platform;

  Map<String, dynamic> toJson() {
    deviceSyncValidateID(deviceID);
    for (final value in [deviceName, platform]) {
      if (value.trim().isEmpty ||
          value.runes.length > 200 ||
          value.contains(RegExp(r'[\x00\r\n]'))) {
        throw ArgumentError('Invalid device-sync device description');
      }
    }
    return {
      'deviceID': deviceID,
      'deviceName': deviceName,
      'platform': platform
    };
  }
}

class DeviceSyncMedia {
  const DeviceSyncMedia(
      {required this.localID,
      required this.sha256,
      required this.size,
      required this.kind,
      this.name,
      this.capturedAt = 0,
      String? contentType})
      : _contentType = contentType;
  final String localID, sha256;
  final int size, capturedAt;
  final DeviceSyncMediaKind kind;
  final String? name, _contentType;
  String get contentType =>
      _contentType ??
      (kind == DeviceSyncMediaKind.image ? 'image/jpeg' : 'video/mp4');
  static const imageTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'image/heic',
    'image/heif'
  };
  static const videoTypes = {
    'video/mp4',
    'video/quicktime',
    'video/3gpp',
    'video/webm'
  };

  void validate() {
    deviceSyncValidateID(localID);
    if (RegExp(r'^[0-9a-f]{64}$').firstMatch(sha256)?.group(0) != sha256 ||
        size <= 0 ||
        size >
            (kind == DeviceSyncMediaKind.image
                ? 30 * 1024 * 1024
                : 512 * 1024 * 1024) ||
        capturedAt < 0 ||
        !(kind == DeviceSyncMediaKind.image ? imageTypes : videoTypes)
            .contains(contentType)) {
      throw ArgumentError('Invalid device-sync media metadata');
    }
    final filename = name?.split(RegExp(r'[/\\]')).last;
    if (filename != null &&
        (filename.runes.length > 200 ||
            filename.contains(RegExp(r'[\x00\r\n]')))) {
      throw ArgumentError('Invalid device-sync filename');
    }
  }

  DeviceSyncMedia copyWith({String? localID}) => DeviceSyncMedia(
      localID: localID ?? this.localID,
      sha256: sha256,
      size: size,
      kind: kind,
      name: name,
      capturedAt: capturedAt,
      contentType: _contentType);

  Map<String, dynamic> toJson() {
    validate();
    return {
      'localID': localID,
      'sha256': sha256,
      'size': size,
      'kind': kind.name,
      if (name != null) 'name': name!.split(RegExp(r'[/\\]')).last,
      'capturedAt': capturedAt,
      'contentType': contentType
    };
  }
}

Map<String, dynamic> deviceSyncJson(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Invalid device-sync response object');
  }
  return Map<String, dynamic>.from(value);
}

int _int(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int || value < 0) {
    throw FormatException('Invalid device-sync $key');
  }
  return value;
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('Invalid device-sync $key');
  return value;
}

DeviceSyncMediaState _state(Map<String, dynamic> json,
    {bool conflict = false}) {
  final value = _string(json, 'state');
  for (final state in DeviceSyncMediaState.values) {
    if (state.name == value &&
        (conflict || state != DeviceSyncMediaState.conflict)) {
      return state;
    }
  }
  throw const FormatException('Invalid device-sync state');
}

List<int> _doneParts(Object? value, int count) {
  if (value is! List ||
      value.any((part) => part is! int || part < 1 || part > count)) {
    throw const FormatException('Invalid device-sync completed parts');
  }
  final parts = value.cast<int>();
  if (parts.toSet().length != parts.length) {
    throw const FormatException('Duplicate device-sync completed part');
  }
  return List.unmodifiable(parts);
}

int _partBytes(int number, int size) {
  final remaining = size - (number - 1) * deviceSyncPartSize;
  return remaining < deviceSyncPartSize ? remaining : deviceSyncPartSize;
}

/// Validates storage destinations without ever including a signature in errors.
Uri deviceSyncOSSUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != '99chat.oss-cn-hongkong.aliyuncs.com' ||
      uri.port != 443 ||
      uri.userInfo.isNotEmpty ||
      uri.authority.contains('@') ||
      uri.hasFragment ||
      uri.path.isEmpty ||
      uri.path == '/') {
    throw const FormatException('Invalid device-sync storage destination');
  }
  return uri;
}

class DeviceSyncProbeResult {
  DeviceSyncProbeResult._(this.localID, this.state, this.received, this.reset,
      this.mode, this.partSize, this.doneParts);
  final String localID, mode;
  final DeviceSyncMediaState state;
  final int received, partSize;
  final bool reset;
  final List<int> doneParts;

  factory DeviceSyncProbeResult.fromJson(Object? value, DeviceSyncMedia media) {
    media.validate();
    final json = deviceSyncJson(value);
    final id = _string(json, 'localID');
    if (id != media.localID) {
      throw const FormatException('Device-sync probe ID mismatch');
    }
    final state = _state(json, conflict: true);
    final received = _int(json, 'received');
    final reset = json['reset'];
    final mode = _string(json, 'mode');
    final partSize = _int(json, 'partSize');
    if (reset is! bool ||
        !const {'', 'put', 'multipart'}.contains(mode) ||
        (state != DeviceSyncMediaState.conflict && received > media.size) ||
        (state == DeviceSyncMediaState.done && received != media.size)) {
      throw const FormatException('Invalid device-sync probe progress');
    }
    final count = (media.size + deviceSyncPartSize - 1) ~/ deviceSyncPartSize;
    final done = _doneParts(json['doneParts'], mode == '' ? 0 : count);
    if ((mode == '' && partSize != 0) ||
        (mode == 'put' &&
            (media.size > deviceSyncPartSize || partSize != media.size)) ||
        (mode == 'multipart' &&
            (media.size <= deviceSyncPartSize ||
                partSize != deviceSyncPartSize ||
                done.fold<int>(
                        0, (sum, part) => sum + _partBytes(part, media.size)) !=
                    received))) {
      throw const FormatException('Invalid device-sync probe parts');
    }
    return DeviceSyncProbeResult._(
        id, state, received, reset, mode, partSize, done);
  }
}

class DeviceSyncUploadPart {
  DeviceSyncUploadPart._(this.partNumber, this.offset, this.size, this.url);
  final int partNumber, offset, size;
  final Uri url;
}

class DeviceSyncUploadTicket {
  DeviceSyncUploadTicket._(
      this.media,
      this.state,
      this.mode,
      this.contentType,
      this.size,
      this.received,
      this.partSize,
      this.expiresAt,
      this.uploadID,
      this.doneParts,
      this.pendingParts);
  final DeviceSyncMedia media;
  final DeviceSyncMediaState state;
  final String mode, contentType, uploadID;
  final int size, received, partSize, expiresAt;
  final List<int> doneParts;
  final List<DeviceSyncUploadPart> pendingParts;

  void checkExpiration(DateTime now) {
    if (state != DeviceSyncMediaState.done &&
        expiresAt <= now.millisecondsSinceEpoch) {
      throw const FormatException('Expired device-sync upload ticket');
    }
  }

  factory DeviceSyncUploadTicket.fromJson(Object? value, DeviceSyncMedia media,
      {required DateTime now}) {
    media.validate();
    final json = deviceSyncJson(value);
    final state = _state(json);
    final size = _int(json, 'size');
    final received = _int(json, 'received');
    if (size != media.size ||
        received > size ||
        (state == DeviceSyncMediaState.done && received != size)) {
      throw const FormatException('Device-sync ticket size mismatch');
    }
    if (state == DeviceSyncMediaState.done) {
      if ((json['url'] != null && json['url'] != '') ||
          (json['parts'] != null &&
              (json['parts'] is! List || (json['parts'] as List).isNotEmpty))) {
        throw const FormatException(
            'Completed device-sync ticket has destinations');
      }
      if ((json['contentType'] != null &&
              json['contentType'] != media.contentType) ||
          (json['mode'] != null &&
              !const {'', 'put', 'multipart'}.contains(json['mode']))) {
        throw const FormatException(
            'Invalid completed device-sync ticket metadata');
      }
      final count = (size + deviceSyncPartSize - 1) ~/ deviceSyncPartSize;
      final done = json['doneParts'] == null
          ? <int>[]
          : _doneParts(json['doneParts'], count);
      if (json['expiresAt'] != null) _int(json, 'expiresAt');
      if (json['partSize'] != null) _int(json, 'partSize');
      return DeviceSyncUploadTicket._(media, state, '', media.contentType, size,
          received, 0, 0, '', List.unmodifiable(done), const []);
    }
    final mode = _string(json, 'mode');
    final contentType = _string(json, 'contentType');
    final expires = _int(json, 'expiresAt');
    final partSize = _int(json, 'partSize');
    final uploadID = _string(json, 'uploadID');
    final url = _string(json, 'url');
    final parts = json['parts'];
    final count = (size + deviceSyncPartSize - 1) ~/ deviceSyncPartSize;
    final done = _doneParts(json['doneParts'], count);
    if (contentType != media.contentType ||
        expires <= now.millisecondsSinceEpoch ||
        parts is! List) {
      throw const FormatException('Invalid device-sync ticket metadata');
    }
    final pending = <DeviceSyncUploadPart>[];
    if (mode == 'put') {
      if (size > deviceSyncPartSize ||
          partSize != size ||
          uploadID.isNotEmpty ||
          received != 0 ||
          done.isNotEmpty ||
          parts.isNotEmpty) {
        throw const FormatException('Invalid device-sync PUT ticket');
      }
      pending.add(DeviceSyncUploadPart._(1, 0, size, deviceSyncOSSUri(url)));
    } else if (mode == 'multipart') {
      if (size <= deviceSyncPartSize ||
          partSize != deviceSyncPartSize ||
          uploadID.isEmpty ||
          url.isNotEmpty ||
          done.fold<int>(0, (sum, part) => sum + _partBytes(part, size)) !=
              received) {
        throw const FormatException('Invalid device-sync multipart ticket');
      }
      final numbers = done.toSet();
      final urls = <Uri>{};
      for (final value in parts) {
        final part = deviceSyncJson(value);
        final number = _int(part, 'partNumber');
        final offset = _int(part, 'offset');
        final bytes = _int(part, 'size');
        final destination = deviceSyncOSSUri(_string(part, 'url'));
        if (number < 1 ||
            number > count ||
            !numbers.add(number) ||
            offset != (number - 1) * deviceSyncPartSize ||
            bytes != _partBytes(number, size) ||
            !urls.add(destination)) {
          throw const FormatException('Invalid device-sync pending part');
        }
        pending.add(DeviceSyncUploadPart._(number, offset, bytes, destination));
      }
      if (numbers.length != count) {
        throw const FormatException('Missing device-sync upload part');
      }
      pending.sort((a, b) => a.partNumber.compareTo(b.partNumber));
    } else {
      throw const FormatException('Invalid device-sync upload mode');
    }
    return DeviceSyncUploadTicket._(
        media,
        state,
        mode,
        contentType,
        size,
        received,
        partSize,
        expires,
        uploadID,
        done,
        List.unmodifiable(pending));
  }
}

class DeviceSyncFinishResult {
  DeviceSyncFinishResult._(this.state, this.size, this.received);
  final DeviceSyncMediaState state;
  final int size, received;
  factory DeviceSyncFinishResult.fromJson(
      Object? value, DeviceSyncMedia media) {
    media.validate();
    final json = deviceSyncJson(value);
    final state = _state(json);
    final size = _int(json, 'size'), received = _int(json, 'received');
    if (size != media.size ||
        received > size ||
        (state == DeviceSyncMediaState.done && received != size)) {
      throw const FormatException('Device-sync completion size mismatch');
    }
    return DeviceSyncFinishResult._(state, size, received);
  }
}

class DeviceSyncLocation {
  const DeviceSyncLocation(
      {required this.clientID,
      required this.latitude,
      required this.longitude,
      required this.accuracy,
      required this.recordedAt});
  final String clientID;
  final double latitude, longitude, accuracy;
  final int recordedAt;
  Map<String, dynamic> toJson({required DateTime now}) {
    deviceSyncValidateID(clientID);
    if (!latitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        !longitude.isFinite ||
        longitude < -180 ||
        longitude > 180 ||
        !accuracy.isFinite ||
        accuracy < 0 ||
        accuracy > 10000000 ||
        recordedAt < DateTime.utc(2000).millisecondsSinceEpoch ||
        recordedAt > now.millisecondsSinceEpoch + 5 * 60 * 1000) {
      throw ArgumentError('Invalid device-sync location');
    }
    return {
      'clientID': clientID,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'recordedAt': recordedAt
    };
  }
}

class DeviceSyncLocationsResult {
  DeviceSyncLocationsResult._(this.stored, this.duplicated);
  final int stored, duplicated;
  factory DeviceSyncLocationsResult.fromJson(Object? value, int uniqueCount) {
    final json = deviceSyncJson(value);
    final stored = _int(json, 'stored'), duplicated = _int(json, 'duplicated');
    if (stored + duplicated != uniqueCount) {
      throw const FormatException(
          'Device-sync location acknowledgement mismatch');
    }
    return DeviceSyncLocationsResult._(stored, duplicated);
  }
}
