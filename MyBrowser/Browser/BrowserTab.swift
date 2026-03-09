import WebKit
import Combine

class BrowserTab {
    let id = UUID()
    let webView: WKWebView

    @Published var title: String = "New Tab"
    @Published var url: URL?
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var estimatedProgress: Double = 0

    init(configuration: WKWebViewConfiguration = WKWebViewConfiguration()) {
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        setupObservers()
    }

    private func setupObservers() {
        webView.publisher(for: \.title)
            .map { $0 ?? "New Tab" }
            .assign(to: &$title)

        webView.publisher(for: \.url)
            .assign(to: &$url)

        webView.publisher(for: \.isLoading)
            .assign(to: &$isLoading)

        webView.publisher(for: \.canGoBack)
            .assign(to: &$canGoBack)

        webView.publisher(for: \.canGoForward)
            .assign(to: &$canGoForward)

        webView.publisher(for: \.estimatedProgress)
            .assign(to: &$estimatedProgress)
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }
}
