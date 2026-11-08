package id.nhasix.kuron_native.kuron_native

import java.io.File
import java.net.ServerSocket
import java.net.Socket
import java.nio.file.Files
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import okhttp3.OkHttpClient

internal class OnnxModelManagerTest {

    private fun sha256Hex(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString("") { "%02x".format(it) }
    }

    /**
     * Minimal HTTP/1.1 server on a raw ServerSocket (no extra test deps):
     * serves [payload] with basic `Range` support and records Range headers.
     */
    private class FakeModelServer(
        val payload: ByteArray,
        val chunkDelayMs: Long = 0,
    ) {
        val seenRanges = mutableListOf<String?>()
        private val server = ServerSocket(0)
        val port: Int = server.localPort

        init {
            val acceptThread = Thread {
                while (!server.isClosed) {
                    try {
                        val socket = server.accept()
                        Thread({ handle(socket) }, "fake-model-conn").start()
                    } catch (_: Exception) {
                        break
                    }
                }
            }
            acceptThread.isDaemon = true
            acceptThread.start()
        }

        private fun handle(socket: Socket) {
            socket.use { s ->
                val reader = s.getInputStream().bufferedReader()
                reader.readLine() ?: return // request line
                var range: String? = null
                while (true) {
                    val line = reader.readLine() ?: break
                    if (line.isEmpty()) break
                    if (line.startsWith("Range:", ignoreCase = true)) {
                        range = line.substringAfter(":").trim()
                    }
                }
                synchronized(seenRanges) { seenRanges.add(range) }
                val (start, status) = if (range != null && range.startsWith("bytes=")) {
                    val parsed = range.removePrefix("bytes=").substringBefore("-").toLongOrNull() ?: 0L
                    parsed to 206
                } else {
                    0L to 200
                }
                val from = start.toInt().coerceIn(0, payload.size)
                val out = s.getOutputStream()
                val head = buildString {
                    append("HTTP/1.1 $status ${if (status == 206) "Partial Content" else "OK"}\r\n")
                    append("Content-Type: application/octet-stream\r\n")
                    append("Content-Length: ${payload.size - from}\r\n")
                    if (status == 206) {
                        append("Content-Range: bytes $from-${payload.size - 1}/${payload.size}\r\n")
                    }
                    append("Connection: close\r\n\r\n")
                }
                out.write(head.toByteArray())
                var offset = from
                while (offset < payload.size) {
                    val end = minOf(offset + 65536, payload.size)
                    out.write(payload, offset, end - offset)
                    out.flush()
                    offset = end
                    if (chunkDelayMs > 0) Thread.sleep(chunkDelayMs)
                }
                out.flush()
            }
        }

        fun url(): String = "http://127.0.0.1:$port/model.onnx"

        fun stop() = runCatching { server.close() }
    }

    private fun tempDir(): File = Files.createTempDirectory("onnx-test").toFile()

    @Test
    fun freshDownload_verifiesShaAndPromotesAtomically() {
        val payload = ByteArray(300 * 1024) { (it % 251).toByte() }
        val server = FakeModelServer(payload)
        try {
            val dir = tempDir()
            val manager = OnnxModelManager(dir, OkHttpClient())
            var lastProgress = -1L
            val error = manager.startDownload(server.url(), sha256Hex(payload)) { received, total ->
                lastProgress = received
                assertEquals(payload.size.toLong(), total)
            }
            assertNull(error, "download should succeed")
            assertEquals(OnnxModelManager.STATE_READY, manager.state)
            assertTrue(manager.finalFile().exists())
            assertFalse(File(dir, "bubble_detector.onnx.part").exists())
            assertTrue(manager.finalFile().readBytes().contentEquals(payload))
            assertTrue(lastProgress > 0)
            val status = manager.status("1")
            assertEquals(OnnxModelManager.STATE_READY, status["state"])
            assertEquals(payload.size.toLong(), status["sizeBytes"])
        } finally {
            server.stop()
        }
    }

    @Test
    fun resume_continuesFromPartWithRangeHeader() {
        val payload = ByteArray(200 * 1024) { (it % 251).toByte() }
        val server = FakeModelServer(payload)
        try {
            val dir = tempDir()
            File(dir, "bubble_detector.onnx.part").writeBytes(payload.copyOfRange(0, 100 * 1024))
            val manager = OnnxModelManager(dir, OkHttpClient())
            val error = manager.startDownload(server.url(), sha256Hex(payload))
            assertNull(error, "resumed download should succeed")
            assertTrue(manager.finalFile().readBytes().contentEquals(payload))
            assertTrue(
                server.seenRanges.any { it == "bytes=102400-" },
                "expected Range resume, saw ${server.seenRanges}",
            )
        } finally {
            server.stop()
        }
    }

    @Test
    fun checksumMismatch_deletesPartAndReportsError() {
        val payload = ByteArray(64 * 1024) { (it % 251).toByte() }
        val server = FakeModelServer(payload)
        try {
            val dir = tempDir()
            val manager = OnnxModelManager(dir, OkHttpClient())
            val error = manager.startDownload(server.url(), "0".repeat(64))
            assertEquals(OnnxModelManager.ERROR_CHECKSUM, error)
            assertEquals(OnnxModelManager.STATE_ERROR, manager.state)
            assertFalse(manager.finalFile().exists())
            assertFalse(File(dir, "bubble_detector.onnx.part").exists())
            assertEquals(OnnxModelManager.ERROR_CHECKSUM, manager.status("1")["errorCode"])
        } finally {
            server.stop()
        }
    }

    @Test
    fun cancel_removesPartAndResetsState() {
        val payload = ByteArray(5 * 1024 * 1024) { (it % 251).toByte() }
        val server = FakeModelServer(payload, chunkDelayMs = 50)
        try {
            val dir = tempDir()
            val manager = OnnxModelManager(dir, OkHttpClient())
            val done = CountDownLatch(1)
            val result = AtomicReference<String?>("unfinished")
            Thread {
                result.set(manager.startDownload(server.url(), sha256Hex(payload)))
                done.countDown()
            }.start()
            Thread.sleep(400)
            manager.cancel()
            assertTrue(done.await(10, TimeUnit.SECONDS), "download thread should finish after cancel")
            assertFalse(File(dir, "bubble_detector.onnx.part").exists())
            assertFalse(manager.finalFile().exists())
            assertNotNull(result.get(), "cancelled download must not report success")
        } finally {
            server.stop()
        }
    }

    @Test
    fun unreachableHost_reportsErrorHonestly() {
        val dir = tempDir()
        val manager = OnnxModelManager(
            dir,
            OkHttpClient.Builder().connectTimeout(2, TimeUnit.SECONDS).build(),
        )
        // Nothing listens on this port (connection refused).
        val error = manager.startDownload("http://127.0.0.1:1/model.onnx", "abc")
        // Refused localhost surfaces as offline or a generic honest error —
        // both are non-crash outcomes surfaced to the UI.
        assertNotNull(error)
        assertFalse(manager.finalFile().exists())
    }
}
