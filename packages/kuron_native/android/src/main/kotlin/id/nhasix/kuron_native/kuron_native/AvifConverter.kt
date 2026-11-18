package id.nhasix.kuron_native.kuron_native

import android.util.Log
import com.antonkarpenko.ffmpegkit.FFmpegKit
import com.antonkarpenko.ffmpegkit.FFmpegSession
import com.antonkarpenko.ffmpegkit.FFprobeKit
import com.antonkarpenko.ffmpegkit.ReturnCode
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class AvifConverter {
    companion object {
        private const val TAG = "AvifConverter"
        @Volatile
        private var ffmpegRuntimeBroken = false
    }

    // In-flight async sessions by output path. Written on the conversion
    // thread, cancelled from the platform thread — hence concurrent maps.
    private val activeSessions = ConcurrentHashMap<String, FFmpegSession>()
    private val cancelRequested = ConcurrentHashMap.newKeySet<String>()
    // Bumped by cancelAllConverts. Tasks queued on conversionExecutor capture
    // the epoch at submit; a stale task exits before doing any ffmpeg work.
    @Volatile
    var convertEpoch = 0L
        private set

    fun convert(
        inputPath: String,
        quality: Int,
        outputPath: String,
        onProgress: ((Float) -> Unit)? = null,
    ): String? {
        val inputFile = File(inputPath)
        if (!inputFile.exists() || !inputFile.isFile || inputFile.length() <= 0L) {
            Log.w(TAG, "Invalid AVIF input: $inputPath")
            return null
        }

        val outputFile = File(outputPath)
        outputFile.parentFile?.mkdirs()

        if (outputFile.exists() && outputFile.isFile && outputFile.length() > 0L) {
            // A killed/interrupted run leaves a truncated WebP behind; serving
            // it renders intact top rows + garbage stripes below, forever.
            // Only reuse when the RIFF size matches the actual file length.
            if (isCompleteWebP(outputFile)) {
                return outputFile.absolutePath
            }
            Log.w(TAG, "Cached WebP incomplete, reconverting: $outputPath")
            outputFile.delete()
        }
        val clampedQuality = quality.coerceIn(0, 100)
        // back to the synchronous path with no progress events.
        val durationMs = if (onProgress != null) probeDurationMs(inputPath) else null
        if (onProgress != null && durationMs != null && durationMs > 0) {
            if (executeAsyncCommand(
                    buildCommand(
                        inputPath = inputPath,
                        quality = clampedQuality,
                        outputPath = outputPath,
                        includeAnimatedStreamMap = true,
                    ),
                    outputFile = outputFile,
                    durationMs = durationMs,
                    onProgress = onProgress,
                )
            ) {
                onProgress(1f)
                return outputFile.absolutePath
            }
            outputFile.delete()
            if (cancelRequested.remove(outputPath)) {
                // Reader went away mid-conversion: report a miss instead of
                // burning another ~30s in the synchronous fallback for nobody.
                Log.i(TAG, "Conversion cancelled, skipping fallback: $outputPath")
                return null
            }
        }

        val primaryCommand = buildCommand(
            inputPath = inputPath,
            quality = clampedQuality,
            outputPath = outputPath,
            includeAnimatedStreamMap = true,
        )

        if (executeCommand(primaryCommand, outputFile)) {
            return outputFile.absolutePath
        }

        // Retry without explicit stream map when AVIF does not expose stream #1.
        outputFile.delete()
        val fallbackCommand = buildCommand(
            inputPath = inputPath,
            quality = clampedQuality,
            outputPath = outputPath,
            includeAnimatedStreamMap = false,
        )

        return if (executeCommand(fallbackCommand, outputFile)) {
            outputFile.absolutePath
        } else {
            null
        }
    }
    // Best-effort cancel of one in-flight conversion. Safe to call from any
    // thread (the platform thread never blocks behind conversionExecutor).
    // The flag is only set when a session is actually running, so a late
    // cancel can never poison the *next* convert of the same path.
    fun cancelConvert(outputPath: String) {
        val session = activeSessions.remove(outputPath) ?: return
        cancelRequested.add(outputPath)
        Log.i(TAG, "Cancelling in-flight conversion: $outputPath")
        FFmpegKit.cancel(session.sessionId)
    }

    fun cancelAllConverts() {
        // Snapshot: cancelConvert mutates the map.
        convertEpoch++
        val paths = activeSessions.keys.toList()
        if (paths.isNotEmpty()) {
            Log.i(TAG, "Cancelling ${paths.size} in-flight conversion(s)")
        }
        paths.forEach(::cancelConvert)
    }


    private fun probeDurationMs(inputPath: String): Long? {
        return try {
            val session = FFprobeKit.getMediaInformation(inputPath)
            if (!ReturnCode.isSuccess(session.returnCode)) return null
            val seconds =
                session.mediaInformation?.duration?.toString()?.toDoubleOrNull()
                    ?: return null
            if (seconds > 0) (seconds * 1000).toLong() else null
        } catch (t: Throwable) {
            Log.w(TAG, "Probe failed for progress: ${t.message}")
            null
        }
    }

    private fun executeAsyncCommand(
        command: String,
        outputFile: File,
        durationMs: Long,
        onProgress: (Float) -> Unit,
    ): Boolean {
        if (ffmpegRuntimeBroken) {
            Log.w(TAG, "Skip FFmpeg execution because runtime is marked broken")
            return false
        }

        return try {
            val latch = CountDownLatch(1)
            var succeeded = false
            val sessionKey = outputFile.absolutePath
            val session = FFmpegKit.executeAsync(
                command,
                { completed ->
                    activeSessions.remove(sessionKey)
                    succeeded = ReturnCode.isSuccess(completed.returnCode) &&
                        outputFile.exists() &&
                        outputFile.length() > 0L
                    if (!succeeded) {
                        Log.w(
                            TAG,
                            "FFmpeg async command failed " +
                                "(rc=${completed.returnCode}): $command",
                        )
                    }
                    latch.countDown()
                },
                { /* log lines already stream to logcat; nothing to do */ },
                { statistics ->
                    val timeMs = statistics.time
                    if (timeMs > 0) {
                        onProgress(
                            (timeMs.toFloat() / durationMs).coerceIn(0f, 1f),
                        )
                    }
                },
            )
            activeSessions[sessionKey] = session
            latch.await(10, TimeUnit.MINUTES)
            activeSessions.remove(sessionKey)
            succeeded
        } catch (t: Throwable) {
            // FFmpegKit can throw java.lang.Error in release builds when JNI init fails.
            // Treat it as a conversion miss so reader can continue with existing fallback.
            ffmpegRuntimeBroken = true
            Log.e(TAG, "FFmpeg runtime unavailable: ${t.message}", t)
            false
        }
    }

    private fun buildCommand(
        inputPath: String,
        quality: Int,
        outputPath: String,
        includeAnimatedStreamMap: Boolean,
    ): String {
        val mapArg = if (includeAnimatedStreamMap) "-map 0:v:1 " else ""
        return "-y -i ${quotePath(inputPath)} " +
            "${mapArg}-r 15 -c:v libwebp -quality $quality -loop 0 " +
            "-pix_fmt yuv420p ${quotePath(outputPath)}"
    }

    private fun executeCommand(command: String, outputFile: File): Boolean {
        if (ffmpegRuntimeBroken) {
            Log.w(TAG, "Skip FFmpeg execution because runtime is marked broken")
            return false
        }

        return try {
            val session = FFmpegKit.execute(command)
            val returnCode = session.returnCode
            if (!ReturnCode.isSuccess(returnCode)) {
                Log.w(TAG, "FFmpeg command failed (rc=$returnCode): $command")
                return false
            }
            if (!outputFile.exists() || outputFile.length() <= 0L) {
                Log.w(TAG, "FFmpeg succeeded but output file is empty: ${outputFile.path}")
                return false
            }
            true
        } catch (t: Throwable) {
            // FFmpegKit can throw java.lang.Error in release builds when JNI init fails.
            // Treat it as a conversion miss so reader can continue with existing fallback.
            ffmpegRuntimeBroken = true
            Log.e(TAG, "FFmpeg runtime unavailable: ${t.message}", t)
            false
        }
    }

    private fun quotePath(path: String): String {
        return "\"${path.replace("\\", "\\\\").replace("\"", "\\\"")}\""
    }

    /// A finished WebP is a RIFF container: bytes 4..7 hold (fileSize - 8)
    /// little-endian. Anything else means truncation — reconvert, never serve.
    private fun isCompleteWebP(file: File): Boolean {
        return try {
            if (file.length() < 12) return false
            java.io.RandomAccessFile(file, "r").use { raf ->
                val header = ByteArray(12)
                raf.readFully(header)
                if (!(header[0] == 0x52.toByte() &&
                        header[1] == 0x49.toByte() &&
                        header[2] == 0x46.toByte() &&
                        header[3] == 0x46.toByte() &&
                        header[8] == 0x57.toByte() &&
                        header[9] == 0x45.toByte() &&
                        header[10] == 0x42.toByte() &&
                        header[11] == 0x50.toByte())
                ) {
                    return false
                }
                val riffSize =
                    (header[4].toInt() and 0xFF) or
                        ((header[5].toInt() and 0xFF) shl 8) or
                        ((header[6].toInt() and 0xFF) shl 16) or
                        ((header[7].toInt() and 0xFF) shl 24)
                riffSize + 8L == file.length()
            }
        } catch (t: Throwable) {
            Log.w(TAG, "WebP completeness check failed: ${t.message}")
            false
        }
    }
}
