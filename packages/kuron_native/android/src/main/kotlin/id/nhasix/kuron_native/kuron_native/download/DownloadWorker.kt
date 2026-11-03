package id.nhasix.kuron_native.kuron_native.download

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Environment
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ListenableWorker
import androidx.work.WorkerParameters
import androidx.work.ForegroundInfo

import androidx.work.workDataOf
import android.content.pm.ServiceInfo
import id.nhasix.kuron_native.kuron_native.R
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.isActive
import okhttp3.ConnectionPool
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.URI
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

class DownloadWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    companion object {
        const val KEY_CONTENT_ID = "content_id"
        const val KEY_SOURCE_ID = "source_id"
        const val KEY_IMAGE_URLS = "image_urls"
        const val KEY_IMAGE_URLS_FILE = "image_urls_file" // New key for file path
        const val KEY_DESTINATION_PATH = "destination_path"
        const val KEY_COOKIES = "cookies"  // Cookies as JSON string
        const val KEY_HEADERS = "headers"  // Source-specific HTTP headers as JSON string
        const val KEY_PER_PAGE_PAYLOAD = "per_page_payload" // v2: JSON array of page objects
        // Metadata fields for v2.1
        const val KEY_TITLE = "title"
        const val KEY_URL = "url"
        const val KEY_COVER_URL = "cover_url"
        const val KEY_LANGUAGE = "language"
        const val KEY_START_PAGE = "start_page"
        const val KEY_END_PAGE = "end_page"
        const val KEY_TOTAL_PAGES = "total_pages"
        const val KEY_BACKUP_FOLDER = "backup_folder" // ✅ NEW: Configurable folder name
        const val KEY_PROGRESS = "progress"
        // Feature C: Parallel download config
        const val KEY_MAX_PARALLEL_IMAGES = "max_parallel_images"   // default 3
        const val KEY_IMAGE_TIMEOUT_MS = "image_timeout_ms"         // default 60_000 ms

        private const val TAG = "DownloadWorker"
        private const val INVALID_IMAGE_RESPONSE_CODE = 598
        private val ALLOWED_COOKIE_DOMAINS = setOf("crotpedia.net", "crotpedia.com")

