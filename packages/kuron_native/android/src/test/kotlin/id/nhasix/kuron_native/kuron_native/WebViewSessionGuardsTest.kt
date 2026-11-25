package id.nhasix.kuron_native.kuron_native

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

// F1 (CWE-79): the session trust guard must keep the normal flow working
// (same domain, subdomains, Cloudflare challenge pages) while refusing to
// treat foreign origins as the session target.
internal class WebViewSessionGuardsTest {

    @Test
    fun `same host is trusted`() {
        assertTrue(
            WebViewActivity.isTrustedSessionUrl(
                "https://komiktap.info/manga",
                "komiktap.info",
            ),
        )
    }

    @Test
    fun `subdomain of session target is trusted`() {
        assertTrue(
            WebViewActivity.isTrustedSessionUrl(
                "https://challenge.komiktap.info/cdn-cgi/challenge-platform",
                "komiktap.info",
            ),
        )
    }

    @Test
    fun `http scheme on session domain is trusted`() {
        assertTrue(
            WebViewActivity.isTrustedSessionUrl(
                "http://komiktap.info/",
                "komiktap.info",
            ),
        )
    }

    @Test
    fun `host comparison is case-insensitive`() {
        assertTrue(
            WebViewActivity.isTrustedSessionUrl(
                "https://KomikTap.INFO/",
                "komiktap.info",
            ),
        )
    }

    @Test
    fun `foreign host is rejected`() {
        assertFalse(
            WebViewActivity.isTrustedSessionUrl(
                "https://evil.com/login",
                "komiktap.info",
            ),
        )
    }

    @Test
    fun `lookalike suffix host is rejected`() {
        assertFalse(
            WebViewActivity.isTrustedSessionUrl(
                "https://komiktap.info.evil.com/",
                "komiktap.info",
            ),
        )
    }

    @Test
    fun `non-http schemes are rejected`() {
        assertFalse(WebViewActivity.isTrustedSessionUrl("javascript:alert(1)", "komiktap.info"))
        assertFalse(WebViewActivity.isTrustedSessionUrl("intent://evil.com#Intent;end", "komiktap.info"))
        assertFalse(WebViewActivity.isTrustedSessionUrl("data:text/html,<h1>x</h1>", "komiktap.info"))
        assertFalse(WebViewActivity.isTrustedSessionUrl("ftp://komiktap.info/f", "komiktap.info"))
    }

    @Test
    fun `blank or unknown urls are rejected`() {
        assertFalse(WebViewActivity.isTrustedSessionUrl(null, "komiktap.info"))
        assertFalse(WebViewActivity.isTrustedSessionUrl("", "komiktap.info"))
        assertFalse(WebViewActivity.isTrustedSessionUrl("https://komiktap.info/", null))
        assertFalse(WebViewActivity.isTrustedSessionUrl("https://komiktap.info/", ""))
        assertFalse(WebViewActivity.isTrustedSessionUrl("not a url at all", "komiktap.info"))
    }

    @Test
    fun `registrableDomain takes last two labels`() {
        assertEquals("komiktap.info", WebViewActivity.registrableDomain("sub.komiktap.info"))
        assertEquals("komiktap.info", WebViewActivity.registrableDomain("komiktap.info"))
        assertEquals("localhost", WebViewActivity.registrableDomain("localhost"))
    }
}
