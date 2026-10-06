import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'customer_service_config.dart';
import 'customer_service_contact.dart';
import 'customer_service_message.dart';

/// Public visitor API; its owned client never receives OpenIM account tokens.
/// Native TLS validation is deliberately kept enabled.
class CustomerServiceApi {
  CustomerServiceApi({
    Dio? client,
    this.config = const CustomerServiceConfig(),
  })  : _ownsClient = client == null,
        _client = client ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 120),
              sendTimeout: const Duration(seconds: 120),
            ));

  final CustomerServiceConfig config;
  static const int maxAttachmentBytes = 40 * 1024 * 1024;
  final Dio _client;
  final bool _ownsClient;
  final Set<CancelToken> _requests = {};
  bool _disposed = false;

  String get _contacts {
    final inbox = config.inboxIdentifier.trim();
    if (inbox.isEmpty) throw StateError('Customer service inbox is empty');
    return '${config.normalizedBaseUrl}/public/api/v1/inboxes/'
        '${Uri.encodeComponent(inbox)}/contacts';
  }

  String _contact(String sourceId) =>
      '$_contacts/${Uri.encodeComponent(_required(sourceId, 'contact'))}';

  String _messages(String contactId, String conversationId) =>
      '${_contact(contactId)}/conversations/'
      '${Uri.encodeComponent(_required(conversationId, 'conversation'))}/messages';

  Future<dynamic> _request(String method, String url, {dynamic data}) async {
    if (_disposed) throw StateError('Customer service API is disposed');
    final cancellation = CancelToken();
    _requests.add(cancellation);
    try {
      final response = await _client.request<dynamic>(url,
          data: data,
          cancelToken: cancellation,
          options: Options(
            method: method,
            contentType: data is FormData ? null : Headers.jsonContentType,
          ));
      if (_disposed) throw StateError('Customer service API is disposed');
      return response.data is String
          ? jsonDecode(response.data as String)
          : response.data;
    } finally {
      _requests.remove(cancellation);
    }
  }

  Future<CustomerServiceContact> createContact({
    required String identifier,
    required String name,
    String avatarUrl = '',
  }) async {
    final body = _profile(name, avatarUrl)
      ..['identifier'] = _required(identifier, 'identifier');
    final map = _map(await _request('POST', _contacts, data: body));
    return CustomerServiceContact(
      sourceId: _required(map['source_id']?.toString() ?? '', 'source_id'),
      pubsubToken:
          _required(map['pubsub_token']?.toString() ?? '', 'pubsub_token'),
    );
  }

  Future<void> updateContact({
    required String sourceId,
    required String name,
    String avatarUrl = '',
  }) async {
    await _request('PATCH', _contact(sourceId),
        data: _profile(name, avatarUrl));
  }

  Future<String> createConversation(String sourceId) async {
    final map = _map(await _request(
        'POST', '${_contact(sourceId)}/conversations',
        data: <String, dynamic>{}));
    return _required(map['id']?.toString() ?? '', 'conversation id');
  }

  Future<List<CustomerServiceMessage>> listMessages({
    required String contactId,
    required String conversationId,
  }) async {
    final raw = await _request('GET', _messages(contactId, conversationId));
    final List<dynamic> rows;
    if (raw is List) {
      rows = raw;
    } else if (raw is Map) {
      final candidates = [raw['payload'], raw['messages'], raw['data']];
      final lists = candidates.whereType<List>();
      if (lists.isEmpty) throw const FormatException('Invalid message history');
      rows = lists.first;
    } else {
      throw const FormatException('Invalid message history');
    }
    return rows
        .whereType<Map>()
        .map((row) => CustomerServiceMessage.fromJson(
            Map<String, dynamic>.from(row),
            config: config))
        .toList();
  }

  Future<CustomerServiceMessage> sendText({
    required String contactId,
    required String conversationId,
    required String content,
    required String echoId,
  }) async {
    final raw = await _request('POST', _messages(contactId, conversationId),
        data: {'content': content, 'echo_id': _required(echoId, 'echo_id')});
    return _sentMessage(raw);
  }

  Future<CustomerServiceMessage> sendAttachment({
    required String contactId,
    required String conversationId,
    required String echoId,
    required String filename,
    required String path,
    List<int>? bytes,
    int width = 0,
    int height = 0,
    String content = '',
    String thumbnailPath = '',
    List<int>? thumbnailBytes,
  }) async {
    final size = bytes != null && bytes.isNotEmpty
        ? bytes.length
        : (path.trim().isEmpty ? 0 : await File(path).length());
    if (size > maxAttachmentBytes) {
      throw ArgumentError('Attachments must be 40MB or smaller');
    }
    final form = FormData();
    form.fields.addAll([
      MapEntry('content', content),
      MapEntry('echo_id', _required(echoId, 'echo_id')),
      if (width > 0 && height > 0) ...[
        MapEntry('width', '$width'),
        MapEntry('height', '$height'),
      ],
    ]);
    form.files.add(MapEntry('attachments[]',
        await _file(filename: filename, path: path, bytes: bytes)));
    if (thumbnailPath.isNotEmpty ||
        (thumbnailBytes != null && thumbnailBytes.isNotEmpty)) {
      form.files.add(MapEntry(
          'thumbnail',
          await _file(
              filename: 'cover.jpg',
              path: thumbnailPath,
              bytes: thumbnailBytes)));
    }
    return _sentMessage(await _request(
        'POST', _messages(contactId, conversationId),
        data: form));
  }

  CustomerServiceMessage _sentMessage(dynamic raw) {
    final message = CustomerServiceMessage.fromJson(_map(raw), config: config);
    _required(message.id, 'message id');
    return message;
  }

  Future<MultipartFile> _file({
    required String filename,
    required String path,
    List<int>? bytes,
  }) async {
    final mediaType = DioMediaType.parse(_mime(filename));
    if (bytes != null && bytes.isNotEmpty) {
      return MultipartFile.fromBytes(bytes,
          filename: filename, contentType: mediaType);
    }
    if (path.trim().isNotEmpty) {
      return MultipartFile.fromFile(path,
          filename: filename, contentType: mediaType);
    }
    throw ArgumentError('Attachment has no readable content');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final request in _requests) {
      request.cancel('Customer service closed');
    }
    _requests.clear();
    if (_ownsClient) _client.close(force: true);
  }
}

