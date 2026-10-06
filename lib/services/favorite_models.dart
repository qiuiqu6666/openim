import 'package:flutter/foundation.dart';

enum FavoriteKind {
  text,
  image,
  video,
  audio,
  file,
  note,
  link,
  location,
  contact,
  messageBundle,
  unknown;

  String get wireName => this == messageBundle ? 'message_bundle' : name;
  bool get isP0 => {
        FavoriteKind.text,
        FavoriteKind.image,
        FavoriteKind.video,
        FavoriteKind.audio,
        FavoriteKind.file,
        FavoriteKind.note,
        FavoriteKind.link
      }.contains(this);
  static FavoriteKind parse(String value) => FavoriteKind.values.firstWhere(
        (kind) => kind.wireName == value,
        orElse: () => FavoriteKind.unknown,
      );
}

enum FavoriteStatus {
  pendingArchive,
  ready,
  failed,
  deleted,
  unknown;

  String get wireName => switch (this) {
        pendingArchive => 'pending_archive',
        failed => 'archive_failed',
        _ => name
      };
  // Read the earlier cache spelling without sending it to the final API.
  static FavoriteStatus parse(String value) => FavoriteStatus.values.firstWhere(
        (status) =>
            status.wireName == value || (status == failed && value == 'failed'),
        orElse: () => FavoriteStatus.unknown,
      );
}

Map<String, dynamic> favoriteJsonMap(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Invalid favorite object');
  }
  return Map<String, dynamic>.from(value);
}

String _string(Map<String, dynamic> map, String key, {bool optional = false}) {
  final value = map[key];
  if (optional && value == null) return '';
  if (value is! String || (!optional && value.trim().isEmpty)) {
    throw FormatException('Invalid favorite $key');
  }
  return value;
}

/// Optional Go string fields can be encoded as either null or an empty string.
/// Wrong types still reject the DTO instead of silently coercing identifiers.
String? _nullableString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('Invalid favorite $key');
  return value.trim().isEmpty ? null : value;
}

int _integer(Map<String, dynamic> map, String key, {int? fallback}) {
  final value = map[key];
  if (value == null && fallback != null) return fallback;
  if (value is! int || value < 0) {
    throw FormatException('Invalid favorite $key');
  }
  return value;
}

int? _optionalInt(Map<String, dynamic> map, String key) =>
    map[key] == null ? null : _integer(map, key);

DateTime? _time(Map<String, dynamic> map, String key) {
  final value = _optionalInt(map, key);
  if (value == null) return null;
  try {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  } on ArgumentError {
    throw FormatException('Invalid favorite $key');
  }
}

List<T> _list<T>(Map<String, dynamic> map, String key,
    T Function(Map<String, dynamic>) parse) {
  final values = map[key];
  if (values == null) return <T>[];
  if (values is! List) throw FormatException('Invalid favorite $key');
  return List<T>.unmodifiable(
      values.map((value) => parse(favoriteJsonMap(value))));
}

@immutable
class FavoriteBlock {
  const FavoriteBlock(
      {required this.id,
      required this.type,
      this.text,
      this.assetID,
      this.hasWireID = true,
      this.data = const {}});
  final String id;
  final String type;
  final String? text;
  final String? assetID;

  /// Authored blocks send their stable ID. Parsed legacy blocks without a wire
  /// ID preserve their original body when replayed with an existing request ID.
  final bool hasWireID;

  /// Type-specific, inert content. It is never passed directly to the IM SDK.
  final Map<String, dynamic> data;

  factory FavoriteBlock.fromJson(Map<String, dynamic> json,
      {String fallbackID = 'b1'}) {
    final text = json['text'];
    final assetID = json['assetID'];
    if ((text != null && text is! String) ||
        (assetID != null && (assetID is! String || assetID.isEmpty))) {
      throw const FormatException('Invalid favorite block');
    }
    return FavoriteBlock(
        id: json['id'] == null ? fallbackID : _string(json, 'id'),
        hasWireID: json['id'] != null,
        type: _string(json, 'type'),
        text: text as String?,
        assetID: assetID as String?,
        data: Map.unmodifiable(json));
  }

