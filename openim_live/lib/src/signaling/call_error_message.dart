import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../models/call_errors.dart';
import 'call_signaling_transport.dart';

/// Keep native/API diagnostics in logs, never in the compact in-app toast.
String callErrorMessage(Object error) {
  if (error is CallPermissionDenied) return StrRes.permissionDeniedTitle;
  if (error is CallBusy) return StrRes.busyVideoCallHint;
  if (error is InvalidCallCertificate) return StrRes.callFail;
  if (error is PlatformException) {
    if (error.code == '${SDKErrorCode.hasBeenBlocked}') return StrRes.callFail;
    if (const ['permission_denied', 'permissionDenied', 'NotAllowedError']
        .contains(error.code)) return StrRes.permissionDeniedTitle;
  }
  if (error is SocketException ||
      error is TimeoutException ||
      error is CallTransportUnavailable) {
    return StrRes.networkError;
  }
  return StrRes.callFail;
}
