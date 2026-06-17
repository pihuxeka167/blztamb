import FirebaseAnalytics
import FirebaseCore
import Foundation

enum TamburelloTelemetry {
    static func log(_ name: String, parameters: [String: Any]? = nil) {
        guard FirebaseApp.app() != nil else { return }
        Analytics.logEvent(name, parameters: parameters)
    }
}
