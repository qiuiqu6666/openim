import 'package:dio/dio.dart';
import 'package:openim_common/openim_common.dart';

import '../models/call_errors.dart';
import 'call_signaling_protocol.dart';

/// Request the existing authenticated RTC endpoint. The call session owns
/// errors: transient RTC failures must never clear the IM login or navigate.
Future<SignalingCertificate> requestRtcCertificate(
    String roomID, String userID) async {
  if (!validCallID(roomID) || userID.trim().isEmpty) {
    throw const InvalidCallCertificate();
  }
  dynamic response;
  try {
    response = await HttpUtil.post(
      Urls.getTokenForRTC,
      data: {'room': roomID, 'identity': userID},
      options: Apis.chatTokenOptions,
      showErrorToast: false,
    );
  } catch (error) {
    // HttpUtil preserves transport exceptions while business errors retain
    // their code. Keep native diagnostics out of the compact call prompt.
    if (error is String || error is DioException) {
      throw const CallTransportUnavailable();
    }
    rethrow;
  }
  if (response is! Map<String, dynamic>) throw const InvalidCallCertificate();
  final SignalingCertificate certificate;
  try {
    certificate = SignalingCertificate.fromJson(response);
  } catch (_) {
    throw const InvalidCallCertificate();
  }
  if (certificate.roomID != null && certificate.roomID != roomID) {
    throw const InvalidCallCertificate();
  }
  if (certificate.token?.trim().isNotEmpty != true ||
      certificate.liveURL?.trim().isNotEmpty != true) {
    throw const InvalidCallCertificate();
  }
  if (certificate.busyLineUserIDList?.isNotEmpty == true) {
    throw const CallBusy();
  }
  return certificate..roomID = roomID;
}

class CallTransportUnavailable implements Exception {
  const CallTransportUnavailable();
}
