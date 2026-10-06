// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:dio/dio.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_transfer.dart';
import 'package:openim/pages/group_features/sangong/utils/api_response_util.dart';

class SangongTransfersApi {
  SangongTransfersApi({required Dio dio, this.scopedOptions}) : _dio = dio;
  final Dio _dio;
  final Options Function()? scopedOptions;

  Future<List<SangongTransfer>> fetch({
    String direction = 'all',
    int limit = 100,
    int? sessionId,
  }) async {
    if (!const ['all', 'out', 'in'].contains(direction)) {
      throw ArgumentError.value(direction, 'direction');
    }
    if (limit < 1 || limit > 500) {
      throw ArgumentError.value(limit, 'limit');
    }
    if (sessionId != null && sessionId <= 0) {
      throw ArgumentError.value(sessionId, 'sessionId');
    }
    final response = await _dio.get(
      '/api/v1/me/transfers',
      options: scopedOptions?.call(),
      queryParameters: {
        'direction': direction,
        'limit': limit,
        if (sessionId != null) 'sessionId': sessionId,
      },
    );
    final envelope = readApiWriteEnvelope(response.data);
    final payload = envelope.payload;
    if (envelope.isBusinessError ||
        (response.data is Map && response.data['ok'] == false) ||
        (payload is Map && payload['ok'] == false)) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
    }
    if (payload is! Map || payload['transfers'] is! List) {
      throw const FormatException('Invalid transfers response');
    }
    final records = (payload['transfers'] as List).map((item) {
      if (item is! Map) throw const FormatException('Invalid transfer');
      return SangongTransfer.fromJson(Map<String, dynamic>.from(item));
    }).toList();
    records.sort((a, b) => b.id.compareTo(a.id));
    return records;
  }
}
