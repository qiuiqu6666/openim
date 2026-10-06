import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:openim_common/openim_common.dart' show Config, DataSp;
import 'package:uuid/uuid.dart';

import '../models/device_sync_models.dart';
export '../models/device_sync_models.dart';

class DeviceSyncException implements Exception {
  const DeviceSyncException(this.code, this.message,
      {this.isCancelled = false});
  final Object code;
  final String message;
  final bool isCancelled;
  bool get isAuthError =>
      code == 'AUTH_INVALID' ||
      code == 401 ||
      code == 20101 ||
      (code is int && (code as int) >= 1501 && (code as int) <= 1507);
  @override
  String toString() => message;
}

/// A captured Chat session, with a separate credential-free OSS transport.
/// Injection borrows adapters: closing this API never closes borrowed clients.
class DeviceSyncApi {
  DeviceSyncApi(
      {required this.device,
      String? chatToken,
      String? baseUrl,
      bool Function()? isCurrent,
      Dio? client,
      Dio? uploadClient,
      DateTime Function()? now})
      : chatToken = chatToken ?? DataSp.chatToken ?? '',
        baseUrl = _base(baseUrl ?? Config.appAuthUrl),
        _client = client ?? _newClient(),
        _ownsClient = client == null,
        _uploadClient = _newClient(),
        _ownsUploadAdapter = uploadClient == null,
        _now = now ?? DateTime.now {
    device.toJson();
    _isCurrent = isCurrent ??
        (() =>
            DataSp.chatToken == this.chatToken &&
            _base(Config.appAuthUrl) == this.baseUrl);
    _uploadClient.interceptors.clear();
    if (uploadClient != null) {
      _uploadClient.httpClientAdapter = uploadClient.httpClientAdapter;
    }
  }

