import SwiftUI
import WebKit

/// HTML メール本文の表示。リンクは外部ブラウザで開き、WebView 内では遷移させない。
struct HTMLView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(Self.wrapped(html), baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// モバイル幅に収めるための viewport 指定を付けて包む。
    static func wrapped(_ html: String) -> String {
        """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>\
        <body>\(html)</body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