        // Defaults for parallel download
        private const val DEFAULT_MAX_PARALLEL = 3
        private const val DEFAULT_IMAGE_TIMEOUT_MS = 60_000L
    }
    
    // Parse cookies from inputData and create HTTP client with authentication
    private val okHttpClient by lazy {
        val cookiesJson = inputData.getString(KEY_COOKIES)
        val cookies = parseCookies(cookiesJson)
        
        val builder = OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .connectionPool(ConnectionPool(1, 5, TimeUnit.SECONDS)) // 2.1: limit idle connections
        
        if (cookies != null && cookies.isNotEmpty()) {
            Log.d(TAG, "Creating HTTP client with ${cookies.size} cookies for authentication")
            builder.cookieJar(createCookieJar(cookies))
        }
        
        builder.build()
    }

    // Track total bytes for speed calculation (AtomicLong for parallel safety)
    private val totalBytesDownloaded = AtomicLong(0L)

    // 2.1: throttle setProgress at the source — at most one emission per
    // second per run. Terminal Result.success/failure always passes through.
    private var lastProgressEmitMs = 0L

    private suspend fun emitProgressThrottled(data: androidx.work.Data) {
        val now = android.os.SystemClock.elapsedRealtime()
        if (now - lastProgressEmitMs >= 1_000L) {
            lastProgressEmitMs = now
            setProgress(data)
        }
    }

    override suspend fun doWork(): ListenableWorker.Result = withContext(Dispatchers.IO) {
        val contentId = inputData.getString(KEY_CONTENT_ID) ?: return@withContext Result.failure()
        val sourceId = inputData.getString(KEY_SOURCE_ID) ?: "unknown"
        val destinationPath = inputData.getString(KEY_DESTINATION_PATH)
        
        // RESOLVE IMAGE URLs: Check file first (large lists), then Data (small lists/legacy)
        val imageUrlsFile = inputData.getString(KEY_IMAGE_URLS_FILE)
        val imageUrls: List<String> = if (!imageUrlsFile.isNullOrEmpty()) {
            try {
                val file = File(imageUrlsFile)
                if (file.exists()) {
                    val json = file.readText()
                    // Parse simple JSON array of strings
                    org.json.JSONArray(json).let { jsonArray ->
                        List(jsonArray.length()) { i -> jsonArray.getString(i) }
                    }
                } else {
                    Log.e(TAG, "Image URLs file not found at: $imageUrlsFile")
                    return@withContext Result.failure()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to read image URLs from file", e)
                return@withContext Result.failure()
            }
        } else {
            inputData.getStringArray(KEY_IMAGE_URLS)?.toList() ?: return@withContext Result.failure()
        }

        val startPage = inputData.getInt(KEY_START_PAGE, 1).coerceAtLeast(1)
        val fallbackEndPage = startPage + imageUrls.size - 1
        val requestedEndPage = inputData.getInt(KEY_END_PAGE, fallbackEndPage)
        val endPage = if (requestedEndPage >= startPage) requestedEndPage else fallbackEndPage
        val requestedTotalPages = inputData.getInt(KEY_TOTAL_PAGES, 0)
        val totalPages = if (requestedTotalPages > 0) {
            requestedTotalPages
        } else {
            maxOf(endPage, fallbackEndPage)
        }
        
        Log.d(TAG, "Starting download for $contentId from $sourceId with ${imageUrls.size} images (Native Notifications Disabled)")
        
        try {
            val downloadDir = getDownloadDirectory(sourceId, contentId, destinationPath)
            val result = downloadImages(
                contentId = contentId,
                sourceId = sourceId,
                imageUrls = imageUrls,
                destinationPath = destinationPath,
                startPage = startPage,
                endPage = endPage,
            )
            
            // Create metadata and .nomedia after successful download
            val title = inputData.getString(KEY_TITLE) ?: "Unknown"
            val url = inputData.getString(KEY_URL) ?: ""
            val coverUrl = inputData.getString(KEY_COVER_URL) ?: ""
            val language = inputData.getString(KEY_LANGUAGE) ?: "unknown"
            
            createMetadataFile(
                downloadDir, 
                contentId, 
                sourceId, 
                title,
                url,
                coverUrl,
                language,
                result.downloadedFiles,
                result.failedPages,
                startPage,
                endPage,
                totalPages,
            )
            createNoMediaFile(downloadDir)
            
            // Clean up the temp file if it was used
            if (!imageUrlsFile.isNullOrEmpty()) {
                try {
                    File(imageUrlsFile).delete()
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to delete temp urls file: $imageUrlsFile")
                }
            }
            
            Log.d(TAG, "Download complete for $contentId.")

            if (result.downloadedFiles.isEmpty()) {
                Log.e(TAG, "Download produced zero valid image files for $contentId")
                return@withContext Result.failure(workDataOf(
                    "content_id" to contentId,
                    "downloadedCount" to 0,
                    "totalCount" to imageUrls.size,
                    "error" to "No valid image files downloaded"
                ))
            }
            
            // Return success with complete data for EventChannel emission
            Result.success(workDataOf(
                "content_id" to contentId,
                "downloadedCount" to result.downloadedFiles.size,
                "totalCount" to imageUrls.size
            ))
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            
            Log.e(TAG, "Download failed for $contentId", e)
            Result.retry()
        }
    }
    
    // Result of downloadImages: downloaded file names + failed page entries
    data class DownloadImagesResult(
        val downloadedFiles: List<String>,
        // List of (1-based page index, original URL) for pages that failed/timed out
        val failedPages: List<Pair<Int, String>>,
        val totalPages: Int,
    )

    private suspend fun downloadImages(
        contentId: String, 
        sourceId: String, 
        imageUrls: List<String>, 
        destinationPath: String?,
        startPage: Int,
        endPage: Int,
    ): DownloadImagesResult {
        val downloadDir = getDownloadDirectory(sourceId, contentId, destinationPath)
        // Create /images/ subfolder to match Flutter pattern
        val imagesDir = File(downloadDir, "images")
        
        Log.d(TAG, "Target Download Dir: ${downloadDir.absolutePath}")
        Log.d(TAG, "Target Images Dir: ${imagesDir.absolutePath}")
        
        if (!imagesDir.exists()) {
            val created = imagesDir.mkdirs()
            Log.d(TAG, "Created Images Dir: $created")
            if (!created) {
                Log.e(TAG, "Failed to create dir! Checking parent: ${downloadDir.exists()}")
                throw IOException("Failed to create directory: ${imagesDir.absolutePath}")
            }
        } else {
             Log.d(TAG, "Images Dir already exists")
        }

        val existingFilesByPage = buildExistingPageFileMap(imagesDir, startPage, endPage)
        val completedCount = AtomicInteger(existingFilesByPage.size)
        totalBytesDownloaded.set(existingFilesByPage.values.fold(0L) { acc, file ->
            acc + file.length()
        })

        if (completedCount.get() > 0) {
            emitProgressThrottled(workDataOf(
                KEY_PROGRESS to calculateProgressPercent(completedCount.get(), imageUrls.size),
                "downloadedCount" to completedCount.get(),
                "totalCount" to imageUrls.size,
                "downloadedBytes" to totalBytesDownloaded.get(),
                KEY_CONTENT_ID to contentId
            ))
        }

        // Feature C: Read parallel config from inputData
        val maxParallel = inputData.getInt(KEY_MAX_PARALLEL_IMAGES, DEFAULT_MAX_PARALLEL)
            .coerceIn(1, 6)
        val imageTimeoutMs = inputData.getLong(KEY_IMAGE_TIMEOUT_MS, DEFAULT_IMAGE_TIMEOUT_MS)
            .coerceAtLeast(10_000L)

        Log.d(TAG, "Parallel download: maxParallel=$maxParallel, timeoutMs=$imageTimeoutMs")

        // Thread-safe map for results (pageNumber -> filename)
        val resultFileNames = Array<String?>(imageUrls.size) { null }
        // Track failed pages in original gallery numbering.
        val failedPageNumbers = java.util.concurrent.ConcurrentHashMap<Int, String>()

        // Pre-fill already-downloaded pages
        existingFilesByPage.forEach { (pageNumber, file) ->
            val resultIndex = pageNumber - startPage
            if (resultIndex in resultFileNames.indices) {
                resultFileNames[resultIndex] = file.name
            }
        }

        val semaphore = Semaphore(maxParallel)

        coroutineScope {
            val jobs = imageUrls.mapIndexed { index, url ->
                async(Dispatchers.IO) {
                    if (isStopped) return@async

                    val pageNumber = startPage + index

                    // Skip already-downloaded pages
                    if (existingFilesByPage.containsKey(pageNumber)) {
                        return@async
                    }

                    semaphore.withPermit {
                        if (isStopped) return@withPermit

                        val extension = resolveFileExtension(url)
                        val fileName = "page_${pageNumber.toString().padStart(3, '0')}$extension"
                        val destFile = File(imagesDir, fileName)

                        val hasValidDestinationFile = destFile.exists() &&
                            destFile.length() > 0L &&
                            isValidDownloadedImageFile(destFile)

                        if (!hasValidDestinationFile) {
                            if (destFile.exists() && destFile.length() > 0L) {
                                Log.w(TAG, "Replacing invalid existing page file ${destFile.absolutePath}")
                                destFile.delete()
                            }

                            // Feature C: Per-image timeout — skip slow images instead of blocking
                            val downloadResult = withTimeoutOrNull(imageTimeoutMs) {
                                try {
                                    // v2: merge per-page headers (per-page wins over global)
                                    val pageOverrides = perPageHeaders?.get(pageNumber)
                                    downloadImage(url, destFile, pageOverrides)
                                    true
                                } catch (e: Exception) {
                                    if (e is CancellationException) throw e
                                    Log.w(TAG, "Failed to download page $pageNumber: ${e.message}")
                                    false
                                }
                            }

                            if (downloadResult == null) {
                                // Timeout — skip this image, record as failed
                                Log.w(TAG, "⏱️ Timeout downloading page $pageNumber (${shortUrl(url)}) — skipping")
                                destFile.delete() // Clean up any partial file
                                failedPageNumbers[pageNumber] = url
                                return@withPermit
                            }

                            if (downloadResult == false) {
                                // Download error — record as failed
                                failedPageNumbers[pageNumber] = url
                                return@withPermit
                            }
                        }

                        val normalizedFile = if (isEhentaiReaderPageUrl(url)) {
                            normalizeDownloadedFileExtension(destFile)
                        } else {
                            destFile
                        }

                        if (normalizedFile.exists() && normalizedFile.length() > 0L) {
                            resultFileNames[pageNumber - startPage] = normalizedFile.name
                            val newCount = completedCount.incrementAndGet()
                            totalBytesDownloaded.addAndGet(normalizedFile.length())

                            emitProgressThrottled(workDataOf(
                                KEY_PROGRESS to calculateProgressPercent(newCount, imageUrls.size),
                                "downloadedCount" to newCount,
                                "totalCount" to imageUrls.size,
                                "downloadedBytes" to totalBytesDownloaded.get(),
                                KEY_CONTENT_ID to contentId
                            ))
                        } else {
                            // File didn't end up valid after download
                            failedPageNumbers[pageNumber] = url
                        }
                    }
                }
            }
            jobs.awaitAll()
        }

        if (isStopped) throw CancellationException("Work cancelled")

        val failedPages = failedPageNumbers.entries
            .sortedBy { it.key }
            .map { (pageNumber, url) -> Pair(pageNumber, url) }

        if (failedPages.isNotEmpty()) {
            Log.w(TAG, "⚠️ ${failedPages.size} page(s) failed to download for $contentId: ${failedPages.map { it.first }}")
        }

        return DownloadImagesResult(
            downloadedFiles = resultFileNames.filterNotNull(),
            failedPages = failedPages,
            totalPages = imageUrls.size,
        )
    }
    
    private fun getDownloadDirectory(sourceId: String, contentId: String, destinationPath: String?): File {
        // If destinationPath is provided by Flutter, use it
        if (!destinationPath.isNullOrEmpty()) {
            return File(destinationPath)
        }
        
        // Get backup folder name from inputData (default: "nhasix")
        val backupFolderName = inputData.getString(KEY_BACKUP_FOLDER) ?: "nhasix"
        
        // Fallback: /storage/emulated/0/Download/[backupFolderName]/{source}/{contentId}
        val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        return File(downloadsDir, "$backupFolderName${File.separator}$sourceId${File.separator}$contentId")
    }
    
    private val customHeaders: Map<String, String> by lazy {
        parseHeaders(inputData.getString(KEY_HEADERS))
    }

    // v2: per-page headers (1-based page index → merged headers).
    // Null when the worker was invoked with v1 payload (no perPagePayload key).
    private val perPageHeaders: Map<Int, Map<String, String>>? by lazy {
        parsePerPagePayload(inputData.getString(KEY_PER_PAGE_PAYLOAD))
    }

    private fun parseHeaders(headersJson: String?): Map<String, String> {
        if (headersJson.isNullOrBlank()) return emptyMap()
        return try {
            val json = JSONObject(headersJson)
            val parsed = mutableMapOf<String, String>()
            val keys = json.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                val value = json.optString(key)
                if (key.isNotBlank() && value.isNotBlank()) {
                    parsed[key] = value
                }
            }
            Log.d(TAG, "Parsed ${parsed.size} custom headers from config")
            parsed
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse headers JSON", e)
            emptyMap()
        }
    }

    // ── v2 per-page payload parsing ──────────────────────────────────────────

    /**
     * Parse the v2 per-page payload (JSON array of page objects produced by
     * NativeDownloadPayload.toChannelMap()).
     *
     * Returns a map of 1-based page index → per-page headers, or null if
     * the key is absent (v1 fallback).
     */
    private fun parsePerPagePayload(payloadJson: String?): Map<Int, Map<String, String>>? {
        if (payloadJson.isNullOrBlank()) return null
        return try {
            val array = org.json.JSONArray(payloadJson)
            val result = mutableMapOf<Int, Map<String, String>>()
            for (i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                val pageNumber = obj.optInt("pageNumber", i + 1)
                val headersObj = obj.optJSONObject("headers")
                val pageHeaders = mutableMapOf<String, String>()
                if (headersObj != null) {
                    val keys = headersObj.keys()
                    while (keys.hasNext()) {
                        val k = keys.next()
                        val v = headersObj.optString(k)
                        if (k.isNotBlank() && v.isNotBlank()) pageHeaders[k] = v
                    }
                }
                val referer = obj.optString("referer", "")
                if (referer.isNotBlank()) pageHeaders["Referer"] = referer
                result[pageNumber] = pageHeaders
            }
            Log.d(TAG, "Parsed v2 per-page payload: ${result.size} pages")
            result
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse per-page payload JSON", e)
            null
        }
    }

    private fun downloadImage(url: String, destFile: File, pageHeaderOverrides: Map<String, String>? = null) {
        if (isEhentaiReaderPageUrl(url)) {
            downloadEhentaiReaderPage(url, destFile)
            return
        }

        // Merge: global headers ← per-page overrides (per-page wins)
        val initialHeaders = customHeaders.toMutableMap()
        pageHeaderOverrides?.forEach { (k, v) -> initialHeaders[k] = v }
        val attempts = buildHeaderAttempts(url, initialHeaders)

        var lastCode = -1
        for ((index, headers) in attempts.withIndex()) {
            if (index == 0) {
                Log.d(
                    TAG,
                    "Downloading image: url=${shortUrl(url)}, target=${destFile.name}, headerKeys=${headers.keys.sorted()}"
                )
            }
            val code = executeDownloadRequest(url, headers, destFile)
            if (code in 200..299) {
                if (index > 0) {
                    Log.i(TAG, "Image download succeeded on retry attempt=${index + 1} code=$code")
                }
                return
            }

            lastCode = code
            if (code != 403 && code != INVALID_IMAGE_RESPONSE_CODE) {
                break
            }
        }

        throw IOException("HTTP $lastCode for URL: $url")
    }

    private fun isEhentaiReaderPageUrl(url: String): Boolean {
        return try {
            val uri = URI(url)
            val host = uri.host?.lowercase() ?: return false
            val path = uri.path ?: return false

            (host == "e-hentai.org" || host == "exhentai.org") && path.startsWith("/s/")
        } catch (_: Exception) {
            false
        }
    }

    private fun downloadEhentaiReaderPage(readerPageUrl: String, destFile: File) {
        val baseHeaders = customHeaders.toMutableMap()
        val readerHtml = fetchEhentaiReaderHtml(readerPageUrl, baseHeaders)
        val resolvedImageUrl = extractEhentaiImageUrl(readerHtml)
            ?: throw IOException("Unable to resolve EHentai image URL from reader page: $readerPageUrl")

        val imageHeaders = baseHeaders.toMutableMap().apply {
            this["Referer"] = readerPageUrl
            this["referer"] = readerPageUrl
            try {
                val uri = URI(readerPageUrl)
                val origin = "${uri.scheme}://${uri.host}"
                this["Origin"] = origin
                this["origin"] = origin
            } catch (_: Exception) {
                remove("Origin")
                remove("origin")
            }
        }

        val attempts = buildHeaderAttempts(resolvedImageUrl, imageHeaders)
        var lastCode = -1

        for ((index, headers) in attempts.withIndex()) {
            val code = executeDownloadRequest(resolvedImageUrl, headers, destFile)
            if (code in 200..299) {
                if (index > 0) {
                    Log.i(TAG, "EHentai image download succeeded on retry attempt=${index + 1} code=$code")
                }
                return
            }

            lastCode = code
            if (code != 403 && code != INVALID_IMAGE_RESPONSE_CODE) {
                break
            }
        }

        throw IOException(
            "HTTP $lastCode for EHentai image URL: $resolvedImageUrl (reader: $readerPageUrl)"
        )
    }

    private fun fetchEhentaiReaderHtml(
        readerPageUrl: String,
        baseHeaders: Map<String, String>
    ): String {
        val attempts = buildHeaderAttempts(readerPageUrl, baseHeaders)
        var lastCode = -1

        for ((index, headers) in attempts.withIndex()) {
            val requestBuilder = Request.Builder().url(readerPageUrl)
            headers.forEach { (name, value) -> requestBuilder.header(name, value) }
            val request = requestBuilder.build()

            var shouldRetry = false
            okHttpClient.newCall(request).execute().use { response ->
                val body = response.body?.string().orEmpty()
                if (response.isSuccessful && body.isNotBlank()) {
                    if (index > 0) {
                        Log.i(
                            TAG,
                            "EHentai reader page resolved on retry attempt=${index + 1} code=${response.code}"
                        )
                    }
                    return body
                }

                lastCode = response.code
                shouldRetry = response.code == 403
            }

            if (!shouldRetry) {
                break
            }
        }

        throw IOException("HTTP $lastCode while loading EHentai reader page: $readerPageUrl")
    }

    private fun extractEhentaiImageUrl(readerHtml: String): String? {
        val patterns = listOf(
            Regex("""<img[^>]*id=["']img["'][^>]*src=["']([^"']+)["']""", RegexOption.IGNORE_CASE),
            Regex("""<img[^>]*src=["']([^"']+)["'][^>]*id=["']img["']""", RegexOption.IGNORE_CASE)
        )

        for (pattern in patterns) {
            val candidate = pattern.find(readerHtml)
                ?.groupValues
                ?.getOrNull(1)
                ?.trim()
            if (!candidate.isNullOrEmpty()) {
                return decodeHtmlEntities(candidate)
            }
        }

        return null
    }

    private fun decodeHtmlEntities(value: String): String {
        return value
            .replace("&amp;", "&")
            .replace("&quot;", "\"")
            .replace("&#39;", "'")
    }

    private fun buildHeaderAttempts(
        imageUrl: String,
        baseHeaders: Map<String, String>
    ): List<Map<String, String>> {
        val attempts = mutableListOf<Map<String, String>>()
        val seen = mutableSetOf<String>()

        fun addAttempt(headers: Map<String, String>) {
            val key = headers.entries
                .sortedBy { it.key.lowercase() }
                .joinToString("|") { "${it.key.lowercase()}=${it.value}" }
            if (seen.add(key)) {
                attempts.add(headers)
            }
        }

        // Attempt 1: original headers from Flutter/config.
        addAttempt(baseHeaders)

        val imageUri = try {
            URI(imageUrl)
        } catch (_: Exception) {
            null
        }

        val currentReferer = baseHeaders["Referer"] ?: baseHeaders["referer"]
        val refererCandidates = mutableListOf<String>()

        if (!currentReferer.isNullOrBlank()) {
            refererCandidates.add(currentReferer)
            if (!currentReferer.endsWith('/')) {
                refererCandidates.add("$currentReferer/")
            }
            try {
                val uri = URI(currentReferer)
                refererCandidates.add("${uri.scheme}://${uri.host}/")
            } catch (_: Exception) {
                // ignore malformed referer
            }
        }

        if (imageUri != null) {
            // Some CDNs allow self-host parent as referer.
            val origin = "${imageUri.scheme}://${imageUri.host}"
            refererCandidates.add("$origin/")
        }

        for (referer in refererCandidates.distinct()) {
            val withOrigin = baseHeaders.toMutableMap().apply {
                this["Referer"] = referer
                this["referer"] = referer
                try {
                    val uri = URI(referer)
                    val origin = "${uri.scheme}://${uri.host}"
                    this["Origin"] = origin
                    this["origin"] = origin
                } catch (_: Exception) {
                    remove("Origin")
                    remove("origin")
                }
            }
            addAttempt(withOrigin)

            // Some anti-hotlink checks fail if Origin exists for image requests.
            val withoutOrigin = withOrigin.toMutableMap().apply {
                remove("Origin")
                remove("origin")
            }
            addAttempt(withoutOrigin)
        }

        Log.d(TAG, "Prepared ${attempts.size} header attempts for image host retry")
        return attempts
    }

    private fun executeDownloadRequest(
        url: String,
        headers: Map<String, String>,
        destFile: File
    ): Int {
        val requestBuilder = Request.Builder().url(url)
        headers.forEach { (name, value) -> requestBuilder.header(name, value) }
        val request = requestBuilder.build()

        okHttpClient.newCall(request).execute().use { response: Response ->
            Log.d(
                TAG,
                "HTTP ${response.code} for ${shortUrl(url)} -> ${destFile.name} contentType=${response.body?.contentType()}"
            )
            if (!response.isSuccessful) {
                return response.code
            }

            val tempFile = File(destFile.parentFile, "${destFile.name}.part")
            response.body?.byteStream()?.use { input ->
                tempFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            } ?: run {
                tempFile.delete()
                Log.w(TAG, "Successful response had empty body for ${shortUrl(url)}")
                return INVALID_IMAGE_RESPONSE_CODE
            }

            if (!isValidDownloadedImageFile(tempFile)) {
                Log.w(
                    TAG,
                    "Rejecting invalid image payload for ${shortUrl(url)} -> ${destFile.name} size=${tempFile.length()}"
                )
                tempFile.delete()
                return INVALID_IMAGE_RESPONSE_CODE
            }

            replaceDownloadedFile(tempFile, destFile)
            return response.code
        }
    }

    private fun replaceDownloadedFile(sourceFile: File, destFile: File) {
        if (destFile.exists() && !destFile.delete()) {
            Log.w(TAG, "Failed to delete stale destination file ${destFile.absolutePath}")
        }

        val renamed = sourceFile.renameTo(destFile)
        if (!renamed) {
            sourceFile.copyTo(destFile, overwrite = true)
            sourceFile.delete()
        }
    }

    private fun resolveFileExtension(url: String): String {
        val normalizedPath = try {
            URI(url).path.lowercase()
        } catch (_: Exception) {
            url.lowercase()
        }

        return when {
            normalizedPath.endsWith(".avif") -> ".avif"
            normalizedPath.endsWith(".webp") -> ".webp"
            normalizedPath.endsWith(".png") -> ".png"
            normalizedPath.endsWith(".gif") -> ".gif"
            normalizedPath.endsWith(".bmp") -> ".bmp"
            normalizedPath.endsWith(".jpeg") -> ".jpeg"
            normalizedPath.endsWith(".jpg") -> ".jpg"
            else -> ".jpg"
        }
    }

    private fun buildExistingPageFileMap(imagesDir: File, startPage: Int, endPage: Int): MutableMap<Int, File> {
        val existingFiles = mutableMapOf<Int, File>()

        for (pageNumber in startPage..endPage) {
            val existing = findExistingDownloadedPage(imagesDir, pageNumber)
            if (existing != null) {
                existingFiles[pageNumber] = existing
            }
        }

        return existingFiles
    }

    private fun findExistingDownloadedPage(imagesDir: File, pageNumber: Int): File? {
        val baseName = "page_${pageNumber.toString().padStart(3, '0')}"
        val supportedExtensions = listOf(
            ".jpg",
            ".jpeg",
            ".png",
            ".webp",
            ".avif",
            ".gif",
            ".bmp"
        )

        for (extension in supportedExtensions) {
            val candidate = File(imagesDir, "$baseName$extension")
            if (candidate.exists() &&
                candidate.length() > 0L &&
                isValidDownloadedImageFile(candidate)
            ) {
                return candidate
            }
        }

        return null
    }

    private fun calculateProgressPercent(downloadedCount: Int, totalCount: Int): Int {
        if (totalCount <= 0) {
            return 0
        }

        return ((downloadedCount.toFloat() / totalCount) * 100).toInt()
    }

    private fun normalizeDownloadedFileExtension(file: File): File {
        if (!file.exists() || file.length() == 0L) {
            return file
        }

        val actualExtension = detectActualFileExtension(file) ?: return file
        if (file.name.lowercase().endsWith(actualExtension)) {
            return file
        }

        val renamedFile = File(file.parentFile, "${file.nameWithoutExtension}$actualExtension")
        if (renamedFile.absolutePath == file.absolutePath) {
            return file
        }

        if (renamedFile.exists() && renamedFile.length() > 0L) {
            Log.w(
                TAG,
                "Detected existing normalized file ${renamedFile.name}; removing stale ${file.name}"
            )
            file.delete()
            return renamedFile
        }

        val renamed = file.renameTo(renamedFile)
        if (renamed) {
            Log.i(
                TAG,
                "Normalized downloaded file extension: ${file.name} -> ${renamedFile.name}"
            )
            return renamedFile
        }

        Log.w(
            TAG,
            "Failed to normalize downloaded file extension for ${file.absolutePath}"
        )
        return file
    }

    private fun isValidDownloadedImageFile(file: File): Boolean {
        if (!file.exists() || file.length() == 0L) {
            return false
        }

        return detectActualFileExtension(file) != null
    }

    private fun detectActualFileExtension(file: File): String? {
        return try {
            file.inputStream().use { input ->
                val header = ByteArray(64)
                val bytesRead = input.read(header)
                if (bytesRead <= 0) {
                    return null
                }

                if (bytesRead >= 12 &&
                    header[0] == 'R'.code.toByte() &&
                    header[1] == 'I'.code.toByte() &&
                    header[2] == 'F'.code.toByte() &&
                    header[3] == 'F'.code.toByte() &&
                    header[8] == 'W'.code.toByte() &&
                    header[9] == 'E'.code.toByte() &&
                    header[10] == 'B'.code.toByte() &&
                    header[11] == 'P'.code.toByte()
                ) {
                    return ".webp"
                }

                if (bytesRead >= 3 &&
                    header[0] == 'G'.code.toByte() &&
                    header[1] == 'I'.code.toByte() &&
                    header[2] == 'F'.code.toByte()
                ) {
                    return ".gif"
                }

                if (bytesRead >= 8 &&
                    header[0] == 0x89.toByte() &&
                    header[1] == 'P'.code.toByte() &&
                    header[2] == 'N'.code.toByte() &&
                    header[3] == 'G'.code.toByte()
                ) {
                    return ".png"
                }

                if (bytesRead >= 3 &&
                    header[0] == 0xFF.toByte() &&
                    header[1] == 0xD8.toByte() &&
                    header[2] == 0xFF.toByte()
                ) {
                    return ".jpg"
                }

                if (bytesRead >= 2 &&
                    header[0] == 0x42.toByte() &&
                    header[1] == 0x4D.toByte()
                ) {
                    return ".bmp"
                }

                if (bytesRead >= 16 &&
                    header[4] == 'f'.code.toByte() &&
                    header[5] == 't'.code.toByte() &&
                    header[6] == 'y'.code.toByte() &&
                    header[7] == 'p'.code.toByte()
                ) {
                    val brand = String(header, 8, 4)
                    if (brand == "avif" || brand == "avis" || brand == "mif1") {
                        return ".avif"
                    }
                }

                null
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to detect actual file extension for ${file.absolutePath}", e)
            null
        }
    }

    private fun shortUrl(url: String, maxLength: Int = 120): String {
        return if (url.length <= maxLength) url else "${url.take(maxLength)}..."
    }
    
    // ============ Cookie Handling Methods ============
    
    /**
     * Parse cookies from JSON string to Map
     * Format: {"cookie1":"value1","cookie2":"value2"}
     */
    private fun parseCookies(cookiesJson: String?): Map<String, String>? {
        if (cookiesJson.isNullOrBlank()) return null
        
        return try {
            val json = JSONObject(cookiesJson)
            val parsed = mutableMapOf<String, String>()
            val keys = json.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                val value = json.optString(key)
                if (key.isNotBlank() && value.isNotBlank()) {
                    parsed[key] = value
                }
            }
            if (parsed.isEmpty()) {
                null
            } else {
                Log.d(TAG, "Parsed ${parsed.size} cookies from JSON")
                parsed
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse cookies JSON", e)
            null
        }
    }
    
    /**
     * Create CookieJar from Map with domain validation
     * Security: Cookies only sent to crotpedia.com
     */
    private fun createCookieJar(cookiesMap: Map<String, String>): okhttp3.CookieJar {
        return object : okhttp3.CookieJar {
            override fun saveFromResponse(url: okhttp3.HttpUrl, cookies: List<okhttp3.Cookie>) {
                // No-op: we don't save cookies from responses
            }
            
            override fun loadForRequest(url: okhttp3.HttpUrl): List<okhttp3.Cookie> {
                // Security: Only return cookies for allowed domain (exact host or subdomain boundary)
                val allowed = ALLOWED_COOKIE_DOMAINS.any { allowedDomain ->
                    url.host.equals(allowedDomain, ignoreCase = true) ||
                        url.host.endsWith(".$allowedDomain", ignoreCase = true)
                }
                if (!allowed) {
                    Log.d(TAG, "No cookies for domain: ${url.host}")
                    return emptyList()
                }
                
                // Convert Map to OkHttp Cookie objects
                return cookiesMap.map { (name, value) ->
                    okhttp3.Cookie.Builder()
                        .name(name)
                        .value(value)
                        .domain(url.host)
                        .path("/")
                        .build()
                }.also { cookieList ->
                    Log.d(TAG, "Loaded ${cookieList.size} cookies for ${url.host}")
                }
            }
        }
    }

    // ============ Metadata & Privacy Methods ============

    /**
     * Create metadata.json file with download information
     * Schema v2.1 - Matches DownloadService format for full compatibility
     * Uses snake_case keys to match Dart implementation
     */
    private fun createMetadataFile(
        downloadDir: File,
        contentId: String,
        sourceId: String,
        title: String,
        url: String,
        coverUrl: String,
        language: String,
        imageFiles: List<String>,
        failedPages: List<Pair<Int, String>> = emptyList(),
        startPage: Int = 1,
        endPage: Int = imageFiles.size,
        totalPages: Int = imageFiles.size,
    ) {
        try {
            val isRangeDownload = startPage > 1 || endPage < totalPages
            val failedPagesJson = org.json.JSONArray().apply {
                failedPages.forEach { (page, originalUrl) ->
                    put(org.json.JSONObject().apply {
                        put("page", page)
                        put("url", originalUrl)
                    })
                }
            }

            val metadata = mapOf(
                "schemaVersion" to "2.1",
                "source" to sourceId,
                "content_id" to contentId,
                "title" to title,
                "url" to url,
                "download_date" to java.text.SimpleDateFormat(
                    "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
                    java.util.Locale.US
                ).apply {
                    timeZone = java.util.TimeZone.getTimeZone("UTC")
                }.format(java.util.Date()),
                "total_pages" to totalPages,
                "downloaded_files" to imageFiles.size,
                "files" to imageFiles,
                "failed_pages" to failedPagesJson,
                "language" to language,
                "cover_url" to coverUrl,
                "is_range_download" to isRangeDownload,
                "start_page" to startPage,
                "end_page" to endPage,
                "pages_downloaded" to imageFiles.size
            )
            
            val metadataFile = File(downloadDir, "metadata.json")
            metadataFile.writeText(org.json.JSONObject(metadata).toString(2))
            Log.d(TAG, "Created v2.1 metadata file for $contentId (${imageFiles.size}/${totalPages} pages, ${failedPages.size} failed)")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to create metadata file", e)
            // Non-critical, don't fail download
        }
    }

    /**
     * Create .nomedia file to hide images from Android Gallery/Photos apps
     * Privacy protection - prevents downloaded content from appearing in media apps
     */
    private fun createNoMediaFile(directory: File) {
        try {
            val noMediaFile = File(directory, ".nomedia")
            if (!noMediaFile.exists()) {
                noMediaFile.createNewFile()
                Log.d(TAG, "Created .nomedia file in ${directory.name}")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to create .nomedia file", e)
            // Non-critical, don't fail download
        }
    }
}
