package id.nhasix.kuron_native.kuron_native

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.Result
import java.io.ByteArrayInputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * Per-request headless WebView for the WebView proxy engine.
 *
 * Exact behavior port of keiyoushi Comix.kt `runInWebView`:
 * - loads the caller-provided page HTML via loadDataWithBaseURL with the
 *   bootstrap script (atob hijack + payload bridges) prepended to <head>
 * - blocks images, applies the caller user-agent
 * - interceptRequest allowlists only the given hosts (exact match, or
 *   parent-domain match for entries starting with '.'), everything else
 *   gets an empty text/plain response
 * - evaluates the capture script onPageStarted / onPageFinished and every
 *   [pollMs]; resolves when the payload bridge posts, rejects on the error
 *   bridge or after 120s (deadline extended on chapter-list API traffic
 *   when requested)
 * - destroys the WebView exactly once on completion (no reuse)
 *
 * The WebView gets a real 1080x1920 viewport and — when an Activity is
 * available — is attached off-screen and invisible to the Activity window.
 * A 0x0 detached WebView reports `window.innerWidth/innerHeight === 0`,
 * so Chromium's IntersectionObserver never fires and lazy content (reader
 * `.rpage-page` images) never materializes. Attachment makes lazy loading
 * behave like a real viewport.
 */