  Map<String, dynamic> toJson() => {
        ...data,
        if (hasWireID) 'id': id,
        'type': type,
        if (text != null) 'text': text,
        if (assetID != null) 'assetID': assetID
      };
}

@immutable
class FavoriteContent {
  const FavoriteContent({required this.kind, required this.blocks});
  final FavoriteKind kind;
  final List<FavoriteBlock> blocks;
  String get text => blocks
      .where((block) => block.type == 'text')
      .map((block) => block.text ?? '')
      .join('\n');
  factory FavoriteContent.fromJson(Map<String, dynamic> json,
      {FavoriteKind? kind}) {
    final resolved =
        json['kind'] == null ? kind : FavoriteKind.parse(_string(json, 'kind'));
    if (resolved == null || json['blocks'] is! List) {
      throw const FormatException('Invalid favorite content');
    }
    final values = json['blocks'] as List;
    final blocks = List<FavoriteBlock>.unmodifiable(List.generate(
        values.length,
        (index) => FavoriteBlock.fromJson(favoriteJsonMap(values[index]),
            fallbackID: 'block_$index')));
    if (blocks.map((block) => block.id).toSet().length != blocks.length) {
      throw const FormatException('Duplicate favorite block');
    }
    return FavoriteContent(kind: resolved, blocks: blocks);
  }
  Map<String, dynamic> toJson() => {
        'kind': kind.wireName,
        'blocks': blocks.map((block) => block.toJson()).toList()
      };
}

@immutable
class FavoriteAsset {
  const FavoriteAsset(
      {required this.id,
      this.role = 'original',
      required this.mimeType,
      required this.sizeBytes,
      required this.sha256,
      this.width,
      this.height,
      this.durationMs,
      this.fileName,
      this.coverAssetID,
      this.codec});
  final String id;
  final String role;
  final String mimeType;
  final int sizeBytes;
  final String sha256;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? fileName;
  final String? coverAssetID;
  final String? codec;
  factory FavoriteAsset.fromJson(Map<String, dynamic> json) {
    final hash = _string(json, 'sha256');
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('Invalid favorite checksum');
    }
    return FavoriteAsset(
        id: _string(json, json.containsKey('id') ? 'id' : 'assetID'),
        role: _string(json, 'role', optional: true).isEmpty
            ? 'original'
            : json['role'] as String,
        mimeType: _string(json, 'mimeType'),
        sizeBytes: _integer(json, 'sizeBytes'),
        sha256: hash.toLowerCase(),
        width: _optionalInt(json, 'width'),
        height: _optionalInt(json, 'height'),
        durationMs: _optionalInt(json, 'durationMs'),
        fileName: json['fileName'] == null
            ? null
            : _string(json, 'fileName', optional: true),
        coverAssetID: _nullableString(json, 'coverAssetID'),
        codec: _nullableString(json, 'codec'));
  }
  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'sha256': sha256,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (durationMs != null) 'durationMs': durationMs,
        if (fileName != null) 'fileName': fileName,
        if (coverAssetID != null) 'coverAssetID': coverAssetID,
        if (codec != null) 'codec': codec
      };
}

@immutable
class FavoriteSource {
  const FavoriteSource(
      {this.conversationID,
      this.clientMsgID,
      this.serverMsgID,
      this.sequence,
      this.displayName,
      this.sentAt});
  final String? conversationID;
  final String? clientMsgID;
  final String? serverMsgID;
  final int? sequence;
  final String? displayName;
  final DateTime? sentAt;
  factory FavoriteSource.fromJson(Map<String, dynamic> json) => FavoriteSource(
      conversationID: _nullableString(json, 'conversationID'),
      clientMsgID: _nullableString(json, 'clientMsgID'),
      serverMsgID: _nullableString(json, 'serverMsgID'),
      sequence: _optionalInt(json, 'sequence'),
      displayName: json['displayName'] == null
          ? null
          : _string(json, 'displayName', optional: true),
      sentAt: _time(json, 'sentAt'));
  Map<String, dynamic> toJson() => {
        if (conversationID != null) 'conversationID': conversationID,
        if (clientMsgID != null) 'clientMsgID': clientMsgID,
        if (serverMsgID != null) 'serverMsgID': serverMsgID,
        if (sequence != null) 'sequence': sequence,
        if (displayName != null) 'displayName': displayName,
        if (sentAt != null) 'sentAt': sentAt!.millisecondsSinceEpoch
      };
}

