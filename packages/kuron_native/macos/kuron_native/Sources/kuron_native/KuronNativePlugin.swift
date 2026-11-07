import Cocoa
import FlutterMacOS
import PDFKit
import UniformTypeIdentifiers
import WebKit

public class KuronNativePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "kuron_native", binaryMessenger: registrar.messenger)
    let instance = KuronNativePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    let events = FlutterEventChannel(name: "kuron_native/download_progress",
                                     binaryMessenger: registrar.messenger)
    events.setStreamHandler(KuronDownloadEvents.shared)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    func s(_ k: String) -> String? { args?[k] as? String }
    func i(_ k: String) -> Int? { (args?[k] as? NSNumber)?.intValue }

    switch call.method {
    case "getPlatformVersion":
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)

    case "getSystemInfo":
      result(Self.systemInfo(type: s("type")))

    case "openWebView", "openVideoPlayer":
      guard let urlStr = s("url") ?? s("filePath"), let url = URL(string: urlStr) ?? Self.fileURL(urlStr) else {
        result(FlutterError(code: "INVALID_ARGS", message: "url is required", details: nil)); return
      }
      _ = NSWorkspace.shared.open(url)
      result(nil)

    case "openPdf", "openAvif":
      guard let path = s("filePath") else {
        result(FlutterError(code: "INVALID_ARGS", message: "filePath is required", details: nil)); return
      }
      let url = Self.fileURL(path) ?? URL(fileURLWithPath: path)
      _ = NSWorkspace.shared.open(url)
      result(nil)

    case "openDnsSettings":
      // No Private-DNS API on macOS; open the Network settings pane instead.
      if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") {
        _ = NSWorkspace.shared.open(url)
        result(true)
      } else {
        result(false)
      }

    case "pickDirectory":
      Self.pickPanel(canFiles: false, canDirs: true, multiple: false, types: nil) { urls in
        result(urls.first?.path)
      }

    case "pickTextFile":
      Self.pickPanel(canFiles: true, canDirs: false, multiple: false, types: nil) { urls in
        guard let p = urls.first?.path else { result(nil); return }
        result(try? String(contentsOfFile: p, encoding: .utf8))
      }

    case "pickBinaryFile":
      Self.pickPanel(canFiles: true, canDirs: false, multiple: false, types: nil) { urls in
        guard let p = urls.first?.path, let d = try? Data(contentsOf: URL(fileURLWithPath: p)) else { result(nil); return }
        result(FlutterStandardTypedData(bytes: d))
      }

    case "pickZipFile":
      Self.pickPanel(canFiles: true, canDirs: false, multiple: false, types: ["zip"]) { urls in
        result(urls.first?.path)
      }

    case "pickZipFiles":
      Self.pickPanel(canFiles: true, canDirs: false, multiple: true, types: ["zip"]) { urls in
        result(urls.map { $0.path })
      }

    case "readZipBytes":
      guard let uri = s("contentUri"), let url = Self.localFileURL(uri) else {
        result(FlutterError(code: "INVALID_ARGS", message: "contentUri is required", details: nil)); return
      }
      guard let d = try? Data(contentsOf: url) else {
        result(FlutterError(code: "NOT_FOUND", message: "cannot read \(uri)", details: nil)); return
      }
      result(FlutterStandardTypedData(bytes: d))

    case "getZipDisplayName":
      guard let uri = s("contentUri") else {
        result(FlutterError(code: "INVALID_ARGS", message: "contentUri is required", details: nil)); return
      }
      result(Self.localFileURL(uri)?.lastPathComponent ?? (uri as NSString).lastPathComponent)

    case "extractZipFile":
      guard let uri = s("contentUri"), let dest = s("destinationPath"),
            let src = Self.localFileURL(uri)?.path else {
        result(FlutterError(code: "INVALID_ARGS", message: "contentUri/destinationPath required", details: nil)); return
      }
      do {
        try FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)
        let code = Self.runUsrBin("/usr/bin/unzip", ["-o", "-q", src, "-d", dest])
        if code == 0 {
          result(["success": true, "outputPath": dest])
        } else {
          result(FlutterError(code: "UNZIP_FAILED", message: "unzip exited with code \(code)", details: nil))
        }
      } catch {
        result(FlutterError(code: "UNZIP_FAILED", message: "\(error)", details: nil))
      }

    case "convertImagesToPdf":
      guard let paths = args?["imagePaths"] as? [String], let out = s("outputPath") else {
        result(FlutterError(code: "INVALID_ARGS", message: "imagePaths/outputPath required", details: nil)); return
      }
      result(Self.imagesToPdf(paths: paths, outputPath: out))

    case "clearCookies":
      WKWebsiteDataStore.default().removeData(
        ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
        modifiedSince: .distantPast) { result(nil) }
    case "clearAnimatedWebPCache", "cancelWebPThumbnail":
      // Android in-memory caches; macOS keeps nothing comparable.
      result(nil)

    case "getDohProvider":
      result(-1)

    case "setDohProvider":
      result(false)

    case "getDnsProviderState":
      result(["currentProvider": -1, "providerName": "System", "isEnabled": false])

    case "getPrivateDnsDiagnostics":
      result(nil)

    case "makeHttpRequest":
      guard let urlStr = s("url"), let url = URL(string: urlStr) else {
        result(FlutterError(code: "INVALID_ARGS", message: "url is required", details: nil)); return
      }
      Self.httpRequest(url: url, method: s("method") ?? "GET",
                       headers: args?["headers"] as? [String: String] ?? [:],
                       body: (args?["body"] as? String)?.data(using: .utf8),
                       completion: result)

    case "downloadBinary":
      guard let urlStr = s("url"), let url = URL(string: urlStr) else {
        result(FlutterError(code: "INVALID_ARGS", message: "url is required", details: nil)); return
      }
      Self.downloadData(url: url, headers: args?["headers"] as? [String: String] ?? [:], completion: result)

    case "showLoginWebView":
      KuronWebViewFlows.showLogin(args: args ?? [:], completion: result)

    case "showCaptchaWebView":
      KuronWebViewFlows.showCaptcha(
        provider: s("provider") ?? "",
        siteKey: s("siteKey") ?? "",
        baseUrl: s("baseUrl"),
        completion: result)

    case "getHeadlessClearance":
      guard let url = s("url") else {
        result(FlutterError(code: "INVALID_ARGS", message: "url is required", details: nil)); return
      }
      KuronWebViewFlows.headlessClearance(url: url, userAgent: s("userAgent"), completion: result)

    case "headlessGetClearance":
      guard let url = s("url"), let script = s("script") else {
        result(FlutterError(code: "INVALID_ARGS", message: "url/script required", details: nil)); return
      }
      let timeout = Double(i("timeoutMs") ?? 10000) / 1000.0
      KuronWebViewFlows.headlessEval(url: url, script: script, timeout: timeout, completion: result)

    case "runProxyWebView":
      KuronWebViewFlows.runProxy(args: args ?? [:], completion: result)

    case "kuronNativeStartDownload", "kuronNativeStartDownloadV2":
      result(KuronDownloadCenter.shared.start(args: args ?? [:]))

    case "kuronNativePauseDownload":
      if let id = args?["contentId"] as? String { KuronDownloadCenter.shared.pause(contentId: id) }
      result(nil)

    case "kuronNativeCancelDownload":
      if let id = args?["contentId"] as? String { KuronDownloadCenter.shared.cancel(contentId: id) }
      result(nil)

    case "kuronNativeGetDownloadStatus":
      if let id = args?["contentId"] as? String {
        result(KuronDownloadCenter.shared.status(contentId: id))
      } else { result(nil) }

    case "kuronNativeGetDownloadedFiles":
      if let id = args?["contentId"] as? String {
        result(KuronDownloadCenter.shared.files(contentId: id, in: nil))
      } else { result([] as [String]) }

    case "kuronNativeGetDownloadPath":
      if let id = args?["contentId"] as? String {
        result(KuronDownloadCenter.shared.path(contentId: id, in: nil))
      } else { result(nil) }

    case "kuronNativeDeleteDownloadedContent":
      KuronDownloadCenter.shared.delete(contentId: args?["contentId"] as? String ?? "",
                                        dirPath: args?["dirPath"] as? String)
      result(nil)

    case "kuronNativeCountDownloadedFiles":
      if let id = args?["contentId"] as? String {
        result(KuronDownloadCenter.shared.count(contentId: id, in: nil))
      } else { result(0) }

    default:
      // Thumbnails, bubbles, AVIF conversion: Android-only views/models —
      // Dart falls back gracefully (verified per call-site audit).
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Tier-1 helpers

  private static func fileURL(_ s: String) -> URL? {
    if s.hasPrefix("file://") { return URL(string: s) }
    return nil
  }

  private static func localFileURL(_ uri: String) -> URL? {
    if let u = fileURL(uri) { return u }
    if uri.hasPrefix("/") { return URL(fileURLWithPath: uri) }
    return nil
  }

  @discardableResult
  private static func runUsrBin(_ launchPath: String, _ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launchPath)
    p.arguments = args
    p.standardOutput = Pipe()
    p.standardError = Pipe()
    do {
      try p.run()
      p.waitUntilExit()
      return p.terminationStatus
    } catch {
      return -1
    }
  }

  private static func pickPanel(canFiles: Bool, canDirs: Bool, multiple: Bool, types: [String]?,
                                completion: @escaping ([URL]) -> Void) {
    DispatchQueue.main.async {
      let panel = NSOpenPanel()
      panel.canChooseFiles = canFiles
      panel.canChooseDirectories = canDirs
      panel.allowsMultipleSelection = multiple
      panel.canCreateDirectories = canDirs
      if let types = types {
        panel.allowedContentTypes = types.compactMap { UTType(filenameExtension: $0) }
      }
      guard panel.runModal() == .OK else { completion([]); return }
      completion(panel.urls)
    }
  }

  private static func systemInfo(type: String?) -> [String: Any] {
    var out: [String: Any] = [:]
    if type == "ram" {
      out["total"] = Int64(ProcessInfo.processInfo.physicalMemory)
    }
    out["model"] = Self.modelIdentifier()
    return out
  }

  private static func modelIdentifier() -> String {
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    var machine = [CChar](repeating: 0, count: size)
    sysctlbyname("hw.model", &machine, &size, nil, 0)
    return String(cString: machine)
  }

  /// Android contract: {success, pdfPath, pageCount, fileSize}.
  private static func imagesToPdf(paths: [String], outputPath: String) -> [String: Any] {
    let doc = PDFDocument()
    var count = 0
    for p in paths {
      guard let img = NSImage(contentsOfFile: p),
            let page = PDFPage(image: img) else { continue }
      doc.insert(page, at: doc.pageCount)
      count += 1
    }
    guard count > 0 else { return [:] }
    let url = URL(fileURLWithPath: outputPath)
    try? FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard doc.write(to: url) else { return [:] }
    let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
    return ["success": true, "pdfPath": outputPath, "pageCount": count, "fileSize": fileSize]
  }

  private static func httpRequest(url: URL, method: String, headers: [String: String],
                                 body: Data?, completion: @escaping FlutterResult) {
    var req = URLRequest(url: url)
    req.httpMethod = method
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    req.httpBody = body
    URLSession.shared.dataTask(with: req) { data, resp, err in
      if let err = err {
        completion(FlutterError(code: "HTTP_FAILED", message: "\(err)", details: nil)); return
      }
      let http = resp as? HTTPURLResponse
      var hs: [String: String] = [:]
      (http?.allHeaderFields as? [AnyHashable: Any])?.forEach { k, v in
        hs["\(k)"] = "\(v)"
      }
      completion([
        "statusCode": http?.statusCode ?? 0,
        "headers": hs,
        "body": data.flatMap { String(data: $0, encoding: .utf8) } ?? "",
      ])
    }.resume()
  }

  private static func downloadData(url: URL, headers: [String: String],
                                   completion: @escaping FlutterResult) {
    var req = URLRequest(url: url)
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    URLSession.shared.dataTask(with: req) { data, _, err in
      if let err = err {
        completion(FlutterError(code: "DOWNLOAD_FAILED", message: "\(err)", details: nil)); return
      }
      completion(FlutterStandardTypedData(bytes: data ?? Data()))
    }.resume()
  }
}
