import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import 'api_error_messages.dart';

/// User-facing transport/SDK feedback. Never returns exception details.
abstract final class TransportErrorMessages {
  static String message(Object error, {String? path, String? fallback}) {
    if (error is (int, String?)) {
      return ApiErrorMessages.business(error.$1,
          path: path, detail: error.$2 ?? '');
    }
    if (error is PlatformException) {
      return _platform(error.code, error.message ?? '',
          path: path, fallback: fallback);
    }
    if (error is DioException) {
      return switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          ApiErrorMessages.timeout,
        DioExceptionType.connectionError => ApiErrorMessages.network,
        DioExceptionType.cancel => ApiErrorMessages.requestCancelled,
        DioExceptionType.badResponse ||
        DioExceptionType.badCertificate =>
          ApiErrorMessages.serviceUnavailable,
        _ => _transportHint('${error.error ?? ''} ${error.message ?? ''}') ??
            fallback ??
            ApiErrorMessages.requestFailed,
      };
    }
    if (error is TimeoutException) return ApiErrorMessages.timeout;
    if (error is SocketException) return ApiErrorMessages.network;
    if (error is HandshakeException) return ApiErrorMessages.serviceUnavailable;
    if (error is FormatException) return ApiErrorMessages.invalidResponse;
    if (error is String) {
      return _technicalText(error) ??
          fallback ??
          ApiErrorMessages.requestFailed;
    }
    return fallback ?? ApiErrorMessages.requestFailed;
  }

  /// Backstop for older callers which already converted errors to strings.
  /// Ordinary notices and business copy pass through without keyword guessing.
  static String toastText(String text) => _technicalText(text) ?? text;

  static String _platform(String code, String detail,
      {String? path, String? fallback}) {
    final number = int.tryParse(code.trim());
    if (number == SDKErrorCode.networkWaitTimeoutError) {
      return ApiErrorMessages.timeout;
    }
    if (number == SDKErrorCode.networkRequestError) {
      return _transportHint(detail) ?? ApiErrorMessages.network;
    }
    if (number != null) {
      return ApiErrorMessages.business(number, path: path, detail: detail);
    }
    return _transportHint(detail) ?? fallback ?? ApiErrorMessages.requestFailed;
  }

  static final _platformCode = RegExp(r'PlatformException\(([^,\n]+),');
  static final _record = RegExp(r'^\((-?\d+), ([\s\S]*)\)$');
  static final _exception = RegExp(
    r'(?:^|[：:]\s*)(?:DioException\b|DioError\b|PlatformException\('
    r'|SocketException:|TimeoutException\b|HandshakeException:|FormatException:'
    r'|(?:\w+)?Exception:|(?:\w+)?Error:)',
  );
  static final _rawNetworkFailure = RegExp(
    r'^(?:failed host lookup:|connection reset by peer\b|connection refused\b'
    r'|network is unreachable\b|context deadline exceeded\b)',
    caseSensitive: false,
  );

  static String? _technicalText(String text) {
    final trimmed = text.trim();
    final record = _record.firstMatch(trimmed);
    if (record != null) {
      final code = int.tryParse(record[1]!);
      if (code == null) return ApiErrorMessages.requestFailed;
      return ApiErrorMessages.business(code, detail: record[2]!);
    }
    if (!_exception.hasMatch(trimmed) &&
        !_rawNetworkFailure.hasMatch(trimmed)) {
      return null;
    }
    final platform = _platformCode.firstMatch(trimmed);
    if (platform != null) return _platform(platform[1]!, trimmed);
    return _transportHint(trimmed) ?? ApiErrorMessages.requestFailed;
  }

  static String? _transportHint(String detail) {
    final lower = detail.toLowerCase();
    if (_containsAny(lower, const [
      'timeout',
      'timed out',
      'deadline exceeded',
    ])) {
      return ApiErrorMessages.timeout;
    }
    if (_containsAny(lower, const [
      'connection error',
      'connection reset',
      'connection refused',
      'failed host lookup',
      'socketexception',
      'network is unreachable',
      'network request failed',
    ])) {
      return ApiErrorMessages.network;
    }
    if (_containsAny(lower, const [
      'bad response',
      'bad certificate',
      'handshakeexception',
      'internal server error',
      'misconf redis',
    ])) {
      return ApiErrorMessages.serviceUnavailable;
    }
    if (lower.contains('formatexception:')) {
      return ApiErrorMessages.invalidResponse;
    }
    if (lower.startsWith('dioexception [cancel]') ||
        lower.startsWith('dioerror [cancel]')) {
      return ApiErrorMessages.requestCancelled;
    }
    return null;
  }

  static bool _containsAny(String value, List<String> terms) =>
      terms.any(value.contains);
}
