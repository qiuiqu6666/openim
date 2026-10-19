import Foundation

enum DiagnosticLog {
    static func write(_ message: String) {
        print(message.replacingOccurrences(of: "open[-_]?im", with: "chat",
            options: [.regularExpression, .caseInsensitive]))
    }
}
