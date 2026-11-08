package id.nhasix.kuron_native.kuron_native

import java.io.File
import java.io.RandomAccessFile
import java.net.ConnectException
import java.net.UnknownHostException
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * Runtime downloader for the ONNX bubble-detection model.
 *
 * The model is NOT an APK asset (change `onnx-runtime-download`): it lives at
 * `modelsDir/<fileName>` with resume state in `<fileName>.part`. Blocking API —
 * callers thread it (see plugin: `networkExecutor`). Pure-JVM core (no Android
 * framework types) so it unit-tests with a plain JDK HTTP server.
 */
class OnnxModelManager(
    private val modelsDir: File,
    private val client: OkHttpClient = OkHttpClient.Builder().build(),
    val fileName: String = BubbleDetector.MODEL_FILE_NAME,
) {
    companion object {
        const val STATE_NOT_DOWNLOADED = "not_downloaded"
        const val STATE_DOWNLOADING = "downloading"
        const val STATE_READY = "ready"
        const val STATE_ERROR = "error"

        const val ERROR_OFFLINE = "offline"
        const val ERROR_STORAGE_FULL = "storage_full"
        const val ERROR_HTTP = "http_error"
        const val ERROR_CHECKSUM = "checksum_mismatch"
        const val ERROR_CANCELLED = "cancelled"
    }

    @Volatile var state: String = STATE_NOT_DOWNLOADED
        private set
    @Volatile var bytesReceived: Long = 0L
        private set
    @Volatile var totalBytes: Long? = null
        private set
    @Volatile var lastErrorCode: String? = null
        private set
    @Volatile var lastErrorMessage: String? = null
        private set

    private val cancelled = AtomicBoolean(false)

    fun finalFile(): File = File(modelsDir, fileName)
    private fun partFile(): File = File(modelsDir, "$fileName.part")

    /** @return map consumed directly as the `getModelStatus` channel payload. */
    fun status(version: String?): Map<String, Any?> {
        val file = finalFile()
        val ready = file.exists() && file.length() > 0
        if (ready && state != STATE_DOWNLOADING) state = STATE_READY
        if (!ready && state == STATE_READY) state = STATE_NOT_DOWNLOADED
        return mapOf(
            "state" to if (state == STATE_DOWNLOADING) STATE_DOWNLOADING else if (ready) STATE_READY else state,
            "bytesReceived" to if (state == STATE_DOWNLOADING) bytesReceived else if (ready) file.length() else 0L,
            "totalBytes" to (if (state == STATE_DOWNLOADING) totalBytes else if (ready) file.length() else null),
            "version" to version,
            "sizeBytes" to if (ready) file.length() else null,
            "fileName" to fileName,
            "errorCode" to lastErrorCode,
            "errorMessage" to lastErrorMessage,
        )
    }

    /**
     * Download [url] with resume, verify SHA256, atomically promote `.part`.
     * Blocking. Returns null on success or an error code on failure.
     */
    fun startDownload(
        url: String,
        expectedSha256: String,
        onProgress: ((received: Long, total: Long?) -> Unit)? = null,
    ): String? {
        cancelled.set(false)
        state = STATE_DOWNLOADING
        lastErrorCode = null
        lastErrorMessage = null
        modelsDir.mkdirs()
        val part = partFile()
        val resumeFrom = if (part.exists()) part.length() else 0L
        bytesReceived = resumeFrom
        totalBytes = null

        try {
            val request = Request.Builder().url(url).apply {
                if (resumeFrom > 0) header("Range", "bytes=$resumeFrom-")
            }.build()
            client.newCall(request).execute().use { response ->
                if (resumeFrom > 0 && response.code != 206) {
                    // Server ignored resume: restart from scratch.
                    part.delete()
                    bytesReceived = 0L
                    if (response.code != 200) return fail(ERROR_HTTP, "HTTP ${response.code}")
                    writeBody(response, append = false, onProgress)?.let { return it }
                } else {
                    if (response.code != 200 && response.code != 206) {
                        return fail(ERROR_HTTP, "HTTP ${response.code}")
                    }
                    val total = response.header("Content-Range")
                        ?.substringAfterLast("/")
                        ?.toLongOrNull()
                        ?: response.body?.contentLength()?.takeIf { it >= 0 }
                            ?.let { if (response.code == 206) it + bytesReceived else it }
                    totalBytes = total
                    writeBody(response, append = response.code == 206, onProgress)?.let { return it }
                }
            }
            if (cancelled.get()) return fail(ERROR_CANCELLED, "Download cancelled", deletePart = true)

            val digest = MessageDigest.getInstance("SHA-256")
            part.inputStream().use { input ->
                val buf = ByteArray(256 * 1024)
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    digest.update(buf, 0, n)
                }
            }
            val actual = digest.digest().joinToString("") { "%02x".format(it) }
            if (!actual.equals(expectedSha256, ignoreCase = true)) {
                return fail(ERROR_CHECKSUM, "SHA256 mismatch (expected ${expectedSha256.take(12)}…, got ${actual.take(12)}…)", deletePart = true)
            }
            if (!part.renameTo(finalFile())) {
                finalFile().delete()
                if (!part.renameTo(finalFile())) {
                    return fail(ERROR_STORAGE_FULL, "Could not promote model file", deletePart = true)
                }
            }
            state = STATE_READY
            lastErrorCode = null
            return null
        } catch (e: UnknownHostException) {
            return fail(ERROR_OFFLINE, "No network: ${e.message}")
        } catch (e: ConnectException) {
            return fail(ERROR_OFFLINE, "Cannot reach server: ${e.message}")
        } catch (e: java.io.IOException) {
            if (cancelled.get()) return fail(ERROR_CANCELLED, "Download cancelled", deletePart = true)
            val msg = e.message.orEmpty()
            return if (msg.contains("no space", ignoreCase = true) || msg.contains("ENOSPC")) {
                fail(ERROR_STORAGE_FULL, "Storage full: $msg", deletePart = true)
            } else {
                fail(ERROR_HTTP, "IO error: $msg")
            }
        } catch (e: Exception) {
            return fail(ERROR_HTTP, "Download failed: ${e.message}")
        }
    }

    private fun writeBody(
        response: okhttp3.Response,
        append: Boolean,
        onProgress: ((received: Long, total: Long?) -> Unit)?,
    ): String? {
        val body = response.body ?: return fail(ERROR_HTTP, "Empty response body")
        try {
            RandomAccessFile(partFile(), "rw").use { raf ->
                if (append) raf.seek(raf.length()) else raf.setLength(0)
                if (!append) bytesReceived = 0L
                val buf = ByteArray(256 * 1024)
                body.byteStream().use { input ->
                    while (true) {
                        if (cancelled.get()) return null
                        val n = input.read(buf)
                        if (n < 0) break
                        raf.write(buf, 0, n)
                        bytesReceived += n
                        onProgress?.invoke(bytesReceived, totalBytes)
                    }
                }
            }
            return null
        } catch (e: java.io.IOException) {
            val msg = e.message.orEmpty()
            return if (msg.contains("no space", ignoreCase = true) || msg.contains("ENOSPC")) {
                fail(ERROR_STORAGE_FULL, "Storage full: $msg", deletePart = true)
            } else {
                fail(ERROR_HTTP, "IO error: $msg")
            }
        }
    }

    private fun fail(code: String, message: String, deletePart: Boolean = false): String? {
        if (deletePart) partFile().delete()
        state = if (code == ERROR_CANCELLED && finalFile().exists()) STATE_READY else if (code == ERROR_CANCELLED) STATE_NOT_DOWNLOADED else STATE_ERROR
        lastErrorCode = if (code == ERROR_CANCELLED) null else code
        lastErrorMessage = if (code == ERROR_CANCELLED) null else message
        if (code == ERROR_CANCELLED) {
            bytesReceived = 0L
            totalBytes = null
        }
        return code
    }

    fun cancel() {
        cancelled.set(true)
        client.dispatcher.cancelAll()
    }

    /** @return true when a model file was removed. */
    fun delete(): Boolean {
        cancel()
        partFile().delete()
        val removed = finalFile().delete()
        if (removed) {
            state = STATE_NOT_DOWNLOADED
            lastErrorCode = null
            lastErrorMessage = null
            bytesReceived = 0L
            totalBytes = null
        }
        return removed
    }
}
