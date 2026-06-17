import StoreKit
import SwiftUI

#if canImport(UIKit)
import UIKit

public enum BLZSignalRootState: Equatable {
    case app
    case destination(URL)
}

public struct BLZSignalRootGate<NativeContent: View>: View {
    public let configuration: BLZSignalConfiguration
    public let requestReviewBeforeCheck: Bool
    private let nativeContent: () -> NativeContent
    @AppStorage("settings.language") private var preferredLanguage = "en"

    @State private var state: BLZSignalRootState = .app
    @State private var hasStarted = false

    public init(
        configuration: BLZSignalConfiguration,
        requestReviewBeforeCheck: Bool = false,
        @ViewBuilder nativeContent: @escaping () -> NativeContent
    ) {
        self.configuration = configuration
        self.requestReviewBeforeCheck = requestReviewBeforeCheck
        self.nativeContent = nativeContent
    }

    public var body: some View {
        ZStack {
            switch state {
            case .app:
                nativeContent()
                    .transition(.opacity)

            case .destination(let url):
                NavigationStack {
                    BLZSignalArenaScreen(configuration: configuration.resolvedDestination(url))
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: state)
        .mediaBridgeAudioAware()
        .task {
            await startIfNeeded()
        }
    }

    @MainActor
    private func startIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true

        await waitBeforeInitialCheck()

        if requestReviewBeforeCheck {
            await requestReviewOnce()
        }

        do {
            let client = BLZSignalRequestClient(configuration: configuration)
            let decision = try await loadDecisionWithTimeout(client: client)
            guard decision.enabled, let url = decision.url else {
                state = .app
                return
            }
            state = .destination(url)
        } catch {
            state = .app
        }
    }

    @MainActor
    private func waitBeforeInitialCheck() async {
        guard configuration.initialCheckDelay > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(configuration.initialCheckDelay * 1_000_000_000))
    }

    private func loadDecisionWithTimeout(client: BLZSignalRequestClient) async throws -> BLZSignalDecision {
        try await withThrowingTaskGroup(of: BLZSignalDecision.self) { group in
            group.addTask {
                try await client.loadDecision(preferredLanguage: preferredLanguage)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64((configuration.requestTimeout + 2) * 1_000_000_000))
                throw URLError(.timedOut)
            }

            guard let result = try await group.next() else {
                throw URLError(.unknown)
            }
            group.cancelAll()
            return result
        }
    }

    @MainActor
    private func requestReviewOnce() async {
        let storageKey = "mediaBridge.launch.rating.shown"
        guard UserDefaults.standard.integer(forKey: storageKey) == 0 else { return }
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
            UserDefaults.standard.set(1, forKey: storageKey)
        }

        try? await Task.sleep(nanoseconds: 800_000_000)
    }
}
#endif
