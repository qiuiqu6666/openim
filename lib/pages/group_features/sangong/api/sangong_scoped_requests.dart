import 'package:dio/dio.dart';

/// Pins the caller's scope before Dio schedules its request interceptor.
class SangongScopedRequests {
  SangongScopedRequests(this._client, this._options);
  final Dio _client;
  final Options Function(Options?) _options;

  Future<Response<dynamic>> get(String path,
          {Map<String, dynamic>? queryParameters, Options? options}) =>
      _client.get(path,
          queryParameters: queryParameters, options: _options(options));

  Future<Response<dynamic>> post(String path,
          {dynamic data,
          Map<String, dynamic>? queryParameters,
          Options? options}) =>
      _client.post(path,
          data: data,
          queryParameters: queryParameters,
          options: _options(options));

  Future<Response<dynamic>> put(String path,
          {dynamic data,
          Map<String, dynamic>? queryParameters,
          Options? options}) =>
      _client.put(path,
          data: data,
          queryParameters: queryParameters,
          options: _options(options));

  Future<Response<dynamic>> delete(String path,
          {dynamic data,
          Map<String, dynamic>? queryParameters,
          Options? options}) =>
      _client.delete(path,
          data: data,
          queryParameters: queryParameters,
          options: _options(options));
}