Map<String, dynamic> _profile(String name, String avatar) {
  final publicAvatar = customerServicePublicAvatarUrl(avatar);
  return {
    'name': name.trim().isEmpty ? '访客' : name.trim(),
    if (publicAvatar.isNotEmpty) 'avatar_url': publicAvatar,
  };
}

/// Avatar uploads use public URLs only; no signed query or local account URL.
String customerServicePublicAvatarUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null ||
      !const ['http', 'https'].contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return '';
  }
  final host = uri.host.toLowerCase();
  if (host == 'localhost' ||
      host == '::1' ||
      host == '0.0.0.0' ||
      host.endsWith('.local') ||
      host.startsWith('127.') ||
      host.startsWith('10.') ||
      host.startsWith('192.168.') ||
      host.startsWith('169.254.') ||
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(host) ||
      (host.contains(':') &&
          (host.startsWith('fc') ||
              host.startsWith('fd') ||
              host.startsWith('fe80')))) {
    return '';
  }
  return uri.toString();
}

String _required(String raw, String label) {
  final value = raw.trim();
  if (value.isEmpty) throw StateError('Customer service $label is missing');
  return value;
}

Map<String, dynamic> _map(dynamic raw) {
  if (raw is! Map) {
    throw const FormatException('Invalid customer service response');
  }
  if (raw['payload'] is Map &&
      !raw.containsKey('id') &&
      !raw.containsKey('source_id')) {
    return Map<String, dynamic>.from(raw['payload'] as Map);
  }
  return Map<String, dynamic>.from(raw);
}

String _mime(String name) {
  final extension = name.toLowerCase().split('.').last;
  return switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'mp4' => 'video/mp4',
    'mov' => 'video/quicktime',
    'pdf' => 'application/pdf',
    _ => 'application/octet-stream',
  };
}
