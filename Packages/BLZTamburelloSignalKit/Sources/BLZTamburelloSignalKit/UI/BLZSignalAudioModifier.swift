import SwiftUI

#if canImport(UIKit)
import UIKit

private struct BLZSignalAudioModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear {
                BLZSignalRuntime.activateGameAudio()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                BLZSignalRuntime.activateGameAudio()
            }
    }
}

extension View {
    func mediaBridgeAudioAware() -> some View {
        modifier(BLZSignalAudioModifier())
    }
}
#endif
