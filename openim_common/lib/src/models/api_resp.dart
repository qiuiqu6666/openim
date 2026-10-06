import 'dart:convert';
import '../utils/http/api_error_messages.dart';

class ApiResp {
  int errCode;
  String errMsg;
  String errDlt;
  dynamic data;

  ApiResp.fromJson(Map<String, dynamic> map)
      : errCode = map['errCode'] is int
            ? map['errCode'] as int
            : int.tryParse('${map['errCode']}') ?? -1,
        errMsg = map["errMsg"]?.toString() ?? '',
        errDlt = map["errDlt"]?.toString() ?? '',
        data = map["data"];

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['errCode'] = errCode;
    data['errMsg'] = errMsg;
    data['errDlt'] = errDlt;
    data['data'] = data;
    return data;
  }

  @override
  String toString() {
    return jsonEncode(this);
  }
}

class ApiError {
  static String getMsg(int errorCode) {
    return ApiErrorMessages.business(errorCode);
  }
}
