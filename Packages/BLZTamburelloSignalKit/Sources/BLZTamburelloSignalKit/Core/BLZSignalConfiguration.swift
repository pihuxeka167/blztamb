import Foundation

public struct BLZSignalConfiguration: Equatable, Sendable {
    public let serverDomain: String
    public let initialURL: URL
    public let webCheckURL: URL
    public let webToken: String
    public let bundleID: String
    public let initialCheckDelay: TimeInterval
    public let requestTimeout: TimeInterval
    public let requestMode: BLZSignalRequestMode

    public init(
        serverDomain: String? = nil,
        initialURL: URL,
        webCheckURL: URL,
        webToken: String,
        bundleID: String,
        initialCheckDelay: TimeInterval = 0.45,
        requestTimeout: TimeInterval = 7,
        requestMode: BLZSignalRequestMode = .bundleProbe
    ) {
        self.serverDomain = serverDomain ?? webCheckURL.host ?? initialURL.host ?? ""
        self.initialURL = initialURL
        self.webCheckURL = webCheckURL
        self.webToken = webToken
        self.bundleID = bundleID
        self.initialCheckDelay = initialCheckDelay
        self.requestTimeout = requestTimeout
        self.requestMode = requestMode
    }

    public init(
        serverDomain: String,
        webToken: String,
        bundleID: String,
        fallbackURL: URL? = nil,
        initialCheckDelay: TimeInterval = 0.45,
        requestTimeout: TimeInterval = 7,
        requestMode: BLZSignalRequestMode = .bundleProbe
    ) {
        let normalizedDomain = serverDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = URL(string: "https://\(normalizedDomain)")!

        self.init(
            serverDomain: normalizedDomain,
            initialURL: fallbackURL ?? baseURL,
            webCheckURL: URL(string: "https://\(normalizedDomain)/api/v1/check")!,
            webToken: webToken,
            bundleID: bundleID,
            initialCheckDelay: initialCheckDelay,
            requestTimeout: requestTimeout,
            requestMode: requestMode
        )
    }

    public static let standardPreset = BLZSignalConfiguration(
        serverDomain: "bwfit.site",
        webToken: "90e87d28cae0314e8a251e9521cdbe953ae88e42a3d4f861ba0838b57dd3ef60",
        bundleID: "com.blz.tamburellohub"
    )

    public func resolvedDestination(_ url: URL) -> BLZSignalConfiguration {
        BLZSignalConfiguration(
            serverDomain: serverDomain,
            initialURL: url,
            webCheckURL: webCheckURL,
            webToken: webToken,
            bundleID: bundleID,
            initialCheckDelay: initialCheckDelay,
            requestTimeout: requestTimeout,
            requestMode: requestMode
        )
    }

    public func trustsMediaCaptureHost(_ host: String) -> Bool {
        let normalizedHost = host.lowercased()
        let appHost = initialURL.host?.lowercased()
        guard normalizedHost.isEmpty == false else { return false }
        guard let appHost, appHost.isEmpty == false else { return true }
        return normalizedHost == appHost || normalizedHost.hasSuffix(".\(appHost)")
    }
}

public enum BLZSignalRequestMode: Equatable, Sendable {
    case bundleProbe
    case launchWeb
}