@immutable
class FavoriteTag {
  const FavoriteTag({required this.id, required this.name, this.version = 1});
  final String id;
  final String name;
  final int version;
  factory FavoriteTag.fromJson(Map<String, dynamic> json) => FavoriteTag(
      id: _string(json, 'id'),
      name: _string(json, 'name'),
      version: _integer(json, 'version', fallback: 1));
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'version': version};
}

@immutable
class FavoriteChange {
  const FavoriteChange(
      {required this.id,
      required this.version,
      required this.operation,
      required this.updatedAt,
      this.item});
  final String id;
  final int version;
  final String operation;
  final int updatedAt;
  final FavoriteItem? item;
  factory FavoriteChange.fromJson(Map<String, dynamic> json) {
    final operation = json['operation'] == null
        ? (json['item'] != null || json['kind'] != null ? 'upsert' : 'delete')
        : _string(json, 'operation');
    if (!{'upsert', 'delete'}.contains(operation)) {
      throw const FormatException('Invalid favorite change operation');
    }
    final item = operation == 'delete'
        ? null
        : FavoriteItem.fromJson(
            json['item'] == null ? json : favoriteJsonMap(json['item']));
    final id = json['id'] == null && json['favoriteID'] == null && item != null
        ? item.id
        : _string(json, json.containsKey('favoriteID') ? 'favoriteID' : 'id');
    final version = json['version'] == null && item != null
        ? item.version
        : _integer(json, 'version');
    final updatedAt = json['updatedAt'] == null && item?.updatedAt != null
        ? item!.updatedAt!.millisecondsSinceEpoch
        : _integer(json, 'updatedAt');
    if (version < 1 ||
        (operation == 'upsert' &&
            (item == null || item.id != id || item.version != version))) {
      throw const FormatException('Invalid favorite change');
    }
    return FavoriteChange(
        id: id,
        version: version,
        operation: operation,
        updatedAt: updatedAt,
        item: item);
  }
}

@immutable
class FavoriteChangesPage {
  const FavoriteChangesPage(
      {required this.events, required this.syncAt, this.limit = 100});
  final List<FavoriteChange> events;
  final int syncAt;
  final int limit;
  bool get hasMore => events.length >= limit;
  factory FavoriteChangesPage.fromJson(Map<String, dynamic> json,
      {int limit = 100}) {
    final values = json['events'] ?? json['items'] ?? json['changes'];
    if (values is! List) {
      throw const FormatException('Invalid favorite changes page');
    }
    return FavoriteChangesPage(
        events: List.unmodifiable(values
            .map((value) => FavoriteChange.fromJson(favoriteJsonMap(value)))),
        syncAt: _integer(json, 'syncAt'),
        limit: limit);
  }
}

