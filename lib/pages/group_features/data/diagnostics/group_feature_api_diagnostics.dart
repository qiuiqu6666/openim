import 'dart:async';

import 'package:dio/dio.dart';

/// Optional observation at the real transport boundary, before payload mapping.
/// Diagnostics must not consume response streams or alter request/response data.
abstract class GroupFeatureApiDiagnostics {
  void onRequest(RequestOptions request);
  void onResponse(Response<dynamic> response);
  void onError(Object error);
  void onStreamData(String chunk);
  void onStreamClosed();
}

final Object _diagnosticsZoneKey = Object();

/// Applies observation only to requests started inside this asynchronous scope.
T withGroupFeatureDiagnostics<T>(
        T Function() action, GroupFeatureApiDiagnostics? Function() factory) =>
    runZoned<T>(action, zoneValues: {_diagnosticsZoneKey: factory});

/// Creates one observer per request without allowing diagnostic failures to
/// affect authentication, request handling, or the caller's asynchronous work.
GroupFeatureApiDiagnostics? scopedGroupFeatureDiagnostics() {
  try {
    final factory = Zone.current[_diagnosticsZoneKey];
    if (factory is GroupFeatureApiDiagnostics? Function()) return factory();
  } catch (_) {
    // An optional observer factory is never authoritative for business calls.
  }
  return null;
}

/// Logging failures never change the outcome or lifetime of a business request.
void reportGroupFeatureDiagnostics(void Function()? report) {
  if (report == null) return;
  try {
    report();
  } catch (_) {
    // The transport remains authoritative when an optional observer fails.
  }
}
