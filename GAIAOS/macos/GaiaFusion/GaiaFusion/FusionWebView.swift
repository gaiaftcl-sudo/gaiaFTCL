import AppKit
import SwiftUI
import WebKit

struct FusionWebView: View {
    @ObservedObject var coordinator: AppCoordinator
    let onReady: (Bool) -> Void
    let onLoadURL: URL

    var body: some View {
        FusionWebKitView(
            coordinator: coordinator,
            loadURL: onLoadURL,
            onReady: { ready in
                onReady(ready)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private final class WasmSchemeHandler: NSObject, WKURLSchemeHandler {
  private static let scheme = "gaiasubstrate"
  private static let host = "local"
  private static func mimeType(for ext: String) -> String {
    switch ext.lowercased() {
    case "wasm":
      return "application/wasm"
    case "css":
      return "text/css; charset=utf-8"
    case "js", "mjs":
      return "application/javascript; charset=utf-8"
    case "html":
      return "text/html; charset=utf-8"
    case "json":
      return "application/json; charset=utf-8"
    case "svg":
      return "image/svg+xml"
    case "png":
      return "image/png"
    case "jpg", "jpeg":
      return "image/jpeg"
    case "webp":
      return "image/webp"
    case "woff":
      return "font/woff"
    case "woff2":
      return "font/woff2"
    case "ttf":
      return "font/ttf"
    default:
      return "application/octet-stream"
    }
  }

  func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
    guard
      let requestURL = urlSchemeTask.request.url,
      requestURL.scheme == Self.scheme,
      requestURL.host == Self.host
    else {
      urlSchemeTask.didFailWithError(URLError(.badURL))
      return
    }

    let resourceName = URL(fileURLWithPath: requestURL.path).deletingPathExtension().lastPathComponent
    let resourceType = requestURL.pathExtension
    guard
      !resourceName.isEmpty,
      !resourceType.isEmpty,
      let resourceURL = Bundle.gaiaFusionResourceBundle.url(forResource: resourceName, withExtension: resourceType)
        ?? Bundle.main.url(forResource: resourceName, withExtension: resourceType),
      let payload = try? Data(contentsOf: resourceURL)
    else {
      urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
      return
    }

    let response = HTTPURLResponse(
      url: requestURL,
      statusCode: 200,
      httpVersion: "HTTP/1.1",
      headerFields: [
        "Content-Type": Self.mimeType(for: resourceType),
        "Cache-Control": "public, max-age=31536000",
      ],
    )

    guard let response = response else {
      urlSchemeTask.didFailWithError(URLError(.badServerResponse))
      return
    }

    urlSchemeTask.didReceive(response)
    urlSchemeTask.didReceive(payload)
    urlSchemeTask.didFinish()
  }

  func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

private struct FusionWebKitView: NSViewRepresentable {
    @ObservedObject var coordinator: AppCoordinator
    let loadURL: URL
    let onReady: (Bool) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
#if DEBUG
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
#endif
        config.setURLSchemeHandler(WasmSchemeHandler(), forURLScheme: "gaiasubstrate")
        // Same-origin `/substrate-raw` iframe must also hole-punch html/body; `forMainFrameOnly: false` applies to child frames.
        let transparencyJS = Self.nativeDomTransparencyBootstrapScript
        let transparencyScript = WKUserScript(source: transparencyJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        config.userContentController.addUserScript(transparencyScript)
        let domWitnessJS = Self.wasmDomShadowWitnessScript
        let domWitnessScript = WKUserScript(source: domWitnessJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(domWitnessScript)
        let wasmRuntimeJS = Self.wasmRuntimeInstantiateScript
        let wasmRuntimeScript = WKUserScript(source: wasmRuntimeJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(wasmRuntimeScript)
        let webView = WKWebView(frame: .zero, configuration: config)
        Self.applyMacOSWebViewTransparencyHolePunch(webView)
        // WebKit often embeds after superview attach — re-punch once the scroll/clip hierarchy exists.
        DispatchQueue.main.async {
            Self.applyMacOSWebViewTransparencyHolePunch(webView)
        }
        webView.setAccessibilityElement(true)
        webView.setAccessibilityRole(.group)
        webView.setAccessibilityIdentifier("fusion_webview_substrate")
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.customUserAgent = "GaiaFusion"

        context.coordinator.webView = webView
        context.coordinator.loadURL = loadURL
        context.coordinator.onReady = onReady
        context.coordinator.bridge = coordinator.bridge
        context.coordinator.bridge?.attachWebView(webView)
        context.coordinator.load()

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        Self.applyMacOSWebViewTransparencyHolePunch(nsView)
        context.coordinator.enforceWebViewSingleton(keeping: nsView)
        if context.coordinator.loadURL != loadURL {
            context.coordinator.loadURL = loadURL
            context.coordinator.load()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// macOS WKWebView: public APIs are insufficient — KVC `drawsBackground` + clear layers + strip `NSScrollView` white backing.
    private static func applyMacOSWebViewTransparencyHolePunch(_ webView: WKWebView) {
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.isOpaque = false
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.enclosingScrollView?.drawsBackground = false
        webView.enclosingScrollView?.backgroundColor = .clear
        if let clip = webView.enclosingScrollView?.contentView {
            clip.drawsBackground = false
            clip.wantsLayer = true
            clip.layer?.isOpaque = false
            clip.layer?.backgroundColor = NSColor.clear.cgColor
        }
        var ancestor: NSView? = webView.superview
        while let cur = ancestor {
            if let sc = cur as? NSScrollView {
                sc.drawsBackground = false
                sc.backgroundColor = .clear
                sc.contentView.drawsBackground = false
                sc.contentView.wantsLayer = true
                sc.contentView.layer?.isOpaque = false
                sc.contentView.layer?.backgroundColor = NSColor.clear.cgColor
            }
            ancestor = cur.superview
        }
    }

    /// Strip solid Next/tailwind `body` / `:root` backgrounds so the native Metal manifold can show through WKWebView.
    private static let nativeDomTransparencyBootstrapScript: String = """
    (function(){
      try {
        document.documentElement.classList.add('gaiafusion-native-bg');
        document.documentElement.style.backgroundColor = 'transparent';
        function holePunchBody() {
          if (document.body) {
            document.body.classList.add('gaiafusion-native-bg');
            document.body.style.backgroundColor = 'transparent';
          }
        }
        holePunchBody();
        document.addEventListener('DOMContentLoaded', holePunchBody);
      } catch (e) {}
    })();
    """

    /// MutationObserver + periodic heartbeat reporting DOM size and **open** shadow-root counts to native (`domWitness`).
    private static let wasmDomShadowWitnessScript: String = """
    (function(){
      var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.domWitness;
      if (!handler) { return; }
      var lastPost = 0;
      function snapshot() {
        var approx = document.getElementsByTagName('*').length;
        var srCount = 0;
        var maxDepth = 0;
        function walk(node, depth) {
          if (!node) { return; }
          maxDepth = Math.max(maxDepth, depth);
          if (node.nodeType === 1 && node.shadowRoot) {
            srCount++;
            walk(node.shadowRoot, depth + 1);
          }
          var ch = node.childNodes;
          for (var i = 0; i < ch.length; i++) {
            walk(ch[i], depth + 1);
          }
        }
        if (document.documentElement) {
          walk(document.documentElement, 0);
        }
        var tsxInvariant = null;
        try {
          var w = window.__GAIAFTCL_FUSION_SURFACE;
          if (w && typeof w === 'object') {
            tsxInvariant = {
              schema: String(w.schema || ''),
              invariant_id: String(w.invariant_id || ''),
              boot_state: String(w.boot_state || ''),
              ts_ms: (typeof w.ts_ms === 'number' && isFinite(w.ts_ms)) ? w.ts_ms : 0
            };
          }
        } catch (e) {}
        return {
          shadow_roots: srCount,
          document_nodes_approx: approx,
          tree_depth_max: maxDepth,
          href: String(location.href || ''),
          tsx_invariant: tsxInvariant
        };
      }
      function post(reason) {
        var now = Date.now();
        if (reason !== 'init' && reason !== 'heartbeat' && (now - lastPost) < 80) { return; }
        lastPost = now;
        try {
          handler.postMessage({ reason: reason, payload: snapshot(), ts: now });
        } catch (e) {}
      }
      post('init');
      try {
        var mo = new MutationObserver(function() { post('mutation'); });
        mo.observe(document.documentElement, { subtree: true, childList: true });
      } catch (e) {}
      setInterval(function() { post('heartbeat'); }, 2000);
    })();
    """

    /// wasm-bindgen: `GET /api/fusion/wasm-substrate-bindgen.js` (ES module) + `GET /api/fusion/wasm-substrate` (`*_bg.wasm`). Raw `WebAssembly.instantiate` cannot load bindgen output — imports come from generated JS.
    private static let wasmRuntimeInstantiateScript: String = """
    (function(){
      var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.wasmRuntime;
      if (!h) { return; }
      function send(p) {
        try { h.postMessage(p); } catch (e) {}
      }
      // WKWebView dynamic import() requires an absolute URL — bare "/api/..." can throw "does not resolve to a valid URL".
      var bindgenUrl = new URL('/api/fusion/wasm-substrate-bindgen.js', window.location.href).href;
      var wasmUrl = new URL('/api/fusion/wasm-substrate', window.location.href).href;
      import(bindgenUrl).then(function(mod) {
        var init = mod.default;
        if (typeof init !== 'function') {
          send({ schema: 'gaiaftcl_wasm_runtime_v1', ok: false, reason: 'bindgen_missing_default_export', ts_ms: Date.now() });
          return;
        }
        return init(wasmUrl);
      }).then(function() {
        send({ schema: 'gaiaftcl_wasm_runtime_v1', ok: true, path: 'wasm_bindgen_init', ts_ms: Date.now(), fallback_from_streaming: false });
      }).catch(function(e) {
        send({ schema: 'gaiaftcl_wasm_runtime_v1', ok: false, reason: String(e), ts_ms: Date.now() });
      });
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        weak var bridge: FusionBridge?
        var loadURL: URL?
        var onReady: ((Bool) -> Void)?
        private var retryTask: DispatchWorkItem?
        private var attached = false

        func enforceWebViewSingleton(keeping keeper: WKWebView) {
            guard let parent = keeper.superview else {
                return
            }
            let all = parent.subviews.compactMap { $0 as? WKWebView }
            guard all.count > 1 else {
                return
            }
            let stale = all.filter { $0 !== keeper }
            if !stale.isEmpty {
                print("[REFUSED] WebKit accumulation detected: \(all.count) WKWebView instances. Purging stale views.")
            }
            for view in stale {
                view.stopLoading()
                view.navigationDelegate = nil
                view.loadHTMLString("", baseURL: nil)
                view.removeFromSuperview()
            }
        }

        func load() {
            guard let webView, let target = loadURL else {
                return
            }

            enforceWebViewSingleton(keeping: webView)

            if !attached {
                webView.configuration.userContentController.add(self.bridge!, name: "fusionBridge")
                webView.configuration.userContentController.add(self.bridge!, name: "domWitness")
                webView.configuration.userContentController.add(self.bridge!, name: "wasmRuntime")
                attached = true
            }
            
            StartupProfiler.shared.checkpoint("webview_load_start")
            webView.load(URLRequest(url: target))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            StartupProfiler.shared.checkpoint("webview_load_finish")
            FusionWebKitView.applyMacOSWebViewTransparencyHolePunch(webView)
            DispatchQueue.main.async {
                FusionWebKitView.applyMacOSWebViewTransparencyHolePunch(webView)
            }
            retryTask?.cancel()
            retryTask = nil
            onReady?(true)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            emitOffline()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            emitOffline()
        }

        private func emitOffline() {
            onReady?(false)
            scheduleRetry()
        }

        private func scheduleRetry() {
            guard retryTask == nil else {
                return
            }
            let task = DispatchWorkItem { [weak self] in
                self?.retryTask = nil
                self?.load()
            }
            retryTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: task)
        }
    }
}
