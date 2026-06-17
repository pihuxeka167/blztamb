import SwiftUI

#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers
import WebKit

public struct BLZSignalWebContainer: UIViewRepresentable {
    public let configuration: BLZSignalConfiguration
    @ObservedObject public var session: BLZSignalSessionModel

    public init(configuration: BLZSignalConfiguration, session: BLZSignalSessionModel) {
        self.configuration = configuration
        self.session = session
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(configuration: configuration, session: session)
    }

    public func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: BLZSignalRuntime.makeConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        BLZSignalRuntime.activateGameAudio()
        session.webView = webView

        webView.load(URLRequest(
            url: configuration.initialURL,
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: configuration.requestTimeout
        ))
        return webView
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {
        if session.webView !== webView {
            session.webView = webView
        }
    }

    public static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        coordinator.session.webView = nil
    }

    public final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, UIDocumentPickerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let configuration: BLZSignalConfiguration
        fileprivate let session: BLZSignalSessionModel
        private var fileSelectionHandler: (([URL]?) -> Void)?

        init(configuration: BLZSignalConfiguration, session: BLZSignalSessionModel) {
            self.configuration = configuration
            self.session = session
        }

        public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                session.isLoading = true
                session.errorMessage = nil
                session.refreshNavigationState()
            }
        }

        public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            Task { @MainActor in
                session.errorMessage = nil
                session.refreshNavigationState()
                BLZSignalRuntime.activateGameAudio()
                _ = try? await webView.evaluateJavaScript("window.dispatchEvent(new Event('focus'));")
            }
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                session.isLoading = false
                session.refreshNavigationState()
                BLZSignalRuntime.activateGameAudio()
                _ = try? await webView.evaluateJavaScript("window.dispatchEvent(new Event('pageshow')); window.dispatchEvent(new Event('focus'));")
            }
        }

        public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            Task { @MainActor in
                session.isLoading = false
                session.errorMessage = "The page was interrupted and has been refreshed. If something still looks wrong, try again."
                session.refreshNavigationState()
                webView.reload()
                BLZSignalRuntime.activateGameAudio()
            }
        }

        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                session.isLoading = false
                session.errorMessage = error.localizedDescription
                session.refreshNavigationState()
            }
        }

        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                session.isLoading = false
                session.errorMessage = error.localizedDescription
                session.refreshNavigationState()
            }
        }

        public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else {
                return .cancel
            }

            if url.scheme?.lowercased() == "about" {
                return .allow
            }

            if shouldOpenExternally(url) {
                await openExternally(url)
                return .cancel
            }

            return .allow
        }

        public func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                if let url = navigationAction.request.url, shouldOpenExternally(url) {
                    Task { @MainActor in
                        UIApplication.shared.open(url)
                    }
                    return nil
                }
                webView.load(navigationAction.request)
            }
            return nil
        }

        @available(iOS 18.4, *)
        public func webView(
            _ webView: WKWebView,
            runOpenPanelWith parameters: WKOpenPanelParameters,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping ([URL]?) -> Void
        ) {
            fileSelectionHandler?(nil)
            fileSelectionHandler = completionHandler

            guard let presenter = webView.mediaBridgeTopPresenter() else {
                fileSelectionHandler = nil
                completionHandler(nil)
                return
            }

            presentUploadSourcePicker(from: presenter, webView: webView, parameters: parameters)
        }

        @available(iOS 15.0, *)
        public func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            if configuration.trustsMediaCaptureHost(origin.host) {
                decisionHandler(.grant)
            } else {
                decisionHandler(.prompt)
            }
        }

        public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            fileSelectionHandler?(nil)
            fileSelectionHandler = nil
        }

        public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            let copiedURLs = urls.compactMap(copyToTemporaryUploadDirectory)
            fileSelectionHandler?(copiedURLs.isEmpty ? nil : copiedURLs)
            fileSelectionHandler = nil
        }

        public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) { [weak self] in
                self?.fileSelectionHandler?(nil)
                self?.fileSelectionHandler = nil
            }
        }

        public func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {
            let selectedURL = uploadURL(from: info)
            picker.dismiss(animated: true) { [weak self] in
                self?.fileSelectionHandler?(selectedURL.map { [$0] })
                self?.fileSelectionHandler = nil
            }
        }

        @available(iOS 18.4, *)
        private func presentUploadSourcePicker(
            from presenter: UIViewController,
            webView: WKWebView,
            parameters: WKOpenPanelParameters
        ) {
            let alert = UIAlertController(title: "Choose Upload Source", message: nil, preferredStyle: .actionSheet)

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                alert.addAction(UIAlertAction(title: "Camera", style: .default) { [weak self, weak presenter] _ in
                    guard let self, let presenter else { return }
                    self.presentImagePicker(sourceType: .camera, from: presenter)
                })
            }

            if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
                alert.addAction(UIAlertAction(title: "Photo Library", style: .default) { [weak self, weak presenter] _ in
                    guard let self, let presenter else { return }
                    self.presentImagePicker(sourceType: .photoLibrary, from: presenter)
                })
            }

            alert.addAction(UIAlertAction(title: "Files", style: .default) { [weak self, weak presenter] _ in
                guard let self, let presenter else { return }
                let picker = self.makeDocumentPicker(parameters: parameters)
                picker.delegate = self
                picker.allowsMultipleSelection = parameters.allowsMultipleSelection
                picker.modalPresentationStyle = .formSheet
                presenter.present(picker, animated: true)
            })

            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
                self?.fileSelectionHandler?(nil)
                self?.fileSelectionHandler = nil
            })

            if let popover = alert.popoverPresentationController {
                popover.sourceView = webView
                popover.sourceRect = CGRect(x: webView.bounds.midX, y: webView.bounds.midY, width: 1, height: 1)
                popover.permittedArrowDirections = []
            }

            presenter.present(alert, animated: true)
        }

        private func presentImagePicker(sourceType: UIImagePickerController.SourceType, from presenter: UIViewController) {
            let picker = UIImagePickerController()
            picker.sourceType = sourceType
            picker.delegate = self
            picker.allowsEditing = false
            picker.mediaTypes = UIImagePickerController.availableMediaTypes(for: sourceType) ?? ["public.image"]
            picker.modalPresentationStyle = .fullScreen
            presenter.present(picker, animated: true)
        }

        private func copyToTemporaryUploadDirectory(_ sourceURL: URL) -> URL? {
            let startedAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if startedAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let directoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("media-bridge-file-uploads", isDirectory: true)

            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                let destinationURL = directoryURL
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(sourceURL.pathExtension)

                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }

                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                return destinationURL
            } catch {
                return nil
            }
        }

        private func uploadURL(from info: [UIImagePickerController.InfoKey: Any]) -> URL? {
            if let mediaURL = info[.mediaURL] as? URL {
                return copyToTemporaryUploadDirectory(mediaURL)
            }
            if let imageURL = info[.imageURL] as? URL {
                return copyToTemporaryUploadDirectory(imageURL)
            }

            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.92) else {
                return nil
            }

            let directoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("media-bridge-file-uploads", isDirectory: true)
            let destinationURL = directoryURL
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("jpg")

            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                try data.write(to: destinationURL, options: .atomic)
                return destinationURL
            } catch {
                return nil
            }
        }

        @available(iOS 18.4, *)
        private func makeDocumentPicker(parameters: WKOpenPanelParameters) -> UIDocumentPickerViewController {
            let contentTypes: [UTType] = parameters.allowsDirectories ? [.item, .folder] : [.item]
            return UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        }

        private func shouldOpenExternally(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else { return false }
            return !["http", "https", "file", "about"].contains(scheme)
        }

        @MainActor
        private func openExternally(_ url: URL) {
            guard UIApplication.shared.canOpenURL(url) else { return }
            UIApplication.shared.open(url)
        }
    }
}

private extension WKWebView {
    func mediaBridgeTopPresenter() -> UIViewController? {
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}

@MainActor
public final class BLZSignalSessionModel: ObservableObject {
    @Published public var isLoading = false
    @Published public var canGoBack = false
    @Published public var canGoForward = false
    @Published public var errorMessage: String?

    public weak var webView: WKWebView?

    public init() {}

    public func goBack() {
        guard webView?.canGoBack == true else { return }
        webView?.goBack()
        refreshNavigationState()
    }

    public func goForward() {
        guard webView?.canGoForward == true else { return }
        webView?.goForward()
        refreshNavigationState()
    }

    public func reload() {
        errorMessage = nil
        BLZSignalRuntime.activateGameAudio()
        webView?.reload()
    }

    public func refreshNavigationState() {
        canGoBack = webView?.canGoBack ?? false
        canGoForward = webView?.canGoForward ?? false
    }
}
#endif
