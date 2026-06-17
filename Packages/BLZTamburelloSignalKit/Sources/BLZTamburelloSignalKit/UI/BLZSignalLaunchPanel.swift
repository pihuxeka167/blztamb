import SwiftUI

#if canImport(UIKit)
public struct BLZSignalLaunchPanel: View {
    public let configuration: BLZSignalConfiguration
    @AppStorage("settings.language") private var preferredLanguage = "en"
    @State private var isLoading = false
    @State private var statusMessage: String?
    @State private var presentedDestination: BLZSignalPresentedDestination?

    public init(configuration: BLZSignalConfiguration) {
        self.configuration = configuration
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Web Launch Check", systemImage: "camera.viewfinder")
                .font(.headline)
                .foregroundStyle(BLZSignalTheme.accent)

            Text("Sends the web launch check and continues with the server-provided destination when available.")
                .font(.subheadline)
                .foregroundStyle(BLZSignalTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await loadDestination() }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(BLZSignalTheme.navy)
                    }
                    Text(isLoading ? "Checking..." : "Check and open")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(BLZSignalTheme.accent)
            .foregroundStyle(BLZSignalTheme.navy)
            .disabled(isLoading)

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(BLZSignalTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BLZSignalTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .fullScreenCover(item: $presentedDestination) { destination in
            NavigationStack {
                BLZSignalArenaScreen(configuration: destination.configuration)
            }
        }
        .mediaBridgeAudioAware()
    }

    @MainActor
    private func loadDestination() async {
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        do {
            let client = BLZSignalRequestClient(configuration: configuration)
            let decision = try await client.loadDecision(preferredLanguage: preferredLanguage)

            guard decision.enabled else {
                statusMessage = "Server returned false. Continuing with the local app."
                return
            }

            guard let url = decision.url else {
                statusMessage = "Server returned true but did not include a URL."
                return
            }

            presentedDestination = BLZSignalPresentedDestination(
                configuration: configuration.resolvedDestination(url)
            )
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

public struct BLZSignalPresentedDestination: Identifiable {
    public let id = UUID()
    public let configuration: BLZSignalConfiguration

    public init(configuration: BLZSignalConfiguration) {
        self.configuration = configuration
    }
}
#endif
