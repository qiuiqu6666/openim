import 'dart:convert';
import 'package:brotli/brotli.dart';
import 'package:dio/dio.dart';
import 'bingo_draw.dart';

class BingoRepository {
  BingoRepository({Dio? client})
      : _client = client ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
            ));
  final Dio _client;
  CancelToken? _cancel;
  static const endpoint = 'https://kai365.cc/api/v1/trend/getInfo';

  Future<BingoDraw> fetch() async => BingoDraw.fromResponse(
      await _request(endpoint, const {'lotCode': '10214'}));

  Future<({List<BingoDraw> draws, bool hasMore})> fetchHistory(int page) async {
    final response = await _request(
        'https://kai365.cc/api/v1/trend/getHistoryList',
        {'lotCode': '10214', 'pageSize': 100, 'pageNum': page});
    final data = response['data'];
    if (response['code'] != 0 ||
        data is! Map ||
        data['list'] is! List ||
        data['pageNum'] != page ||
        data['pageCount'] is! int) {
      throw const FormatException('宾果历史数据格式错误');
    }
    final draws = (data['list'] as List).map((row) {
      if (row is! Map || row['groupCode'] != 'sixmark') {
        throw const FormatException('宾果历史记录格式错误');
      }
      // History drawIssue belongs to drawCode, unlike getInfo's pending issue.
      return BingoDraw.fromResponse({
        'code': 0,
        'data': {
          'lotCode': '10214',
          'preDrawIssue': row['drawIssue'],
          'preDrawCode': row['drawCode'],
          'preDrawTime': row['drawTime'],
          'drawIssue': row['drawIssue'],
          'drawTime': row['drawTime'],
          'serverTime': row['drawTime'],
          'result': row['result'],
        }
      });
    }).toList();
    return (
      draws: draws,
      hasMore: draws.isNotEmpty && page + 1 < data['pageCount']
    );
  }

  Future<Map<String, dynamic>> _request(
      String url, Map<String, dynamic> query) async {
    final cancel = _cancel = CancelToken();
    // Dedicated public client: no chat credentials, cookies, or group headers.
    final response = await _client.get<List<int>>(url,
        queryParameters: query,
        cancelToken: cancel,
        options: Options(
            responseType: ResponseType.bytes,
            headers: const {
              'Accept': 'application/json',
              'Accept-Encoding': 'gzip'
            },
            followRedirects: false));
    var bytes = response.data ?? const <int>[];
    if (bytes.length > 1024 * 1024) throw const FormatException('开奖响应过大');
    // This provider sends Brotli even when only gzip/identity was requested.
    // Browsers may already have decoded it while preserving the header.
    final first = bytes.where((b) => b > 32).firstOrNull;
    if (response.headers.value('content-encoding') == 'br' && first != 123) {
      bytes = brotli.decode(bytes);
    }
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map) throw const FormatException('宾果开奖数据格式错误');
    return Map<String, dynamic>.from(json);
  }

  void cancel() => _cancel?.cancel('Bingo view closed');
  void dispose() {
    cancel();
    _client.close(force: true);
  }
}
