package id.nhasix.kuron_native.kuron_native
import android.widget.FrameLayout

import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.Toolbar
import androidx.browser.customtabs.CustomTabsIntent
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat

/**
 * Plays a chapter's video page inside the app.
 *
 * Two reasons this exists instead of a Custom Tab: Custom Tabs carry no request
 * headers, and hotlink-protected players (cossora.stream) answer
 * `{"error":true}` unless the request carries the embedder's origin as
 * `Referer`; and a Custom Tab hands the user a browser chrome with the page's
 * own URL as the title, for a page the app already knows the name of.
 *
 * Deliberately NOT [WebViewActivity]: that one drives login and CAPTCHA flows —
 * it gives the loaded page a JavaScript bridge, harvests cookies into a result
 * intent, and watches for success filters and auto-close cookies. None of that
 * belongs around a third-party video page.
 *
 * The chrome stays plain on purpose: black, one stock toolbar, the chapter title
 * pinned (an embed page titles itself with its own URL), and a two-item menu.
 */
class VideoPlayerActivity : AppCompatActivity() {

    companion object {
        const val EXTRA_URL = "extra_url"
        const val EXTRA_REFERER = "extra_referer"

        /** Title to show. Pinned: the page's own `<title>` never replaces it. */
        const val EXTRA_TITLE = "extra_title"

        /**
         * Menu labels, passed in already localized. The plugin ships no
         * per-locale strings resources for the app's three locales, so the
         * caller owns the wording.
         *
         * "Open in browser" is only offered when the caller sends this label,
         * because a browser cannot send `Referer` either: for a protected host
         * the button would reproduce the error the player activity exists to
         * avoid.
         */
        const val EXTRA_OPEN_IN_BROWSER_LABEL = "extra_open_in_browser_label"
        const val EXTRA_COPY_LINK_LABEL = "extra_copy_link_label"

        const val MENU_OPEN_IN_BROWSER = 1
        const val MENU_COPY_LINK = 2
    }

    private lateinit var webView: WebView
    private var customView: View? = null
    private var customViewCallback: WebChromeClient.CustomViewCallback? = null
    // System-bar padding, remembered so fullscreen can drop it and leaving
    // fullscreen can put it back without waiting for another inset pass.
    private val barPadding = intArrayOf(0, 0, 0, 0)

    private val pageUrl: String by lazy { intent.getStringExtra(EXTRA_URL).orEmpty() }
    private val referer: String? by lazy { intent.getStringExtra(EXTRA_REFERER) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)

        if (pageUrl.isBlank()) {
            finish()
            return
        }

        val root = android.widget.FrameLayout(this).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            setBackgroundColor(Color.BLACK)
        }
        ViewCompat.setOnApplyWindowInsetsListener(root) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            barPadding[0] = bars.left; barPadding[1] = bars.top
            barPadding[2] = bars.right; barPadding[3] = bars.bottom
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            WindowInsetsCompat.CONSUMED
        }

        // Order matters: a FrameLayout draws children in the order they were
        // added, and the WebView is opaque and full-screen, so the toolbar has
        // to be added last or it sits underneath and is never seen.
        webView = WebView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            setBackgroundColor(Color.BLACK)
        }
        root.addView(webView)

        val toolbar = Toolbar(this).apply {
            setBackgroundColor(Color.BLACK)
            setTitleTextColor(Color.WHITE)
            title = intent.getStringExtra(EXTRA_TITLE).orEmpty()
        }
        root.addView(
            toolbar,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )
        setContentView(root)
        // After setContentView: AppCompat binds the action bar to the toolbar
        // once it is in the hierarchy, which is the order it documents.
        setSupportActionBar(toolbar)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)

        // Third-party cookies stay on: hosts that gate the media segments behind
        // the embed's own cookies would otherwise stall on a blank player.
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)

        @SuppressLint("SetJavaScriptEnabled")
        with(webView.settings) {
            javaScriptEnabled = true
            domStorageEnabled = true
            userAgentString = userAgentString.replace("; wv", "")
        }
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?,
            ): Boolean {
                val target = request?.url ?: return false
                // Keep http(s) inside the player; hand anything else (tel:,
                // mailto:, intent:) to the system.
                if (target.scheme == "http" || target.scheme == "https") return false
                return try {
                    startActivity(Intent(Intent.ACTION_VIEW, target))
                    true
                } catch (_: Exception) {
                    true
                }
            }
        }
        webView.webChromeClient = object : WebChromeClient() {
            // HTML5 fullscreen arrives here rather than through the layout.
            override fun onShowCustomView(view: View?, callback: CustomViewCallback?) {
                if (customView != null) {
                    callback?.onCustomViewHidden()
                    return
                }
                customView = view
                customViewCallback = callback
                webView.visibility = View.GONE
                // The inset padding belongs to the chrome, not to the video:
                // keeping it would letterbox fullscreen against the status bar.
                root.setPadding(0, 0, 0, 0)
                if (view != null) {
                    root.addView(
                        view,
                        FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT,
                        ),
                    )
                    view.systemUiVisibility = (
                        View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                            or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                            or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                            or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                            or View.SYSTEM_UI_FLAG_FULLSCREEN
                            or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                        )
                }
            }

            override fun onHideCustomView() {
                customViewCallback?.onCustomViewHidden()
                customViewCallback = null
                customView?.let { root.removeView(it) }
                root.setPadding(barPadding[0], barPadding[1], barPadding[2], barPadding[3])
                customView = null
                webView.visibility = View.VISIBLE
                webView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE
            }
        }

        if (referer.isNullOrBlank()) {
            webView.loadUrl(pageUrl)
        } else {
            webView.loadUrl(pageUrl, mapOf("Referer" to referer!!))
        }
    }

    override fun onCreateOptionsMenu(menu: android.view.Menu): Boolean {
        // No label, no item: an unlabelled row in the overflow is worse than
        // the action being absent. The app passes both labels from l10n.
        intent.getStringExtra(EXTRA_OPEN_IN_BROWSER_LABEL)?.let {
            menu.add(0, MENU_OPEN_IN_BROWSER, 0, it)
        }
        intent.getStringExtra(EXTRA_COPY_LINK_LABEL)?.let {
            menu.add(0, MENU_COPY_LINK, 1, it)
        }
        return true
    }

    override fun onOptionsItemSelected(item: android.view.MenuItem): Boolean {
        return when (item.itemId) {
            android.R.id.home -> {
                finish()
                true
            }
            MENU_COPY_LINK -> {
                val clip = ClipData.newPlainText("link", webView.url ?: pageUrl)
                (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
                    .setPrimaryClip(clip)
                true
            }
            MENU_OPEN_IN_BROWSER -> {
                val target = webView.url ?: pageUrl
                try {
                    val customTabs = CustomTabsIntent.Builder().build()
                    customTabs.intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    customTabs.launchUrl(this, Uri.parse(target))
                } catch (_: Exception) {
                    // No browser to hand it to; staying put beats crashing.
                }
                true
            }
            else -> super.onOptionsItemSelected(item)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (customView != null) {
            webView.webChromeClient?.onHideCustomView()
            return
        }
        if (webView.canGoBack()) {
            webView.goBack()
            return
        }
        @Suppress("DEPRECATION")
        super.onBackPressed()
    }

    override fun onDestroy() {
        if (customView != null) {
            webView.webChromeClient?.onHideCustomView()
        }
        webView.stopLoading()
        webView.destroy()
        super.onDestroy()
    }
}
