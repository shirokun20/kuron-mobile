package id.nhasix.kuron_native.kuron_native

import android.app.Activity
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.webkit.WebResourceResponse
import android.os.Bundle
import android.view.MenuItem
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.net.http.SslError
import android.webkit.SslErrorHandler
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import java.io.ByteArrayInputStream
import org.json.JSONArray
import org.json.JSONObject

class WebViewActivity : AppCompatActivity() {

    companion object {
        const val EXTRA_URL = "extra_url"
        const val EXTRA_USER_AGENT = "extra_user_agent"
        const val EXTRA_SUCCESS_FILTERS = "extra_success_filters"
        const val EXTRA_INITIAL_COOKIE = "extra_initial_cookie"
        const val EXTRA_AUTO_CLOSE_ON_COOKIE = "extra_auto_close_on_cookie"
        const val EXTRA_SSO_REDIRECT_URL = "extra_sso_redirect_url"
        const val EXTRA_ENABLE_AD_BLOCK = "extra_enable_ad_block"
        const val EXTRA_CLEAR_COOKIES = "extra_clear_cookies"
        const val EXTRA_DOM_IMAGE_SELECTORS = "extra_dom_image_selectors"
        const val EXTRA_DOM_IMAGE_ATTRIBUTES = "extra_dom_image_attributes"
        const val EXTRA_DOM_LINK_SELECTORS = "extra_dom_link_selectors"
        const val EXTRA_CAPTURE_REQUEST_PATTERNS = "extra_capture_request_patterns"
        const val EXTRA_ALLOW_REQUEST_PATTERNS = "extra_allow_request_patterns"
        const val EXTRA_PAGE_FINISHED_SCRIPT = "extra_page_finished_script"
        const val EXTRA_BLOCK_NETWORK_IMAGES = "extra_block_network_images"
        const val EXTRA_BACKGROUND_COLOR = "extra_background_color"
        const val EXTRA_TEXT_COLOR = "extra_text_color"
        const val EXTRA_REFERER = "extra_referer"
        const val EXTRA_TITLE = "extra_title"

        const val RESULT_USED_SSL_FALLBACK = "result_used_ssl_fallback"
        const val RESULT_COOKIES = "result_cookies" // ArrayList<String>
        const val RESULT_USER_AGENT = "result_user_agent"
        const val RESULT_CURRENT_URL = "result_current_url"
        const val RESULT_RESOLVED_IMAGE_URL = "result_resolved_image_url"
        const val RESULT_CAPTURED_REQUEST_URL = "result_captured_request_url"
        const val RESULT_PAGE_HTML = "result_page_html"
        const val RESULT_CAPTURED_IMAGE_URLS = "result_captured_image_urls"
        
        fun createIntent(
            context: Context, 
            url: String, 
            userAgent: String?, 
            successFilters: List<String>?,
            initialCookie: String?,
            autoCloseOnCookie: String? = null,
            ssoRedirectUrl: String? = null,
            domImageSelectors: List<String>? = null,
            domImageAttributes: List<String>? = null,
            domLinkSelectors: List<String>? = null,
            captureRequestPatterns: List<String>? = null,
            allowRequestPatterns: List<String>? = null,
            pageFinishedScript: String? = null,
            blockNetworkImages: Boolean = false,
            enableAdBlock: Boolean = false,
            clearCookies: Boolean = false,
            backgroundColor: String? = null,
            textColor: String? = null
        ): Intent {
            return Intent(context, WebViewActivity::class.java).apply {
                putExtra(EXTRA_URL, url)
                if (userAgent != null) putExtra(EXTRA_USER_AGENT, userAgent)
                if (successFilters != null) putStringArrayListExtra(EXTRA_SUCCESS_FILTERS, ArrayList(successFilters))
                if (initialCookie != null) putExtra(EXTRA_INITIAL_COOKIE, initialCookie)
                if (autoCloseOnCookie != null) putExtra(EXTRA_AUTO_CLOSE_ON_COOKIE, autoCloseOnCookie)
                if (ssoRedirectUrl != null) putExtra(EXTRA_SSO_REDIRECT_URL, ssoRedirectUrl)
                if (domImageSelectors != null) putStringArrayListExtra(EXTRA_DOM_IMAGE_SELECTORS, ArrayList(domImageSelectors))
                if (domImageAttributes != null) putStringArrayListExtra(EXTRA_DOM_IMAGE_ATTRIBUTES, ArrayList(domImageAttributes))
                if (domLinkSelectors != null) putStringArrayListExtra(EXTRA_DOM_LINK_SELECTORS, ArrayList(domLinkSelectors))
                if (captureRequestPatterns != null) putStringArrayListExtra(EXTRA_CAPTURE_REQUEST_PATTERNS, ArrayList(captureRequestPatterns))
                if (allowRequestPatterns != null) putStringArrayListExtra(EXTRA_ALLOW_REQUEST_PATTERNS, ArrayList(allowRequestPatterns))
                if (pageFinishedScript != null) putExtra(EXTRA_PAGE_FINISHED_SCRIPT, pageFinishedScript)
                putExtra(EXTRA_BLOCK_NETWORK_IMAGES, blockNetworkImages)
                putExtra(EXTRA_ENABLE_AD_BLOCK, enableAdBlock)
                if (clearCookies) putExtra(EXTRA_CLEAR_COOKIES, true)
                if (backgroundColor != null) putExtra(EXTRA_BACKGROUND_COLOR, backgroundColor)
                if (textColor != null) putExtra(EXTRA_TEXT_COLOR, textColor)
            }
        }
    }

