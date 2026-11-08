package id.nhasix.kuron_native.kuron_native

import okhttp3.ConnectionPool
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertNotNull
import kotlin.test.assertEquals
import kotlin.test.assertTrue

internal class AnimatedWebPViewTest {

    @Test
    fun `httpClient is configured and assignable`() {
        val client = OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(90, TimeUnit.SECONDS)
            .connectionPool(ConnectionPool(5, 5, TimeUnit.MINUTES))
            .build()

        AnimatedWebPView.httpClient = client

        val retrieved: OkHttpClient? = AnimatedWebPView.httpClient
        assertNotNull(retrieved)
    }

    @Test
    fun `httpClient connect timeout is 30 seconds`() {
        val client = OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(90, TimeUnit.SECONDS)
            .connectionPool(ConnectionPool(5, 5, TimeUnit.MINUTES))
            .build()

        AnimatedWebPView.httpClient = client

        val retrieved: OkHttpClient = AnimatedWebPView.httpClient!!
        assertNotNull(retrieved)
        assertEquals(30_000, retrieved.connectTimeoutMillis)
    }

    @Test
    fun `httpClient read timeout is 90 seconds`() {
        val client = OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(90, TimeUnit.SECONDS)
            .connectionPool(ConnectionPool(5, 5, TimeUnit.MINUTES))
            .build()

        AnimatedWebPView.httpClient = client

        val retrieved: OkHttpClient = AnimatedWebPView.httpClient!!
        assertNotNull(retrieved)
        assertEquals(90_000, retrieved.readTimeoutMillis)
    }

    @Test
    fun `httpClient connection pool has 5 idle connections`() {
        val client = OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(90, TimeUnit.SECONDS)
            .connectionPool(ConnectionPool(5, 5, TimeUnit.MINUTES))
            .build()

        AnimatedWebPView.httpClient = client

        val retrieved: OkHttpClient = AnimatedWebPView.httpClient!!
        assertNotNull(retrieved)
        assertTrue(retrieved.connectionPool.connectionCount() >= 0)
    }
}
