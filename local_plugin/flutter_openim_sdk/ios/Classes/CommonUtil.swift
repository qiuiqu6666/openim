import Foundation


public class CommonUtil {
    
    public static func emitEvent(channel: FlutterMethodChannel, method: String, type: String, errCode: Int32?, errMsg: String?, data: Any?){
        safeMainAsync {
            var res: [String: Any] = [:]
            res["type"] = type
            res["data"] = data
            res["errCode"] = errCode
            res["errMsg"] = errMsg
            #if DEBUG
            DiagnosticLog.write("native call flutter { method: \(method) type: \(type) }")
            #endif
            channel.invokeMethod(method, arguments: res)
        }
    }
}