class ProxyWebViewHandler(
    private val context: Context,
    private val activity: Activity? = null,
) {

    /// Active proxy requests by bridge name. Each entry settles its WebView
    /// as cancelled (detach + stopLoading + destroy) without posting a
    /// result; entries are removed on every settlement path.
    private val activeCancellations = ConcurrentHashMap<String, () -> Unit>()

    /// Cancels the in-flight request registered under [bridgeName].
    /// Returns true when an active WebView was torn down.
    fun cancel(bridgeName: String): Boolean {
        val settle = activeCancellations.remove(bridgeName) ?: return false
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            runCatching { settle() }
        }
        return true
    }

    fun handle(call: MethodCall, result: Result) {
        val pageUrl = call.argument<String>("pageUrl") ?: run {
            result.error("INVALID_ARGS", "pageUrl is required", null); return
        }
        val html = call.argument<String>("html") ?: run {
            result.error("INVALID_ARGS", "html is required", null); return
        }
        val userAgent = call.argument<String>("userAgent").orEmpty()
        @Suppress("UNCHECKED_CAST")
        val allowedHosts = (call.argument<List<String>>("allowedHosts") ?: emptyList())
        val bootstrapScript = call.argument<String>("bootstrapScript").orEmpty()
        val captureScript = call.argument<String>("captureScript") ?: run {
            result.error("INVALID_ARGS", "captureScript is required", null); return
        }
        val bridgeName = call.argument<String>("bridgeName") ?: run {
            result.error("INVALID_ARGS", "bridgeName is required", null); return
        }
        val errorBridgeName = call.argument<String>("errorBridgeName") ?: run {
            result.error("INVALID_ARGS", "errorBridgeName is required", null); return
        }
        val pollMs = (call.argument<Int>("pollIntervalMs") ?: 100).toLong()
        val extendDeadline = call.argument<Boolean>("extendDeadlineOnApiTraffic") ?: false

        Handler(Looper.getMainLooper()).post {
            try {
                runRequest(
                    pageUrl, html, userAgent, allowedHosts, bootstrapScript,
                    captureScript, bridgeName, errorBridgeName, pollMs,
                    extendDeadline, result,
                )
            } catch (e: Exception) {
                // Never leave the Dart side hanging: every path settles.
                android.util.Log.e(TAG, "runProxyWebView failed for $pageUrl", e)
                runCatching {
                    result.error(
                        "WEBVIEW_PROXY",
                        "Proxy WebView failed: ${e.message}",
                        null,
                    )
                }
            }
        }
    }

    @Suppress("SetJavaScriptEnabled")
    private fun runRequest(
        pageUrl: String,
        html: String,
        userAgent: String,
        allowedHosts: List<String>,
        bootstrapScript: String,
        captureScript: String,
        bridgeName: String,
        errorBridgeName: String,
        pollMs: Long,
        extendDeadline: Boolean,
        result: Result,
    ) {
        val deadline = AtomicLong(System.nanoTime() + TIMEOUT_SECONDS * 1_000_000_000L)
        val settled = AtomicBoolean(false)
        val main = Handler(Looper.getMainLooper())

        fun settleSuccess(payload: String, webView: WebView) {
            if (!settled.compareAndSet(false, true)) return
            activeCancellations.remove(bridgeName)
            android.util.Log.i(
                TAG,
                "captured ${payload.length} chars for $pageUrl",
            )
            main.removeCallbacksAndMessages(null)
            // Bridges fire on the JavaBridge thread: WebView methods must
            // run on the main thread (StrictMode violation otherwise).
            main.post {
                runCatching { webView.stopLoading() }
                runCatching {
                    (webView.parent as? ViewGroup)?.removeView(webView)
                }
                runCatching { webView.destroy() }
            }
            result.success(payload)
        }

        fun settleError(message: String, webView: WebView) {
            if (!settled.compareAndSet(false, true)) return
            activeCancellations.remove(bridgeName)
            android.util.Log.w(TAG, "failed for $pageUrl: $message")
            main.removeCallbacksAndMessages(null)
            main.post {
                runCatching { webView.stopLoading() }
                runCatching {
                    (webView.parent as? ViewGroup)?.removeView(webView)
                }
                runCatching { webView.destroy() }
            }
            result.error("WEBVIEW_PROXY", message, null)
        }

        val webView = WebView(context)
        with(webView.settings) {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            blockNetworkImage = true
            if (userAgent.isNotEmpty()) this.userAgentString = userAgent
        }
        // A 0x0 detached WebView reports window.innerWidth/innerHeight === 0
        // and Chromium's IntersectionObserver never fires, so lazy content
        // (reader `.rpage-page` images) never materializes. Give the WebView
        // a real 1080x1920 viewport, and attach it off-screen and invisible
        // to the Activity window when one is available.
        webView.measure(
            View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(1920, View.MeasureSpec.EXACTLY),
        )
        webView.layout(0, 0, 1080, 1920)
        val hostActivity = activity
        if (hostActivity != null &&
            !hostActivity.isFinishing &&
            !hostActivity.isDestroyed
        ) {
            runCatching {
                val decor = hostActivity.window?.decorView as? ViewGroup
                if (webView.parent == null && decor != null) {
                    val params = FrameLayout.LayoutParams(1080, 1920)
                    webView.layoutParams = params
                    webView.alpha = 0f
                    webView.translationX = -99999f
                    webView.isFocusable = false
                    webView.isClickable = false
                    webView.importantForAccessibility =
                        View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
                    decor.addView(webView)
                }
            }
        }

        val emptyResponse: () -> WebResourceResponse = {
            WebResourceResponse("text/plain", "utf-8", ByteArrayInputStream(ByteArray(0)))
        }

        webView.addJavascriptInterface(object {
            @JavascriptInterface
            fun post(message: String) = settleSuccess(message, webView)
        }, bridgeName)
        webView.addJavascriptInterface(object {
            @JavascriptInterface
            fun post(message: String) = settleError(message.ifEmpty { "WebView error" }, webView)
        }, errorBridgeName)

        // Cancellation entry: tears the WebView down without posting a
        // result (the Dart side reports the cancellation itself). Removed
        // on every settlement path above.
        activeCancellations[bridgeName] = {
            main.removeCallbacksAndMessages(null)
            runCatching { webView.stopLoading() }
            runCatching {
                (webView.parent as? ViewGroup)?.removeView(webView)
            }
            runCatching { webView.destroy() }
        }

        fun evaluateCapture() {
            if (settled.get()) return
            runCatching { webView.evaluateJavascript(captureScript, null) }
        }

        val poller = object : Runnable {
            override fun run() {
                if (settled.get()) return
                if (System.nanoTime() >= deadline.get()) {
                    settleError("Timed out waiting for WebView", webView)
                    return
                }
                evaluateCapture()
                main.postDelayed(this, pollMs)
            }
        }

        webView.webChromeClient = object : android.webkit.WebChromeClient() {
            override fun onConsoleMessage(
                message: android.webkit.ConsoleMessage?,
            ): Boolean {
                android.util.Log.d(
                    TAG,
                    "console [${message?.messageLevel()}] ${message?.message()}",
                )
                return true
            }
        }

        webView.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(
                view: WebView?,
                request: WebResourceRequest?,
            ): WebResourceResponse? {
                val url = request?.url?.toString() ?: return emptyResponse()
                val host = request.url?.host.orEmpty()
                if (extendDeadline && url.contains("/api/v1/manga/") && url.contains("chapters")) {
                    deadline.set(System.nanoTime() + TIMEOUT_SECONDS * 1_000_000_000L)
                }
                val allowed = allowedHosts.any { entry ->
                    if (entry.startsWith(".")) {
                        host == entry.drop(1) || host.endsWith(entry)
                    } else {
                        host == entry
                    }
                }
                if (!allowed) {
                    android.util.Log.d(TAG, "blocked $url")
                }
                return if (allowed) null else emptyResponse()
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: android.webkit.WebResourceError?,
            ) {
                android.util.Log.w(
                    TAG,
                    "resource error ${request?.url} ${error?.description}",
                )
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                evaluateCapture()
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                evaluateCapture()
            }
        }

        val withBootstrap = injectBootstrap(html, bootstrapScript)
        webView.loadDataWithBaseURL(pageUrl, withBootstrap, "text/html", "utf-8", null)
        main.postDelayed(poller, pollMs)
    }

    private fun injectBootstrap(html: String, bootstrap: String): String {
        if (bootstrap.isEmpty()) return html
        val tag = "<script>$bootstrap</script>"
        val headIndex = html.indexOf("<head", ignoreCase = true)
        if (headIndex != -1) {
            val close = html.indexOf('>', headIndex)
            if (close != -1) {
                return html.substring(0, close + 1) + tag + html.substring(close + 1)
            }
        }
        return tag + html
    }

    companion object {
        private const val TAG = "MFPROXY"
        private const val TIMEOUT_SECONDS = 120L
    }
}
