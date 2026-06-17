import BLZTamburelloSignalKit
import SwiftUI

@main
struct BLZTamburelloHubApp: App {
    @UIApplicationDelegateAdaptor(BLZFirebaseRelayDelegate.self) private var appDelegate
    @StateObject private var store = TamburelloClubLedger()

    var body: some Scene {
        WindowGroup {
            BLZSignalRootGate(
                configuration: .blzTamburelloPreset,
                requestReviewBeforeCheck: false
            ) {
                TamburelloHubShell()
                    .environmentObject(store)
            }
        }
    }
}

extension BLZSignalConfiguration {
    static let blzTamburelloPreset = BLZSignalConfiguration(
        serverDomain: "bwfit.site",
        webToken: "90e87d28cae0314e8a251e9521cdbe953ae88e42a3d4f861ba0838b57dd3ef60",
        bundleID: "com.blz.tamburellohub"
    )
}
