import Foundation

public struct BLZSignalRequestClient: Sendable {
    public let configuration: BLZSignalConfiguration
    public var session: URLSession

    public init(configuration: BLZSignalConfiguration, session: URLSession? = nil) {
        self.configuration = configuration
        if let session {
            self.session = session
        } else {
            let sessionConfiguration = URLSessionConfiguration.ephemeral
            sessionConfiguration.timeoutIntervalForRequest = configuration.requestTimeout
            sessionConfiguration.timeoutIntervalForResource = configuration.requestTimeout + 2
            self.session = URLSession(configuration: sessionConfiguration)
        }
    }

    public func loadDecision() async throws -> BLZSignalDecision {
        try await loadDecision(preferredLanguage: Self.defaultLanguageCode())
    }

    public func loadDecision(preferredLanguage: String) async throws -> BLZSignalDecision {
        let request: URLRequest
        switch configuration.requestMode {
        case .bundleProbe:
            request = try makeProbeRequest()
        case .launchWeb:
            request = try makeLaunchRequest(payload: Self.defaultLaunchPayload(
                configuration: configuration,
                preferredLanguage: preferredLanguage
            ))
        }

        let decision = try await send(request: request)
        guard decision.enabled, let url = decision.url else { return decision }

        return BLZSignalDecision(
            enabled: true,
            url: Self.resolvedDestinationURL(base: url, preferredLanguage: preferredLanguage)
        )
    }

    public func makeLaunchRequest(payload: BLZSignalLaunchPayload) throws -> URLRequest {
        var request = URLRequest(url: configuration.webCheckURL)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(configuration.webToken)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.webToken, forHTTPHeaderField: "X-Analytics-Token")
        request.setValue(configuration.bundleID, forHTTPHeaderField: "X-Bundle-ID")
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    public func makeProbeRequest() throws -> URLRequest {
        var request = URLRequest(url: configuration.webCheckURL)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(configuration.webToken)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.webToken, forHTTPHeaderField: "X-Analytics-Token")
        request.setValue(configuration.bundleID, forHTTPHeaderField: "X-Bundle-ID")
        request.setValue(configuration.serverDomain, forHTTPHeaderField: "X-Server-Domain")
        request.httpBody = try JSONEncoder().encode(
            BLZSignalProbePayload(
                appID: configuration.bundleID,
                domain: configuration.serverDomain,
                key: configuration.webToken
            )
        )
        return request
    }

    public static func resolvedDestinationURL(base: URL, preferredLanguage: String) -> URL {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return base }
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "platform", value: "ios"))
        queryItems.append(URLQueryItem(name: "language", value: preferredLanguage))
        components.queryItems = queryItems
        return components.url ?? base
    }

    public static func defaultLaunchPayload(
        configuration: BLZSignalConfiguration,
        preferredLanguage: String = Locale.current.identifier
    ) -> BLZSignalLaunchPayload {
        let bundle = Bundle.main
        return BLZSignalLaunchPayload(
            event: "app_open",
            bundleID: configuration.bundleID,
            appVersion: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            appBuild: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            platform: "ios",
            language: preferredLanguage,
            timeZone: TimeZone.current.identifier,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }

    private func send(request: URLRequest) async throws -> BLZSignalDecision {
        let (data, response) = try await sendData(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        persistCookies(from: httpResponse, for: request.url)
        return try JSONDecoder().decode(BLZSignalDecision.self, from: data)
    }

    private func persistCookies(from response: HTTPURLResponse, for url: URL?) {
        guard let url else { return }
        let headerFields = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            guard let key = item.key as? String, let value = item.value as? String else { return }
            result[key] = value
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
        for cookie in cookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    private func sendData(for request: URLRequest) async throws -> (Data, URLResponse) {
        if #available(macOS 12.0, iOS 15.0, *) {
            return try await session.data(for: request)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }

    private static func defaultLanguageCode() -> String {
        if #available(macOS 13.0, iOS 16.0, *) {
            return Locale.current.language.languageCode?.identifier ?? Locale.current.identifier
        }
        return Locale.preferredLanguages.first ?? Locale.current.identifier
    }
}