@immutable
class FavoriteItem {
  const FavoriteItem(
      {required this.id,
      required this.kind,
      this.rawKind,
      required this.title,
      this.summary = '',
      this.coverAssetID,
      this.totalBytes,
      required this.version,
      this.schemaVersion = 1,
      this.contentRevision,
      this.createdAt,
      this.updatedAt,
      required this.status,
      this.rawStatus,
      this.content,
      this.assets = const [],
      this.source,
      this.tags = const [],
      this.provenance});
  final String id;
  final FavoriteKind kind;
  final String? rawKind;
  final String title;
  final String summary;
  final String? coverAssetID;
  final int? totalBytes;
  final int version;
  final int schemaVersion;
  final String? contentRevision;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final FavoriteStatus status;
  final String? rawStatus;
  final FavoriteContent? content;
  final List<FavoriteAsset> assets;
  final FavoriteSource? source;
  final List<FavoriteTag> tags;
  final String? provenance;
  String get text => content?.text ?? summary;
  List<FavoriteBlock> get blocks => content?.blocks ?? const [];
  bool get isReady => status == FavoriteStatus.ready;
  bool get isSupported => kind.isP0 && schemaVersion == 1;
  bool get canSend =>
      isReady &&
      isSupported &&
      {
        FavoriteKind.text,
        FavoriteKind.note,
        FavoriteKind.image,
        FavoriteKind.video,
        FavoriteKind.audio,
        FavoriteKind.file,
        FavoriteKind.link
      }.contains(kind);
  factory FavoriteItem.fromJson(Map<String, dynamic> json) {
    final wireKind = _string(json, 'kind');
    final kind = FavoriteKind.parse(wireKind);
    final wireStatus = _string(json, 'status');
    final version = _integer(json, 'version');
    if (version == 0) throw const FormatException('Invalid favorite version');
    return FavoriteItem(
        id: _string(json, 'id'),
        kind: kind,
        rawKind: wireKind,
        title: _string(json, 'title', optional: true),
        summary: _string(json, 'summary', optional: true),
        coverAssetID: _nullableString(json, 'coverAssetID'),
        totalBytes: _optionalInt(json, 'totalBytes'),
        version: version,
        schemaVersion: _integer(json, 'schemaVersion', fallback: 1),
        contentRevision: _nullableString(json, 'contentRevision'),
        createdAt: _time(json, 'createdAt'),
        updatedAt: _time(json, 'updatedAt'),
        status: FavoriteStatus.parse(wireStatus),
        rawStatus: wireStatus,
        content: json['content'] == null
            ? null
            : FavoriteContent.fromJson(favoriteJsonMap(json['content']),
                kind: kind),
        assets: _list(json, 'assets', FavoriteAsset.fromJson),
        source: json['source'] == null
            ? null
            : FavoriteSource.fromJson(favoriteJsonMap(json['source'])),
        tags: _list(json, 'tags', FavoriteTag.fromJson),
        provenance:
            json['provenance'] == null ? null : _string(json, 'provenance'));
  }

  /// Lightweight metadata only. Neither original bytes nor access URLs are cached here.
  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'kind': rawKind ?? kind.wireName,
        'title': title,
        'summary': summary,
        'version': version,
        'schemaVersion': schemaVersion,
        if (coverAssetID != null) 'coverAssetID': coverAssetID,
        if (totalBytes != null) 'totalBytes': totalBytes,
        if (provenance != null) 'provenance': provenance,
        'status': rawStatus ?? status.wireName,
        if (contentRevision != null) 'contentRevision': contentRevision,
        if (createdAt != null) 'createdAt': createdAt!.millisecondsSinceEpoch,
        if (updatedAt != null) 'updatedAt': updatedAt!.millisecondsSinceEpoch,
        'tags': tags.map((tag) => tag.toJson()).toList()
      };
}

@immutable
class FavoritePage {
  const FavoritePage({required this.items, this.nextCursor, this.syncAt = 0});
  final List<FavoriteItem> items;
  final String? nextCursor;
  final int syncAt;
  factory FavoritePage.fromJson(Map<String, dynamic> json) {
    if (json['items'] is! List) {
      throw const FormatException('Invalid favorites page');
    }
    final items = _list(json, 'items', FavoriteItem.fromJson);
    if (items.map((item) => item.id).toSet().length != items.length) {
      throw const FormatException('Duplicate favorite IDs');
    }
    return FavoritePage(
        items: items,
        nextCursor:
            json['nextCursor'] == null ? null : _string(json, 'nextCursor'),
        syncAt: _integer(json, 'syncAt'));
  }
}

