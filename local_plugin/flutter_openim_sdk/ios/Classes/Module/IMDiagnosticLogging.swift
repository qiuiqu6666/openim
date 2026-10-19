import Flutter
import OpenIMCore

extension IMMananger {
    func setDiagnosticLogging(methodCall: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = methodCall.arguments as? [String: Any],
              let seconds = args["seconds"] as? NSNumber else {
            callBack(result, FlutterError(code: "invalid_arguments", message: "seconds is required", details: nil))
            return
        }
        callBack(result, Open_im_sdkSetDiagnosticLogging(max(0, min(900, seconds.intValue))))
    }

    func getDiagnosticLoggingSeconds(methodCall: FlutterMethodCall, result: @escaping FlutterResult) {
        callBack(result, Open_im_sdkGetDiagnosticLoggingSeconds())
    }
}