  static Dio _newClient() => Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(minutes: 5),
      receiveTimeout: const Duration(minutes: 5)));
  static String _base(String value) {
    var base = value.replaceFirst(RegExp(r'/+$'), '');
    if (base.endsWith('/chat')) base = base.substring(0, base.length - 5);
    final uri = Uri.tryParse(base);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.authority.contains('@') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError('Invalid device-sync service address');
    }
    return base;
  }

  final DeviceSyncDevice device;
  final String chatToken, baseUrl;
  final Dio _client, _uploadClient;
  final bool _ownsClient, _ownsUploadAdapter;
  final DateTime Function() _now;
  late final bool Function() _isCurrent;
  final _requests = <CancelToken>{};
  bool _closed = false;

  void _check([CancelToken? cancellation]) {
    if (_closed || cancellation?.isCancelled == true || !_isCurrent()) {
      throw const DeviceSyncException('CANCELLED', '设备同步已停止',
          isCancelled: true);
    }
    if (chatToken.trim().isEmpty || chatToken.contains(RegExp(r'[\r\n]'))) {
      throw const DeviceSyncException('AUTH_INVALID', '设备同步需要有效的登录');
    }
  }

  CancelToken _begin(CancelToken? caller) {
    _check(caller);
    final token = CancelToken();
    _requests.add(token);
    caller?.whenCancel.then((_) {
      if (_requests.contains(token)) token.cancel('Device sync cancelled');
    });
    return token;
  }

  void close({bool force = true}) {
    if (_closed) return;
    _closed = true;
    for (final token in _requests.toList()) {
      token.cancel('Device sync closed');
    }
    if (_ownsClient) _client.close(force: force);
    if (_ownsUploadAdapter) _uploadClient.close(force: force);
  }

  Future<Map<String, dynamic>> _request(
      String path, Map<String, dynamic> body, CancelToken? cancellation) async {
    final token = _begin(cancellation);
    try {
      final response = await _client.post<dynamic>(
          '$baseUrl/chat/device-sync/$path',
          data: {...device.toJson(), ...body},
          cancelToken: token,
          options: Options(
              headers: {'token': chatToken, 'operationID': const Uuid().v4()},
              contentType: Headers.jsonContentType,
              followRedirects: false,
              maxRedirects: 0,
              validateStatus: (_) => true));
      _check(cancellation);
      if (response.statusCode == 401) {
        throw const DeviceSyncException(401, '设备同步登录已失效');
      }
      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300) {
        throw const DeviceSyncException('HTTP_ERROR', '设备同步服务暂不可用');
      }
      final envelope = deviceSyncJson(response.data);
      final code = envelope['errCode'];
      if (code is! int) {
        throw const FormatException('Invalid device-sync envelope');
      }
      if (code != 0) throw DeviceSyncException(code, '设备同步请求未完成');
      return deviceSyncJson(envelope['data']);
    } on DioException catch (error) {
      _check(cancellation);
      if (CancelToken.isCancel(error)) {
        throw const DeviceSyncException('CANCELLED', '设备同步已停止',
            isCancelled: true);
      }
      if (error.response?.statusCode == 401) {
        throw const DeviceSyncException(401, '设备同步登录已失效');
      }
      throw const DeviceSyncException('NETWORK_ERROR', '设备同步服务暂不可用');
    } finally {
      _requests.remove(token);
    }
  }

  Future<List<DeviceSyncProbeResult>> probe(List<DeviceSyncMedia> items,
      {CancelToken? cancelToken}) async {
    _check(cancelToken);
    if (items.isEmpty ||
        items.length > 50 ||
        items.map((item) => item.localID).toSet().length != items.length) {
      throw ArgumentError('Invalid device-sync probe batch');
    }
    final snapshots = List<DeviceSyncMedia>.of(items);
    final data = await _request(
        'media/probe',
        {'items': snapshots.map((item) => item.toJson()).toList()},
        cancelToken);
    _check(cancelToken);
    final rows = data['items'];
    if (rows is! List || rows.length != snapshots.length) {
      throw const FormatException('Invalid device-sync probe acknowledgement');
    }
    final byID = {for (final media in snapshots) media.localID: media};
    final results = <String, DeviceSyncProbeResult>{};
    for (final row in rows) {
      final json = deviceSyncJson(row);
      final media = byID[json['localID']];
      if (media == null || results.containsKey(media.localID)) {
        throw const FormatException('Device-sync probe identity mismatch');
      }
      results[media.localID] = DeviceSyncProbeResult.fromJson(json, media);
    }
    return List.unmodifiable(snapshots.map((item) => results[item.localID]!));
  }

  Future<DeviceSyncUploadTicket> ticket(DeviceSyncMedia media,
      {CancelToken? cancelToken}) async {
    _check(cancelToken);
    media.validate();
    final data =
        await _request('media/ticket', {'localID': media.localID}, cancelToken);
    _check(cancelToken);
    return DeviceSyncUploadTicket.fromJson(data, media, now: _now());
  }

  Future<DeviceSyncFinishResult> finish(DeviceSyncMedia media,
      {CancelToken? cancelToken}) async {
    _check(cancelToken);
    media.validate();
    final data =
        await _request('media/finish', {'localID': media.localID}, cancelToken);
    _check(cancelToken);
    return DeviceSyncFinishResult.fromJson(data, media);
  }

  Future<DeviceSyncLocationsResult> locations(List<DeviceSyncLocation> points,
      {CancelToken? cancelToken}) async {
    _check(cancelToken);
    if (points.isEmpty || points.length > 100) {
      throw ArgumentError('Invalid device-sync location batch');
    }
    final now = _now();
    final snapshots = List<DeviceSyncLocation>.of(points);
    final data = await _request(
        'locations',
        {'points': snapshots.map((point) => point.toJson(now: now)).toList()},
        cancelToken);
    _check(cancelToken);
    return DeviceSyncLocationsResult.fromJson(
        data, snapshots.map((point) => point.clientID).toSet().length);
  }

  Future<void> putPart(
      File file, DeviceSyncUploadTicket ticket, DeviceSyncUploadPart part,
      {CancelToken? cancelToken}) async {
    _check(cancelToken);
    ticket.checkExpiration(_now());
    if (!ticket.pendingParts.contains(part)) {
      throw ArgumentError('Part does not belong to the device-sync ticket');
    }
    deviceSyncOSSUri(part.url.toString());
    final int length;
    try {
      length = await file.length();
    } on FileSystemException {
      _check(cancelToken);
      throw const DeviceSyncException('FILE_UNAVAILABLE', '无法读取本机媒体');
    }
    _check(cancelToken);
    ticket.checkExpiration(_now());
    if (length != ticket.size) {
      throw const DeviceSyncException('FILE_CHANGED', '本机媒体已变化');
    }
    final token = _begin(cancelToken);
    try {
      final stream =
          file.openRead(part.offset, part.offset + part.size).map((chunk) {
        _check(cancelToken);
        return chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      });
      final response = await _uploadClient.put<dynamic>(part.url.toString(),
          data: stream,
          cancelToken: token,
          options: Options(
              headers: {
                Headers.contentTypeHeader: ticket.contentType,
                Headers.contentLengthHeader: part.size
              },
              responseType: ResponseType.plain,
              followRedirects: false,
              maxRedirects: 0,
              validateStatus: (_) => true));
      _check(cancelToken);
      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300) {
        throw const DeviceSyncException('UPLOAD_ERROR', '媒体上传尚未完成');
      }
    } on DioException catch (error) {
      _check(cancelToken);
      if (CancelToken.isCancel(error)) {
        throw const DeviceSyncException('CANCELLED', '设备同步已停止',
            isCancelled: true);
      }
      throw const DeviceSyncException('UPLOAD_ERROR', '媒体上传尚未完成');
    } finally {
      _requests.remove(token);
    }
  }
}