@immutable
class FavoriteDownload {
  const FavoriteDownload(
      {required this.assetID,
      required this.url,
      required this.sizeBytes,
      required this.sha256,
      this.expiresAt});
  final String assetID;
  final Uri url;
  final int sizeBytes;
  final String sha256;
  final DateTime? expiresAt;
  factory FavoriteDownload.fromJson(Map<String, dynamic> json,
      {DateTime? leaseExpiresAt}) {
    final uri = Uri.tryParse(_string(json, 'url'));
    final hash = _string(json, 'sha256');
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('Invalid favorite download authorization');
    }
    final expiresAt = _time(json, 'expiresAt');
    final effectiveExpiry = expiresAt == null
        ? leaseExpiresAt
        : leaseExpiresAt != null && leaseExpiresAt.isBefore(expiresAt)
            ? leaseExpiresAt
            : expiresAt;
    return FavoriteDownload(
        assetID: _string(json, 'assetID'),
        url: uri,
        sizeBytes: _integer(json, 'sizeBytes'),
        sha256: hash.toLowerCase(),
        expiresAt: effectiveExpiry);
  }
}

@immutable
class FavoritePreparedSend {
  const FavoritePreparedSend(
      {required this.prepareID,
      required this.contentRevision,
      required this.expiresAt,
      required this.sendContent,
      required this.downloads});
  final String prepareID;
  final String contentRevision;
  final DateTime expiresAt;
  final FavoriteContent sendContent;
  final List<FavoriteDownload> downloads;
  factory FavoritePreparedSend.fromJson(Map<String, dynamic> json) {
    final expiry = _time(json, 'expiresAt');
    if (expiry == null ||
        (json['downloads'] != null && json['downloads'] is! List)) {
      throw const FormatException('Invalid favorite preparation');
    }
    final downloads = _list(json, 'downloads',
        (wire) => FavoriteDownload.fromJson(wire, leaseExpiresAt: expiry));
    if (downloads.map((item) => item.assetID).toSet().length !=
        downloads.length) {
      throw const FormatException('Duplicate prepared favorite asset');
    }
    final content =
        FavoriteContent.fromJson(favoriteJsonMap(json['sendContent']));
    final ids = downloads.map((value) => value.assetID).toSet();
    if (content.blocks.any(
        (block) => block.assetID != null && !ids.contains(block.assetID))) {
      throw const FormatException('Missing prepared favorite asset');
    }
    return FavoritePreparedSend(
        prepareID: _string(json, 'prepareID'),
        contentRevision: _string(json, 'contentRevision'),
        expiresAt: expiry,
        sendContent: content,
        downloads: downloads);
  }
}

@immutable
class FavoriteUploadSession {
  const FavoriteUploadSession(
      {required this.uploadID,
      required this.uploadURL,
      required this.expiresAt,
      required this.maxSizeBytes,
      this.contentType,
      this.method = 'PUT',
      this.headers = const {}});
  final String uploadID;
  final Uri uploadURL;
  final DateTime expiresAt;
  final int maxSizeBytes;

  /// The declared original MIME from upload initialization, kept only in memory.
  final String? contentType;
  final String method;
  final Map<String, String> headers;
  factory FavoriteUploadSession.fromJson(Map<String, dynamic> json,
      {String? declaredMimeType}) {
    final url = Uri.tryParse(_string(json, 'uploadURL'));
    final expiry = _time(json, 'expiresAt');
    final method =
        json['method'] == null ? 'PUT' : _string(json, 'method').toUpperCase();
    if (url == null ||
        !{'http', 'https'}.contains(url.scheme) ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        expiry == null ||
        method != 'PUT') {
      throw const FormatException('Invalid favorite upload session');
    }
    final headers = json['headers'] == null
        ? <String, dynamic>{}
        : favoriteJsonMap(json['headers']);
    if (headers.values.any((value) => value is! String)) {
      throw const FormatException('Invalid favorite upload headers');
    }
    return FavoriteUploadSession(
        uploadID: _string(json, 'uploadID'),
        uploadURL: url,
        expiresAt: expiry,
        maxSizeBytes: _integer(json, 'maxSizeBytes'),
        contentType: declaredMimeType,
        method: method,
        headers: Map.unmodifiable(headers.cast<String, String>()));
  }
}
