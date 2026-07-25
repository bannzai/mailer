import SwiftUI
import WebKit

#if os(iOS)
    /// HTML メール本文の表示。リンクは外部ブラウザで開き、WebView 内では遷移させない。
    struct HTMLView: UIViewRepresentable {
        let html: String

        func makeUIView(context: Context) -> WKWebView {
            let webView = WKWebView()
            webView.navigationDelegate = context.coordinator
            return webView
        }

        func updateUIView(_ webView: WKWebView, context: Context) {
            webView.loadHTMLString(HTMLView.wrapped(html), baseURL: nil)
        }

        func makeCoordinator() -> HTMLViewCoordinator {
            HTMLViewCoordinator()
        }
    }
#else
    /// HTML メール本文の表示 (macOS)。リンクは外部ブラウザで開き、WebView 内では遷移させない。
    struct HTMLView: NSViewRepresentable {
        let html: String

        func makeNSView(context: Context) -> WKWebView {
            let webView = WKWebView()
            webView.navigationDelegate = context.coordinator
            return webView
        }

        func updateNSView(_ webView: WKWebView, context: Context) {
            webView.loadHTMLString(HTMLView.wrapped(html), baseURL: nil)
        }

        func makeCoordinator() -> HTMLViewCoordinator {
            HTMLViewCoordinator()
        }
    }
#endif

extension HTMLView {
    /// モバイル幅に収めるための viewport 指定を付けて包む。
    static func wrapped(_ html: String) -> String {
        """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>\
        <body>\(html)</body></html>
        """
    }
}

/// リンククリックを外部ブラウザへ逃がす WKWebView のデリゲート。
final class HTMLViewCoordinator: NSObject, WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            #if os(iOS)
                UIApplication.shared.open(url)
            #else
                NSWorkspace.shared.open(url)
            #endif
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
