import SwiftUI

#if canImport(UIKit)
public struct BLZSignalArenaScreen: View {
    public let configuration: BLZSignalConfiguration
    @Environment(\.openURL) private var openURL
    @StateObject private var session = BLZSignalSessionModel()

    public init(configuration: BLZSignalConfiguration) {
        self.configuration = configuration
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                BLZSignalTheme.overlay
                    .ignoresSafeArea()

                BLZSignalWebContainer(configuration: configuration, session: session)
                    .padding(.top, browserTopInset(topInset: proxy.safeAreaInsets.top))
                    .ignoresSafeArea(edges: [.horizontal, .bottom])

                controlBar(topInset: proxy.safeAreaInsets.top, width: proxy.size.width)

                if session.isLoading {
                    ProgressView()
                        .tint(BLZSignalTheme.accent)
                        .padding(10)
                        .background(BLZSignalTheme.overlay.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.top, browserTopInset(topInset: proxy.safeAreaInsets.top) + 16)
                }

                if let errorMessage = session.errorMessage {
                    VStack(spacing: 10) {
                        Text("Connection issue")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                        Button("Reload") {
                            session.reload()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(BLZSignalTheme.accent)
                        .foregroundStyle(BLZSignalTheme.navy)
                    }
                    .padding(16)
                    .foregroundStyle(.white)
                    .background(BLZSignalTheme.overlay.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(20)
                    .padding(.top, browserTopInset(topInset: proxy.safeAreaInsets.top))
                }
            }
            .ignoresSafeArea()
        }
        .mediaBridgeAudioAware()
        .onAppear {
            BLZSignalRuntime.prewarm(url: configuration.initialURL, timeout: configuration.requestTimeout)
        }
        .onDisappear {
            BLZSignalAudioKeeper.shared.stop()
        }
    }

    private func browserTopInset(topInset: CGFloat) -> CGFloat {
        max(topInset + 42, 86)
    }

    private func dynamicIslandSpacing(width: CGFloat) -> CGFloat {
        width >= 430 ? 168 : 148
    }

    private func controlBar(topInset: CGFloat, width: CGFloat) -> some View {
        HStack {
            HStack(spacing: 8) {
                controlButton(systemName: "chevron.left", isEnabled: session.canGoBack) {
                    session.goBack()
                }

                controlButton(systemName: "chevron.right", isEnabled: session.canGoForward) {
                    session.goForward()
                }
            }

            Spacer(minLength: dynamicIslandSpacing(width: width))

            controlButton(systemName: "safari", isEnabled: browserURL != nil) {
                openInDefaultBrowser()
            }

            controlButton(systemName: "arrow.clockwise", isEnabled: true) {
                session.reload()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, max(topInset - 4, 8))
    }

    private var browserURL: URL? {
        session.webView?.url ?? configuration.initialURL
    }

    private func openInDefaultBrowser() {
        guard let browserURL else { return }
        openURL(browserURL)
    }

    private func controlButton(systemName: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isEnabled ? .primary : .secondary.opacity(0.55))
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
#endif