    private lateinit var webView: WebView
    private var successFilters: List<String> = emptyList()
    private var autoCloseOnCookie: String? = null
    private var ssoRedirectUrl: String? = null
    private var enableAdBlock: Boolean = false
    private var domImageSelectors: List<String> = emptyList()
    private var domImageAttributes: List<String> = emptyList()
    private var domLinkSelectors: List<String> = emptyList()
    private var captureRequestPatterns: List<String> = emptyList()
    private var allowRequestPatterns: List<String> = emptyList()
    private var pageFinishedScript: String? = null
    private var blockNetworkImages: Boolean = false
    private var hasFinishedResult = false
    private var usedSslFallback = false
    private var pageFinishedScriptResult: String? = null
    private var capturedPageHtmlPath: String? = null
    private val capturedImageUrls = mutableListOf<String>()
    private val sslConsentHosts = mutableSetOf<String>()
    private var sessionTargetHost: String? = null

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Enable Edge-to-Edge (like PdfReaderActivity)
        WindowCompat.setDecorFitsSystemWindows(window, false)

        // Use NoActionBar theme in Manifest, so we build our own layout
        // Root config
        val rootLayout = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            layoutParams = android.view.ViewGroup.LayoutParams(
                android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                android.view.ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        
        // Handle System Insets (Status Bar)
        ViewCompat.setOnApplyWindowInsetsListener(rootLayout) { view, windowInsets ->
            val insets = windowInsets.getInsets(WindowInsetsCompat.Type.systemBars())
            // Apply top padding so Toolbar doesn't overlap Status Bar
            view.setPadding(insets.left, insets.top, insets.right, insets.bottom) 
            WindowInsetsCompat.CONSUMED
        }

        // Toolbar
        val toolbar = androidx.appcompat.widget.Toolbar(this).apply {
            layoutParams = android.widget.LinearLayout.LayoutParams(
                android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                android.util.TypedValue.applyDimension(
                    android.util.TypedValue.COMPLEX_UNIT_DIP, 
                    56f, 
                    resources.displayMetrics
                ).toInt()
            )
            elevation = 4f
            translationZ = 4f
        }
        rootLayout.addView(toolbar)
        setSupportActionBar(toolbar)
        
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        supportActionBar?.title = "Login"

        // "Login" is this activity's original job; video playback reuses it
        // and needs its own label.
        intent.getStringExtra(EXTRA_TITLE)?.let { supportActionBar?.title = it }

        // WebView
        webView = WebView(this).apply {
            layoutParams = android.widget.LinearLayout.LayoutParams(
                android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1f // Weight 1 to fill remaining space
            )
        }
        rootLayout.addView(webView)
        
        setContentView(rootLayout)

        val bgColorHex = intent.getStringExtra(EXTRA_BACKGROUND_COLOR)
        val txtColorHex = intent.getStringExtra(EXTRA_TEXT_COLOR)

        if (bgColorHex != null) {
            try {
                val parsedBgColor = android.graphics.Color.parseColor(bgColorHex)
                rootLayout.setBackgroundColor(parsedBgColor)
                toolbar.setBackgroundColor(parsedBgColor)
                webView.setBackgroundColor(parsedBgColor)
                
                // Adjust status bar text color based on luminance
                val luminance = (0.299 * android.graphics.Color.red(parsedBgColor) + 0.587 * android.graphics.Color.green(parsedBgColor) + 0.114 * android.graphics.Color.blue(parsedBgColor)) / 255
                val isLight = luminance > 0.5
                WindowCompat.getInsetsController(window, window.decorView).isAppearanceLightStatusBars = isLight
            } catch (e: Exception) {
                // Ignore parsing errors, keep default theme
            }
        } else {
            toolbar.setBackgroundColor(android.graphics.Color.parseColor("#FFFFFF"))
        }

        if (txtColorHex != null) {
            try {
                val parsedTxtColor = android.graphics.Color.parseColor(txtColorHex)
                toolbar.setTitleTextColor(parsedTxtColor)
                
                // Color back button and overflow icons
                toolbar.navigationIcon?.mutate()?.setTint(parsedTxtColor)
                toolbar.overflowIcon?.mutate()?.setTint(parsedTxtColor)
            } catch (e: Exception) {
                // Ignore parsing errors
            }
        }

        val url = intent.getStringExtra(EXTRA_URL) ?: run {
            finish()
            return
        }
        val userAgent = intent.getStringExtra(EXTRA_USER_AGENT)
        val initialCookie = intent.getStringExtra(EXTRA_INITIAL_COOKIE)
        successFilters = intent.getStringArrayListExtra(EXTRA_SUCCESS_FILTERS) ?: emptyList()
        autoCloseOnCookie = intent.getStringExtra(EXTRA_AUTO_CLOSE_ON_COOKIE)
        ssoRedirectUrl = intent.getStringExtra(EXTRA_SSO_REDIRECT_URL)
        enableAdBlock = intent.getBooleanExtra(EXTRA_ENABLE_AD_BLOCK, false)
        domImageSelectors = intent.getStringArrayListExtra(EXTRA_DOM_IMAGE_SELECTORS) ?: emptyList()
        domImageAttributes = intent.getStringArrayListExtra(EXTRA_DOM_IMAGE_ATTRIBUTES) ?: emptyList()
        domLinkSelectors = intent.getStringArrayListExtra(EXTRA_DOM_LINK_SELECTORS) ?: emptyList()
        captureRequestPatterns = intent.getStringArrayListExtra(EXTRA_CAPTURE_REQUEST_PATTERNS) ?: emptyList()
        allowRequestPatterns = intent.getStringArrayListExtra(EXTRA_ALLOW_REQUEST_PATTERNS) ?: emptyList()
        pageFinishedScript = intent.getStringExtra(EXTRA_PAGE_FINISHED_SCRIPT)
        blockNetworkImages = intent.getBooleanExtra(EXTRA_BLOCK_NETWORK_IMAGES, false)
        sessionTargetHost = intent.getStringExtra(EXTRA_URL)?.let { getDomainFromUrl(it) }

        // Sync Initial Cookies if provided
        val cookieManager = CookieManager.getInstance()
        cookieManager.setAcceptCookie(true)
        cookieManager.setAcceptThirdPartyCookies(webView, true)

        val clearCookies = intent.getBooleanExtra(EXTRA_CLEAR_COOKIES, false)
        if (clearCookies) {
             android.util.Log.i("KuronNative", "🧹 Clearing cookies requested.")
             cookieManager.removeAllCookies(null)
             cookieManager.flush()
        }

        if (initialCookie != null) {
            val domain = getDomainFromUrl(url)
            val cookies = initialCookie.split(";")
            for (cookie in cookies) {
                 cookieManager.setCookie(domain, cookie.trim())
            }
            cookieManager.flush()
        }

        with(webView.settings) {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            this.blockNetworkImage = blockNetworkImages
            if (userAgent != null) {
                userAgentString = userAgent
            } else {
                userAgentString = userAgentString.replace("; wv", "")
            }
        }



        webView.addJavascriptInterface(object : Any() {
            @android.webkit.JavascriptInterface
            fun sendToken(token: String) {
                android.util.Log.d("KuronNative", "Caught token from JS interface (length=${token.length})")
                runOnUiThread {
                    val cookieManager = android.webkit.CookieManager.getInstance()
                    val harvestUrl = webView.url ?: sessionTargetHost
                    val cookiesStr = cookieManager.getCookie(harvestUrl)?.split(";")?.filter { it.isNotBlank() }?.distinct()?.joinToString("; ") ?: ""
                    val cookieList = arrayListOf(cookiesStr)

                    val resultIntent = Intent()
                    resultIntent.putExtra(RESULT_USER_AGENT, webView.settings.userAgentString)
                    resultIntent.putExtra(RESULT_CURRENT_URL, webView.url)
                    resultIntent.putExtra(RESULT_USED_SSL_FALLBACK, usedSslFallback)
                    resultIntent.putExtra("pageFinishedScriptResult", token)
                    resultIntent.putStringArrayListExtra(RESULT_COOKIES, cookieList)
                    setResult(android.app.Activity.RESULT_OK, resultIntent)
                    finish()
                }
            }

            @android.webkit.JavascriptInterface
            fun logNetwork(log: String) {
                android.util.Log.d("KuronNative", "JS Network Log (chars=${log.length})")
            }
        }, "KuronTokenInterface")

        webView.webViewClient = object : WebViewClient() {
            private var pollingStarted = false

            private fun startPolling(view: WebView?) {
                if (pollingStarted) return
                
                val script = pageFinishedScript
                if (!script.isNullOrBlank()) {
                    pollingStarted = true
                    val handler = android.os.Handler(android.os.Looper.getMainLooper())
                    val runnable = object : Runnable {
                        override fun run() {
                            if (isDestroyed || isFinishing) return
                            view?.evaluateJavascript(script) { result ->
                                android.util.Log.d("KuronNative", "evaluateJavascript result: $result")
                                if (result != null && result != "null" && result != "\"\"" && result.isNotBlank()) {
                                    android.util.Log.d("KuronNative", "Clearance found! Closing WebView.")
                                    // Route through finishWithSuccess so the real page's
                                    // HTML is captured to file (RESULT_PAGE_HTML) and
                                    // captured image URLs are returned — the raw
                                    // resultIntent path above omitted both, which left
                                    // preferCapturedHtml with no pageHtml and fell back
                                    // to a Dio verify that fails CF fingerprinting.
                                    pageFinishedScriptResult = result
                                    finishWithSuccess(view?.url ?: sessionTargetHost ?: "")
                                } else {
                                    handler.postDelayed(this, 1000)
                                }
                            }
                        }
                    }
                    handler.postDelayed(runnable, 1000)
                }
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                super.onPageStarted(view, url, favicon)
                // SSO Check on Start
                if (checkSsoRedirect(url)) return
                
                // Inject Network Interceptor to log everything
                val interceptScript = """
                    (function() {
                        if (window.kuronInterceptInjected) return;
                        window.kuronInterceptInjected = true;
                        
                        var originalFetch = window.fetch;
                        window.fetch = function(input, init) {
                            var url = typeof input === 'string' ? input : (input && input.url ? input.url : 'unknown');
                            var headers = (init && init.headers) ? JSON.stringify(init.headers) : 'none';
                            window.KuronTokenInterface.logNetwork('FETCH url: ' + url + ' headers: ' + headers);
                            return originalFetch.apply(this, arguments);
                        };
                        
                        var originalOpen = XMLHttpRequest.prototype.open;
                        XMLHttpRequest.prototype.open = function(method, url) {
                            this._url = url;
                            window.KuronTokenInterface.logNetwork('XHR OPEN url: ' + url);
                            return originalOpen.apply(this, arguments);
                        };
                        
                        var originalSetRequestHeader = XMLHttpRequest.prototype.setRequestHeader;
                        XMLHttpRequest.prototype.setRequestHeader = function(header, value) {
                            window.KuronTokenInterface.logNetwork('XHR HEADER url: ' + this._url + ' header: ' + header + ' value: ' + value);
                            return originalSetRequestHeader.apply(this, arguments);
                        };
                    })();
                """.trimIndent()
                view?.evaluateJavascript(interceptScript, null)

                checkForSuccess(url)
                startPolling(view)
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                // SSO Check on Finish
                if (checkSsoRedirect(url)) return
                
                checkForSuccess(url)
                startPolling(view)
                
                // Update title
                view?.title?.let {
                    supportActionBar?.title = it
                }
                
                // Force sync cookies on page finish
                CookieManager.getInstance().flush()

                // Check for Auto-Close Cookie (Generic)
                if (autoCloseOnCookie != null) {
                    val cookies = CookieManager.getInstance().getCookie(url)
                    if (cookies != null && cookies.contains(autoCloseOnCookie!!)) {
                        // Skip auto-close if the page is still a CF challenge page.
                        // Turnstile sets cf_clearance pre-challenge — closing early
                        // would skip user-interactive challenge solving.
                        val title = view?.title ?: ""
                        val isChallengePage = title.isBlank() ||
                            title.contains("Just a moment", ignoreCase = true) ||
                            title.contains("Attention Required", ignoreCase = true) ||
                            title.contains("security verification", ignoreCase = true) ||
                            url?.contains("challenge-platform") == true
                        if (!isChallengePage) {
                            android.util.Log.i("KuronNative", "✅ Auto-close cookie '$autoCloseOnCookie' detected! Closing WebView.")
                            finishWithSuccess(url ?: "")
                        } else {
                            android.util.Log.i("KuronNative", "⏳ Auto-close cookie '$autoCloseOnCookie' found but page is still a challenge page ('$title'). Waiting for user interaction.")
                        }
                    }
                }
            }

            override fun onReceivedSslError(view: WebView?, handler: SslErrorHandler?, error: SslError?) {
                val primaryError = error?.primaryError ?: "unknown"
                val failingHost = error?.url?.let { getDomainFromUrl(it) }
                android.util.Log.w("KuronNative", "SSL error: type=$primaryError url=${error?.url}")
                if (failingHost == null) {
                    handler?.cancel()
                    return
                }
                val pageHost = view?.url?.let { getDomainFromUrl(it) }
                val allowed = failingHost == sessionTargetHost ||
                    (pageHost != null && registrableDomain(failingHost) == registrableDomain(pageHost))
                if (!allowed) {
                    android.util.Log.w("KuronNative", "SSL error rejected for host $failingHost")
                    handler?.cancel()
                    return
                }
                if (sslConsentHosts.contains(failingHost)) {
                    usedSslFallback = true
                    handler?.proceed()
                    return
                }
                runOnUiThread {
                    androidx.appcompat.app.AlertDialog.Builder(this@WebViewActivity)
                        .setTitle("Untrusted certificate")
                        .setMessage("The site $failingHost presented an untrusted certificate. Continue anyway? (session only)")
                        .setPositiveButton("Continue") { _, _ ->
                            sslConsentHosts.add(failingHost)
                            usedSslFallback = true
                            handler?.proceed()
                        }
                        .setNegativeButton("Cancel") { _, _ -> handler?.cancel() }
                        .setCancelable(false)
                        .show()
                }
            }

            // AdBlock Implementation
            override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): android.webkit.WebResourceResponse? {
                val requestUrl = request?.url?.toString() ?: return super.shouldInterceptRequest(view, request)

                // Sniff for Authorization header (Schale Clearance) — same registrable domain as session target only
                val requestHost = request?.url?.host
                val sessionHost = sessionTargetHost // immutable snapshot (mutable field)
                val sniffAllowed = sessionHost != null &&
                    requestHost != null &&
                    registrableDomain(requestHost) == registrableDomain(sessionHost)
                if (sniffAllowed) {
                    val authHeader = request.requestHeaders?.entries?.firstOrNull { it.key.equals("Authorization", ignoreCase = true) }?.value
                    if (authHeader != null && authHeader.startsWith("Bearer ", ignoreCase = true)) {
                        val token = authHeader.substring(7).trim()
                        if (token.isNotBlank() && token != "null" && token.length > 10) {
                            android.util.Log.d("KuronNative", "Caught token from Authorization header (length=${token.length})")
                            view?.postDelayed({
                                val cookieManager = android.webkit.CookieManager.getInstance()
                                cookieManager.flush()
                                val cookiesStr = cookieManager.getCookie(view.url ?: sessionTargetHost)?.split(";")?.filter { it.isNotBlank() }?.distinct()?.joinToString("; ") ?: ""
                                val cookieList = arrayListOf(cookiesStr)

                                val resultIntent = Intent()
                                resultIntent.putExtra(RESULT_USER_AGENT, view.settings.userAgentString)
                                resultIntent.putExtra(RESULT_CURRENT_URL, view.url)
                                resultIntent.putExtra(RESULT_USED_SSL_FALLBACK, usedSslFallback)
                                resultIntent.putExtra("pageFinishedScriptResult", token)
                                resultIntent.putStringArrayListExtra(RESULT_COOKIES, cookieList)

                                setResult(android.app.Activity.RESULT_OK, resultIntent)
                                finish()
                            }, 1000) // Delay 1 second to ensure cookies are written
                            return super.shouldInterceptRequest(view, request)
                        }
                    }
                }

                if (captureRequestPatterns.any { requestUrl.contains(it) }) {
                    //  MangaFire captures one AJAX URL and exits; HentaiRead
                    // collects many image URLs, so keep the old list behavior unless
                    // the caller explicitly enabled blockNetworkImages capture mode.
                    if (blockNetworkImages) {
                        view?.post {
                            finishWithSuccess(webView.url ?: url, requestUrl)
                        }
                        return emptyResponse()
                    }
                    capturedImageUrls.add(requestUrl)
                    // Don't block – let the image load normally in WebView
                }

                if (captureRequestPatterns.isNotEmpty() &&
                    requestUrl != url &&
                    allowRequestPatterns.none { requestUrl.contains(it) }
                ) {
                    return emptyResponse()
                }

                if (enableAdBlock && request != null) {
                    if (AdBlocker.isAd(requestUrl)) {
                        android.util.Log.d("KuronNative", "🚫 Blocked Ad: $requestUrl")
                        // Return empty response to block
                        return emptyResponse()
                    }
                }
                return super.shouldInterceptRequest(view, request)
            }

            // SSO Redirect Interception
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val url = request?.url?.toString()
                if (checkSsoRedirect(url)) return true
                return super.shouldOverrideUrlLoading(view, request)
            }
        }
        
        // Hotlink-protected players (cossora.stream) reject the request unless
        // the embedder's origin arrives as Referer — the source page that framed
        // the player. Custom Tabs cannot send headers, so this WebView path is
        // the only one that can.
        val referer = intent.getStringExtra(EXTRA_REFERER)
        if (referer.isNullOrBlank()) {
            webView.loadUrl(url)
        } else {
            webView.loadUrl(url, mapOf("Referer" to referer))
        }
    }
    
    private fun getDomainFromUrl(url: String): String {
        return try {
            val uri = android.net.Uri.parse(url)
            uri.host ?: url
        } catch (e: Exception) {
            url
        }
    }

    // Last two labels of a host, e.g. sub.komiktap.info -> komiktap.info.
    // ponytail: naive last-two-labels; co.uk-type multi-label TLDs out of scope
    // per spec (no PublicSuffixDatabase) — add one if such hosts appear.
    private fun registrableDomain(host: String): String {
        val labels = host.split(".")
        return if (labels.size >= 2) {
            labels.takeLast(2).joinToString(".")
        } else {
            host
        }
    }

    private fun checkForSuccess(url: String?) {
        if (url == null) return

        // 1. Check URL patterns if filters provided
        if (successFilters.isNotEmpty()) {
            for (filter in successFilters) {
                if (url.contains(filter)) {
                    finishWithSuccess(url)
                    return
                }
            }
        }
        
        // 2. Fallback or specific logic could go here
        // For Crotpedia, we might just rely on the user closing the activity 
        // OR the flutter side passing specific success URLs (like 'wp-admin').
    }

    private fun checkSsoRedirect(url: String?): Boolean {
        if (url == null || ssoRedirectUrl == null) return false
        
        // Exact match or starts with (for query params)
        if (url.startsWith(ssoRedirectUrl!!)) {
             android.util.Log.i("KuronNative", "🔐 SSO Redirect Captured: $url")
             finishWithSuccess(url)
             return true
        }
        return false
    }

    private fun finishWithSuccess(currentUrl: String, capturedRequestUrl: String? = null) {
        if (hasFinishedResult) {
            return
        }
        hasFinishedResult = true

        val fallbackCurrentUrl = if (currentUrl.isBlank()) webView.url ?: "" else currentUrl

        if (!capturedRequestUrl.isNullOrBlank()) {
            completeWithSuccessResult(
                currentUrl = fallbackCurrentUrl,
                resolvedImageUrl = null,
                capturedRequestUrl = capturedRequestUrl,
            )
            return
        }

        try {
            webView.evaluateJavascript(buildImageExtractionScript()) { rawResult ->
                val extraction = parseImageExtractionResult(rawResult)
                // Capture HTML to file before finishing (avoids OOM in Intent)
                if (capturedPageHtmlPath == null) {
                    try {
                        val htmlFile = java.io.File(cacheDir, "captured_${System.currentTimeMillis()}.html")
                        webView.evaluateJavascript("document.documentElement.outerHTML") { raw ->
                            if (raw != null) {
                                try {
                                    htmlFile.writeText(raw)
                                    capturedPageHtmlPath = htmlFile.absolutePath
                                } catch (_: Exception) { }
                            }
                            completeWithSuccessResult(
                                currentUrl = extraction.currentUrl ?: fallbackCurrentUrl,
                                resolvedImageUrl = extraction.imageUrl,
                                capturedRequestUrl = null,
                            )
                        }
                    } catch (_: Exception) {
                        completeWithSuccessResult(
                            currentUrl = extraction.currentUrl ?: fallbackCurrentUrl,
                            resolvedImageUrl = extraction.imageUrl,
                            capturedRequestUrl = null,
                        )
                    }
                } else {
                    completeWithSuccessResult(
                        currentUrl = extraction.currentUrl ?: fallbackCurrentUrl,
                        resolvedImageUrl = extraction.imageUrl,
                        capturedRequestUrl = null,
                    )
                }
            }
        } catch (_: Exception) {
            completeWithSuccessResult(
                currentUrl = fallbackCurrentUrl,
                resolvedImageUrl = null,
                capturedRequestUrl = null,
            )
        }
    }

    private fun completeWithSuccessResult(currentUrl: String, resolvedImageUrl: String?, capturedRequestUrl: String?) {
        val cookieManager = CookieManager.getInstance()
        cookieManager.flush() // Ensure sync
        
        val cookies = cookieManager.getCookie(currentUrl) // Returns "key=value; key2=value2"
        android.util.Log.d("KuronNative", "WebView Finishing. URL: $currentUrl")
        android.util.Log.d("KuronNative", "Cookies found: ${cookies?.split(";")?.size ?: 0} cookie(s)")
        
        // Helper to get cookies for the base domain too if redirected
        // But getCookie(url) usually gets applicable cookies.
        
        val resultIntent = Intent()
        
        // We return the raw cookie string, let Dart parse it to list if needed
        // Or we can split it here.
        if (cookies != null) {
            val cookieList = ArrayList(cookies.split(";").map { it.trim() })
            resultIntent.putStringArrayListExtra(RESULT_COOKIES, cookieList)
        }
        
        resultIntent.putExtra(RESULT_USER_AGENT, webView.settings.userAgentString)
        resultIntent.putExtra(RESULT_CURRENT_URL, currentUrl)
        resultIntent.putExtra(RESULT_USED_SSL_FALLBACK, usedSslFallback)
        if (pageFinishedScriptResult != null) {
            resultIntent.putExtra("pageFinishedScriptResult", pageFinishedScriptResult)
        }

        // Pass saved HTML file path if available
        if (capturedPageHtmlPath != null) {
            resultIntent.putExtra(RESULT_PAGE_HTML, capturedPageHtmlPath)
        }
        // Pass captured image URLs (from shouldInterceptRequest)
        if (capturedImageUrls.isNotEmpty()) {
            resultIntent.putStringArrayListExtra(
                RESULT_CAPTURED_IMAGE_URLS, ArrayList(capturedImageUrls))
        }

        if (!resolvedImageUrl.isNullOrBlank()) {
            resultIntent.putExtra(RESULT_RESOLVED_IMAGE_URL, resolvedImageUrl)
        }
        if (!capturedRequestUrl.isNullOrBlank()) {
            resultIntent.putExtra(RESULT_CAPTURED_REQUEST_URL, capturedRequestUrl)
        }
        
        setResult(Activity.RESULT_OK, resultIntent)
        finish()
    }

    private fun emptyResponse(): WebResourceResponse {
        return WebResourceResponse(
            "text/plain",
            "utf-8",
            ByteArrayInputStream(ByteArray(0)),
        )
    }

    private fun buildImageExtractionScript(): String {
        val selectorsJson = JSONArray(domImageSelectors).toString()
        val attributesJson = JSONArray(domImageAttributes).toString()
        val linkSelectorsJson = JSONArray(domLinkSelectors).toString()

        return """
            (function() {
              const imageSelectors = $selectorsJson;
              const imageAttributes = $attributesJson;
              const linkSelectors = $linkSelectorsJson;
              const toAbsolute = (value) => {
                if (!value) return '';
                try {
                  return new URL(value, window.location.href).toString();
                } catch (_) {
                  return value;
                }
              };
              const firstSrcSet = (value) => {
                if (!value) return '';
                const first = value.split(',')[0] || '';
                return first.trim().split(' ')[0] || '';
              };
              const nearestAnchorHref = (node) => {
                let current = node;
                while (current) {
                  if ((current.tagName || '').toLowerCase() === 'a') {
                    const href = current.getAttribute('href');
                    if (href) return toAbsolute(href.trim());
                  }
                  current = current.parentElement;
                }
                return '';
              };
              const extractFromNode = (node) => {
                if (!node) return '';
                const candidates = [node];
                if (typeof node.querySelectorAll === 'function') {
                  node.querySelectorAll('img').forEach((img) => candidates.push(img));
                }
                for (const candidate of candidates) {
                  if (!candidate || typeof candidate.getAttribute !== 'function') continue;
                  for (const attr of imageAttributes) {
                    const value = candidate.getAttribute(attr);
                    if (value) return toAbsolute(value.trim());
                  }
                  const srcSet = firstSrcSet(candidate.getAttribute('srcset'));
                  if (srcSet) return toAbsolute(srcSet);
                  const wrappedLink = nearestAnchorHref(candidate);
                  if (wrappedLink) return wrappedLink;
                }
                const directHref = typeof node.getAttribute === 'function' ? node.getAttribute('href') : '';
                if (directHref) return toAbsolute(directHref.trim());
                const nestedLink = typeof node.querySelector === 'function' ? node.querySelector('a[href]') : null;
                const nestedHref = nestedLink && typeof nestedLink.getAttribute === 'function'
                  ? nestedLink.getAttribute('href')
                  : '';
                if (nestedHref) return toAbsolute(nestedHref.trim());
                return '';
              };

              let imageUrl = '';
              for (const selector of imageSelectors) {
                try {
                  const node = document.querySelector(selector);
                  imageUrl = extractFromNode(node);
                  if (imageUrl) break;
                } catch (_) {}
              }

              if (!imageUrl) {
                for (const selector of linkSelectors) {
                  try {
                    const node = document.querySelector(selector);
                    const href = node && typeof node.getAttribute === 'function'
                      ? node.getAttribute('href')
                      : '';
                    if (href) {
                      imageUrl = toAbsolute(href.trim());
                      break;
                    }
                  } catch (_) {}
                }
              }

              return {
                currentUrl: window.location.href || '',
                imageUrl: imageUrl || '',
              };
            })();
        """.trimIndent()
    }

    private fun parseImageExtractionResult(rawResult: String?): ImageExtractionResult {
        if (rawResult.isNullOrBlank() || rawResult == "null") {
            return ImageExtractionResult()
        }

        return try {
            val normalized = if (rawResult.startsWith("\"")) {
                JSONObject("""{"value":$rawResult}""").optString("value")
            } else {
                rawResult
            }
            val json = JSONObject(normalized)
            ImageExtractionResult(
                currentUrl = json.optString("currentUrl").takeIf { it.isNotBlank() },
                imageUrl = json.optString("imageUrl").takeIf { it.isNotBlank() },
            )
        } catch (_: Exception) {
            ImageExtractionResult()
        }
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        if (item.itemId == android.R.id.home) {
            // Check for cookies even on manual close, 
            // incase user logged in but didn't trigger a specific URL filter
            finishWithSuccess(webView.url ?: "")
            return true
        }
        return super.onOptionsItemSelected(item)
    }
    
    override fun onBackPressed() {
        if (webView.canGoBack()) {
            webView.goBack()
        } else {
            // Return validation on back press too
            finishWithSuccess(webView.url ?: "")
        }
    }

    override fun onDestroy() {
        webView.removeAllViews()
        webView.destroy()
        super.onDestroy()
    }

    private data class ImageExtractionResult(
        val currentUrl: String? = null,
        val imageUrl: String? = null,
    )
}
