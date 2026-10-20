import WebKit

/// Deezer's own sign-in page, which takes an email and password or a Google account. Signing in
/// there sets the `arl` cookie, the one credential a session needs, so the password never passes
/// through this app. The page keeps nothing once it is gone.
public final class SignInPage: WKWebView {
    public enum Method: Sendable, CaseIterable, Identifiable {
        case email, google
        public var id: Self { self }

        /// The button that opens this method, once it can be used.
        fileprivate var button: String {
            switch self {
            case .email: "[data-testid=btn-switch-to-email]"
            case .google: "[data-cy=social-auth-google]:enabled"
            }
        }
    }

    public static let title = "Sign In to Deezer"
    public static let size = CGSize(width: 480, height: 680)

    private let handler: Handler

    public init(_ method: Method, onARL: @escaping (String) -> Void) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // Google turns away embedded browsers that don't present as Safari.
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        handler = Handler(method: method, onARL: onARL)
        super.init(frame: .zero, configuration: configuration)
        navigationDelegate = handler
        uiDelegate = handler
        configuration.websiteDataStore.httpCookieStore.add(handler)
        load(URLRequest(url: URL(string: "https://www.deezer.com/login")!))
    }

    required init?(coder: NSCoder) { nil }
}

private final class Handler: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
    /// Opened once the sign-in form first loads, and then left to the person.
    private var method: SignInPage.Method?
    private var onARL: ((String) -> Void)?

    init(method: SignInPage.Method, onARL: @escaping (String) -> Void) {
        self.method = method
        self.onARL = onARL
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let method, webView.url?.host() == "account.deezer.com" else { return }
        self.method = nil
        for button in ["[data-testid=gdpr-btn-refuse-all]", method.button] {
            Task { await press(button, in: webView) }
        }
    }

    /// Google signs in through a popup, shown over the page until it closes itself.
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let popup = WKWebView(frame: webView.bounds, configuration: configuration)
        popup.autoresizingMask = [.width, .height]
        popup.uiDelegate = self
        webView.addSubview(popup)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        webView.removeFromSuperview()
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task {
            let cookies = await cookieStore.allCookies()
            guard let arl = cookies.first(where: { $0.name == "arl" && !$0.value.isEmpty })?.value,
                let onARL
            else { return }
            self.onARL = nil
            onARL(arl)
        }
    }

    /// Waits a few seconds for the button, unless the person starts using the page first, and
    /// clicks it from here: WebKit counts that as the person's own click, the only kind Google
    /// opens its popup for.
    private func press(_ button: String, in webView: WKWebView) async {
        let found = try? await webView.callAsyncJavaScript(
            """
            return await new Promise(resolve => {
              const settle = found => { clearInterval(timer); resolve(found); };
              const timer = setInterval(() => document.querySelector(button) && settle(true), 100);
              setTimeout(() => settle(false), 10000);
              for (const type of ["pointerdown", "keydown"]) addEventListener(type, () => settle(false), { capture: true, once: true });
            });
            """, arguments: ["button": button], contentWorld: .page
        )
        guard found as? Bool == true else { return }
        _ = try? await webView.callAsyncJavaScript(
            "document.querySelector(button).click()", arguments: ["button": button], contentWorld: .page
        )
    }
}
