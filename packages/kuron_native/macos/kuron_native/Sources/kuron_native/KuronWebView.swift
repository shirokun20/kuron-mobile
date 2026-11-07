import Cocoa
import FlutterMacOS
import WebKit

/// Headless + windowed WebView flows for macOS.
///
/// Mirrors the Android handlers with the same result contracts:
/// - cookies are ONE combined `"name=a; name=b"` string in a 1-element array
/// - manual close resolves with the harvested state (like Android back/home),
///   timeouts resolve as failure
/// - per-request ephemeral `WKWebView`s, settle-exactly-once, no reuse
enum KuronWebViewFlows {
  static let defaultUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

  // MARK: - Shared plumbing

  fileprivate final class Keeper {
    static var active: [AnyObject] = []
    static func hold(_ o: AnyObject) { active.append(o) }
    static func drop(_ o: AnyObject) { active.removeAll { $0 === o } }
  }

  static func makeWebView(userAgent: String?) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    let view = WKWebView(frame: .zero, configuration: config)
    view.customUserAgent = (userAgent?.isEmpty == false) ? userAgent : defaultUA
    Keeper.hold(view)
    return view
  }

  static func release(_ view: WKWebView) {
    view.configuration.userContentController.removeAllScriptMessageHandlers()
    view.stopLoading()
    Keeper.drop(view)
  }

  /// Android shape: one combined string, like CookieManager.getCookie().
  static func harvestCookies(_ store: WKHTTPCookieStore, completion: @escaping ([String]) -> Void) {
    store.getAllCookies { cookies in
      completion([cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")])
    }
  }

  static func seedCookies(_ store: WKHTTPCookieStore, host: String?,
                          cookieHeader: String?, done: @escaping () -> Void) {
    guard let header = cookieHeader, !header.isEmpty else { done(); return }
    let group = DispatchGroup()
    for pair in header.split(separator: ";") {
      let kv = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
      guard kv.count == 2 else { continue }
      var props: [HTTPCookiePropertyKey: Any] = [.name: kv[0], .value: kv[1], .path: "/"]
      if let host = host, !host.isEmpty { props[.domain] = host }
      if let cookie = HTTPCookie(properties: props) {
        group.enter()
        store.setCookie(cookie) { group.leave() }
      }
    }
    group.notify(queue: .main, execute: done)
  }

  static func evaluate(_ view: WKWebView, _ script: String,
                       completion: @escaping (String?) -> Void) {
    view.evaluateJavaScript(script) { value, _ in
      if let s = value as? String, !s.isEmpty { completion(s); return }
      if let n = value as? NSNumber { completion("\(n)"); return }
      completion(nil)
    }
  }

  /// DOM scrape for the repair flow (resolvedImageUrl).
  static func domImageURLs(view: WKWebView, selectors: [String], attributes: [String],
                           completion: @escaping (String?) -> Void) {
    guard !selectors.isEmpty else { completion(nil); return }
    guard let selJSON = Self.jsonString(selectors),
          let attrJSON = Self.jsonString(attributes) else { completion(nil); return }
    let script = """
      (function(){
        var sels = \(selJSON); var attrs = \(attrJSON);
        function abs(u){ try { return new URL(u, document.baseURI).href; } catch(e){ return u; } }
        var out = [];
        sels.forEach(function(sel){
          try {
            document.querySelectorAll(sel).forEach(function(el){
              var cands = [el.src, el.href];
              attrs.forEach(function(a){ try { var v = el.getAttribute(a); if (v) cands.push(v); } catch(e){} });
              cands.forEach(function(u){ if (u) out.push(abs(u)); });
            });
          } catch(e){}
        });
        return JSON.stringify(out.slice(0, 50));
      })()
      """
    evaluate(view, script) { json in
      guard let json = json,
            let data = json.data(using: .utf8),
            let arr = (try? JSONSerialization.jsonObject(with: data)) as? [String],
            let first = arr.first, !first.isEmpty else { completion(nil); return }
      completion(first)
    }
  }

  private static func jsonString(_ value: [String]) -> String? {
    guard let data = try? JSONSerialization.data(withJSONObject: value),
          let s = String(data: data, encoding: .utf8) else { return nil }
    return s
  }

  // MARK: - Windowed interactive flows (login / captcha)

  private final class WindowFlow: NSObject, WKNavigationDelegate, NSWindowDelegate {
    let window: NSWindow
    let view: WKWebView
    var settled = false
    var onNavigate: ((String) -> Bool)?
    var onClose: (() -> Void)?

    init(title: String, size: NSSize = NSSize(width: 1000, height: 700)) {
      window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.titled, .closable, .resizable, .miniaturizable],
                        backing: .buffered, defer: false)
      window.title = title
      window.minSize = NSSize(width: 480, height: 360)
      view = KuronWebViewFlows.makeWebView(userAgent: nil)
      super.init()
      view.navigationDelegate = self
      window.delegate = self
      window.contentView = view
      window.center()
    }

    func show() { window.makeKeyAndOrderFront(nil) }

    func finish() {
      guard !settled else { return }
      settled = true
      onClose = nil
      onNavigate = nil
      let v = view
      window.orderOut(nil)
      KuronWebViewFlows.release(v)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
      if let url = action.request.url?.absoluteString, let check = onNavigate, check(url) {
        decisionHandler(.cancel)
        return
      }
      decisionHandler(.allow)
    }

    func windowWillClose(_ notification: Notification) { finish() }
  }

  /// Manual login dialog equivalent: visible window. Resolves with the
  /// harvested state on success-URL match, autoClose cookie, finished-script
  /// token, or manual close (like Android back/home). Timeout fails.
  static func showLogin(args: [String: Any], completion: @escaping FlutterResult) {
    DispatchQueue.main.async {
      guard let pageUrl = args["url"] as? String, let target = URL(string: pageUrl) else {
        completion(FlutterError(code: "INVALID_ARGS", message: "url is required", details: nil)); return
      }
      let filters = args["successUrlFilters"] as? [String] ?? []
      let autoCookie = args["autoCloseOnCookie"] as? String
      let finishedScript = args["pageFinishedScript"] as? String
      let selectors = args["domImageSelectors"] as? [String] ?? []
      let attributes = args["domImageAttributes"] as? [String] ?? []
      let flow = WindowFlow(title: target.host ?? pageUrl)
      Keeper.hold(flow)
      var done = false
      func settle(_ map: [String: Any]) {
        guard !done else { return }
        done = true
        flow.finish()
        Keeper.drop(flow)
        completion(map)
      }
      func resolveState(extra: [String: Any] = [:]) {
        harvestCookies(flow.view.configuration.websiteDataStore.httpCookieStore) { cookies in
          domImageURLs(view: flow.view, selectors: selectors, attributes: attributes) { resolved in
            var map: [String: Any] = [
              "success": true,
              "cookies": cookies,
              "userAgent": flow.view.customUserAgent ?? defaultUA,
              "currentUrl": flow.view.url?.absoluteString ?? pageUrl,
              "usedSslFallback": false,
            ]
            if let resolved = resolved { map["resolvedImageUrl"] = resolved }
            extra.forEach { map[$0] = $1 }
            settle(map)
          }
        }
      }
      flow.onNavigate = { url in
        if filters.contains(where: { url.contains($0) }) { resolveState(); return true }
        return false
      }
      if let ua = args["userAgent"] as? String, !ua.isEmpty { flow.view.customUserAgent = ua }
      let store = flow.view.configuration.websiteDataStore.httpCookieStore
      seedCookies(store, host: target.host, cookieHeader: args["initialCookie"] as? String) {
        _ = flow.view.load(URLRequest(url: target))
        flow.show()
      }
      // Auto-close cookie + finished-script token polling.
      var poller: Timer?
      poller = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
        guard !done else { poller?.invalidate(); return }
        if let need = autoCookie, !need.isEmpty {
          harvestCookies(store) { cookies in
            if !done, cookies.joined().contains(need) { poller?.invalidate(); resolveState() }
          }
        }
        if let script = finishedScript, !script.isEmpty {
          evaluate(flow.view, script) { token in
            if !done, let token = token {
              poller?.invalidate()
              resolveState(extra: ["pageFinishedScriptResult": token])
            }
          }
        } else if autoCookie == nil || autoCookie!.isEmpty {
          poller?.invalidate()
        }
      }
      // Manual close (window X) resolves with current state, like Android.
      flow.onClose = { resolveState() }
      DispatchQueue.main.asyncAfter(deadline: .now() + 600) {
        if !done { settle(["success": false]) }
      }
    }
  }

  /// Challenge widget equivalent: serves the provider widget (Turnstile /
  /// hCaptcha, same markup as Android) and resolves on the token bridge.
  static func showCaptcha(provider: String, siteKey: String, baseUrl: String?,
                          completion: @escaping FlutterResult) {
    DispatchQueue.main.async {
      let flow = WindowFlow(title: "Captcha", size: NSSize(width: 520, height: 640))
      Keeper.hold(flow)
      var done = false
      func settle(_ map: [String: Any]) {
        guard !done else { return }
        done = true
        flow.finish()
        Keeper.drop(flow)
        completion(map)
      }
      let handler = CaptchaBridge { token in
        if let token = token, !token.isEmpty { settle(["success": true, "token": token]) }
      }
      flow.view.configuration.userContentController.add(handler, name: "captcha")
      flow.onClose = { settle(["success": false]) }
      _ = flow.view.loadHTMLString(Self.captchaHTML(provider: provider, siteKey: siteKey),
                                   baseURL: baseUrl.flatMap(URL.init(string:)))
      flow.show()
      DispatchQueue.main.asyncAfter(deadline: .now() + 120) {
        settle(["success": false])
      }
    }
  }

  private final class CaptchaBridge: NSObject, WKScriptMessageHandler {
    let onToken: (String?) -> Void
    init(onToken: @escaping (String?) -> Void) {
      self.onToken = onToken
      super.init()
    }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
      if let d = m.body as? [String: Any] {
        onToken(d["token"] as? String)
      } else if let s = m.body as? String {
        onToken(s)
      } else {
        onToken(nil)
      }
    }
  }

  private static func captchaHTML(provider: String, siteKey: String) -> String {
    let lower = provider.lowercased()
    let widget: String
    if lower.contains("hcaptcha") {
      widget = """
        <script src="https://js.hcaptcha.com/1/api.js" async defer></script>
        <div class="h-captcha" data-sitekey="\(siteKey)" data-callback="onSolved" data-expired-callback="onExpired"></div>
        """
    } else {
      widget = """
        <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
        <div class="cf-turnstile" data-sitekey="\(siteKey)" data-callback="onSolved" data-error-callback="onError" data-expired-callback="onExpired" data-retry="never"></div>
        """
    }
    return """
      <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1" /></head>
      <body style="font-family:-apple-system,sans-serif;padding:16px">
      <div style="max-width:460px;margin:32px auto"><h3>Captcha</h3><p>Please complete the challenge.</p>\(widget)</div>
      <script>
        function onSolved(token) {
          window.webkit.messageHandlers.captcha.postMessage({token: token || ""});
        }
        function onError(code) { window.webkit.messageHandlers.captcha.postMessage({token: ""}); }
        function onExpired() { window.webkit.messageHandlers.captcha.postMessage({token: ""}); }
      </script></body></html>
      """
  }

  // MARK: - Headless flows

  /// Passive clearance check: load the URL, poll
  /// `window.localStorage.getItem('clearance')` like Android (500ms x30
  /// after a 1s settle delay), harvest cookies, and return the minted
  /// token when present. Without the token poll the driver can never
  /// succeed headlessly and always falls through to the visible popup.
  static func headlessClearance(url: String, userAgent: String? = nil, completion: @escaping FlutterResult) {
    DispatchQueue.main.async {
      let view = makeWebView(userAgent: userAgent)
      var done = false
      var timer: Timer?
      var delegate: HeadlessDelegate?
      func settle(_ map: [String: Any]) {
        guard !done else { return }
        done = true
        if let t = timer { t.invalidate(); Keeper.drop(t) }
        if let d = delegate { Keeper.drop(d) }
        release(view)
        completion(map)
      }
      func harvestAndSettle(token: String?) {
        harvestCookies(view.configuration.websiteDataStore.httpCookieStore) { cookies in
          var map: [String: Any] = [
            "success": true,
            "cookies": cookies,
            "userAgent": view.customUserAgent ?? defaultUA,
            "currentUrl": view.url?.absoluteString ?? url,
          ]
          if let token = token { map["token"] = token }
          settle(map)
        }
      }
      guard let target = URL(string: url) else {
        settle(["success": false, "cookies": [], "userAgent": defaultUA, "currentUrl": url]); return
      }
      delegate = HeadlessDelegate(onFinish: {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
          guard !done else { return }
          var attempts = 0
          timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            guard !done else { timer?.invalidate(); return }
            evaluate(view, "window.localStorage.getItem('clearance')") { raw in
              guard !done else { return }
              let token = (raw ?? "").replacingOccurrences(of: "\"", with: "")
              if !token.isEmpty, token != "null" {
                timer?.invalidate()
                harvestAndSettle(token: token)
                return
              }
              attempts += 1
              if attempts >= 30 {
                timer?.invalidate()
                harvestAndSettle(token: nil)
              }
            }
          }
          if let t = timer { Keeper.hold(t) }
        }
      })
      if let d = delegate { Keeper.hold(d) }
      view.navigationDelegate = delegate
      _ = view.load(URLRequest(url: target))
      DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
        settle(["success": false, "cookies": [],
                "userAgent": view.customUserAgent ?? defaultUA,
                "currentUrl": view.url?.absoluteString ?? url])
      }
    }
  }

  private final class HeadlessDelegate: NSObject, WKNavigationDelegate {
    let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) {
      self.onFinish = onFinish
      super.init()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinish() }
  }

  /// Evaluate `script` until it returns a non-empty string or timeout.
  static func headlessEval(url: String, script: String, timeout: TimeInterval,
                           completion: @escaping FlutterResult) {
    DispatchQueue.main.async {
      guard let target = URL(string: url) else {
        completion(FlutterError(code: "INVALID_ARGS", message: "bad url", details: nil)); return
      }
      let view = makeWebView(userAgent: nil)
      var done = false
      var timer: Timer?
      let deadline = Date().addingTimeInterval(timeout)
      func settle(_ value: String) {
        guard !done else { return }
        done = true
        if let t = timer { t.invalidate(); Keeper.drop(t) }
        release(view)
        completion(value)
      }
      _ = view.load(URLRequest(url: target))
      timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
        if Date() > deadline { settle(""); return }
        evaluate(view, script) { out in
          if let out = out, !done { settle(out) }
        }
      }
      if let timer = timer { Keeper.hold(timer) }
    }
  }

  // MARK: - Proxy engine (Comix runInWebView port)

  /// Loads caller HTML with the bootstrap prepended to <head>, bridges post
  /// payloads, polls the capture script, allowlists hosts via content
  /// blockers, and settles exactly once (120s deadline, extended on traffic).
  static func runProxy(args: [String: Any], completion: @escaping FlutterResult) {
    DispatchQueue.main.async {
      guard let pageUrl = args["pageUrl"] as? String,
            let html = args["html"] as? String,
            let captureScript = args["captureScript"] as? String,
            let bridge = args["bridgeName"] as? String,
            let errorBridge = args["errorBridgeName"] as? String else {
        completion(FlutterError(code: "INVALID_ARGS",
                                message: "pageUrl/html/captureScript/bridgeName/errorBridgeName required",
                                details: nil)); return
      }
      let session = ProxySession(
        pageUrl: pageUrl,
        html: html,
        userAgent: (args["userAgent"] as? String) ?? "",
        allowedHosts: args["allowedHosts"] as? [String] ?? [],
        bootstrap: (args["bootstrapScript"] as? String) ?? "",
        capture: captureScript,
        bridge: bridge, errorBridge: errorBridge,
        pollMs: (args["pollIntervalMs"] as? NSNumber)?.intValue ?? 100,
        extendOnTraffic: (args["extendDeadlineOnApiTraffic"] as? NSNumber)?.boolValue ?? false,
        completion: completion)
      Keeper.hold(session)
      session.start()
    }
  }

  private final class ProxySession: NSObject, WKScriptMessageHandler {
    let pageUrl: String
    let html: String
    let userAgent: String
    let allowedHosts: [String]
    let bootstrap: String
    let capture: String
    let bridge: String
    let errorBridge: String
    let pollMs: Int
    let extendOnTraffic: Bool
    let completion: FlutterResult
    var view: WKWebView?
    var timer: Timer?
    var deadline = Date.distantFuture
    var done = false

    init(pageUrl: String, html: String, userAgent: String, allowedHosts: [String],
         bootstrap: String, capture: String, bridge: String, errorBridge: String,
         pollMs: Int, extendOnTraffic: Bool, completion: @escaping FlutterResult) {
      self.pageUrl = pageUrl; self.html = html; self.userAgent = userAgent
      self.allowedHosts = allowedHosts; self.bootstrap = bootstrap
      self.capture = capture; self.bridge = bridge; self.errorBridge = errorBridge
      self.pollMs = pollMs; self.extendOnTraffic = extendOnTraffic
      self.completion = completion
      super.init()
    }

    func start() {
      deadline = Date().addingTimeInterval(120)
      let config = WKWebViewConfiguration()
      config.websiteDataStore = .nonPersistent()
      let rules = Self.blockRules(except: allowedHosts)
      WKContentRuleListStore.default().compileContentRuleList(
        forIdentifier: "kuron-proxy-\(UUID().uuidString)", encodedContentRuleList: rules) { [weak self] list, _ in
        guard let self = self, !self.done else { return }
        if let list = list { config.userContentController.add(list) }
        self.launch(config: config)
      }
    }

    private static func blockRules(except hosts: [String]) -> String {
      var rules: [[String: Any]] = [
        ["trigger": ["url-filter": ".*", "resource-type": ["image", "style-sheet", "font", "media"]],
         "action": ["type": "block"]],
      ]
      for h in hosts {
        let bare = h.hasPrefix(".") ? String(h.dropFirst()) : h
        let e = NSRegularExpression.escapedPattern(for: bare)
        rules.append(["trigger": ["url-filter": ".*\(e).*"],
                      "action": ["type": "ignore-previous-rules"]])
      }
      let data = (try? JSONSerialization.data(withJSONObject: rules)) ?? Data()
      return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func launch(config: WKWebViewConfiguration) {
      let view = WKWebView(frame: .zero, configuration: config)
      view.customUserAgent = userAgent.isEmpty ? KuronWebViewFlows.defaultUA : userAgent
      view.configuration.userContentController.add(self, name: bridge)
      view.configuration.userContentController.add(self, name: errorBridge)
      self.view = view
      KuronWebViewFlows.Keeper.hold(view)
      var doc = html
      if !bootstrap.isEmpty {
        let tag = "<script>\(bootstrap)</script>"
        if let r = doc.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) {
          doc.insert(contentsOf: tag, at: r.upperBound)
        } else {
          doc = tag + doc
        }
      }
      _ = view.loadHTMLString(doc, baseURL: URL(string: pageUrl))
      var timer: Timer?
      timer = Timer.scheduledTimer(withTimeInterval: Double(pollMs) / 1000.0, repeats: true) { [weak self] _ in
        self?.poll()
      }
      self.timer = timer
      if let timer = timer { KuronWebViewFlows.Keeper.hold(timer) }
    }

    private func poll() {
      guard !done, let view = view else { return }
      if Date() > deadline {
        settleError("deadline exceeded (120s)")
        return
      }
      KuronWebViewFlows.evaluate(view, capture) { [weak self] out in
        // Traffic signal: a non-empty (but incomplete) capture means the
        // page is still producing data — push the deadline out.
        if let self = self, self.extendOnTraffic, out != nil {
          self.deadline = Date().addingTimeInterval(120)
        }
      }
    }

    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
      guard !done else { return }
      if m.name == bridge {
        if let s = m.body as? String { settleSuccess(s); return }
        if let d = m.body as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: d),
           let s = String(data: data, encoding: .utf8) { settleSuccess(s); return }
        settleSuccess("")
      } else if m.name == errorBridge {
        settleError("\(m.body)")
      }
    }

    private func settleSuccess(_ payload: String) {
      guard !done else { return }
      done = true
      teardown()
      completion(payload)
    }

    private func settleError(_ message: String) {
      guard !done else { return }
      done = true
      teardown()
      completion(FlutterError(code: "WEBVIEW_PROXY", message: "Proxy WebView failed: \(message)", details: nil))
    }

    private func teardown() {
      if let t = timer { t.invalidate(); KuronWebViewFlows.Keeper.drop(t) }
      timer = nil
      if let view = view {
        view.configuration.userContentController.removeAllScriptMessageHandlers()
        view.stopLoading()
        KuronWebViewFlows.release(view)
      }
      KuronWebViewFlows.Keeper.drop(self)
    }
  }
}
