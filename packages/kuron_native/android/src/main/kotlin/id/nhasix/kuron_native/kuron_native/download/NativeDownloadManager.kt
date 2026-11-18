package id.nhasix.kuron_native.kuron_native.download

import android.content.Context
import android.util.Log
import androidx.work.Constraints
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.workDataOf
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class NativeDownloadManager(private val context: Context) {
    companion object {
        private const val TAG = "NativeDownloadManager"
    }
    
    fun queueDownload(
        contentId: String,
        sourceId: String,
        imageUrls: List<String>,
        destinationPath: String,
        cookies: Map<String, String>? = null,  // Optional cookies for authentication
        headers: Map<String, String>? = null,  // Optional source-specific HTTP headers
        // Metadata for v2.1
        title: String = "Unknown",
        url: String = "",
        coverUrl: String = "",
        language: String = "unknown",
        startPage: Int = 1,
        endPage: Int = imageUrls.size,
        totalPages: Int = imageUrls.size,
        backupFolderName: String = "nhasix",  // ✅ NEW: Configurable backup folder name
        // Feature C: Parallel download config
        maxParallelImages: Int = 3,
        imageTimeoutMs: Long = 60_000L,
    ): String {
        // Convert cookies Map to JSON string for WorkManager Data
        val cookiesJson = cookies?.let { map -> JSONObject(map).toString() }

        // Convert headers Map to JSON string for WorkManager Data
        val headersJson = headers?.let { map -> JSONObject(map).toString() }
        
        // FIX: WorkManager has 10KB Data limit. Large lists (>200 items) cause crash.
        // Solution: Write URLs to a temporary file and pass file path to Worker.
        val safeKey = contentId.replace(Regex("[^A-Za-z0-9._-]"), "_").take(80)
        val urlsFile = java.io.File(context.cacheDir, "download_urls_${safeKey}_${contentId.hashCode()}.json")
        try {
            val jsonArray = org.json.JSONArray(imageUrls)
            urlsFile.writeText(jsonArray.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to persist image URL list for contentId=$contentId", e)
            throw IllegalStateException(
                "Failed to persist image URL list for native worker",
                e
            )
        }

        val workRequest = OneTimeWorkRequestBuilder<DownloadWorker>()
            .setInputData(workDataOf(
                DownloadWorker.KEY_CONTENT_ID to contentId,
                DownloadWorker.KEY_SOURCE_ID to sourceId,
                // Pass file path instead of raw list
                DownloadWorker.KEY_IMAGE_URLS_FILE to urlsFile.absolutePath,
                DownloadWorker.KEY_DESTINATION_PATH to destinationPath,
                DownloadWorker.KEY_COOKIES to cookiesJson,
                DownloadWorker.KEY_HEADERS to headersJson,
                // Pass metadata
                DownloadWorker.KEY_TITLE to title,
                DownloadWorker.KEY_URL to url,
                DownloadWorker.KEY_COVER_URL to coverUrl,
                DownloadWorker.KEY_LANGUAGE to language,
                DownloadWorker.KEY_START_PAGE to startPage,
                DownloadWorker.KEY_END_PAGE to endPage,
                DownloadWorker.KEY_TOTAL_PAGES to totalPages,
                // ✅ NEW: Pass backup folder name for fallback path construction
                DownloadWorker.KEY_BACKUP_FOLDER to backupFolderName,
                // Feature C: Parallel download config
                DownloadWorker.KEY_MAX_PARALLEL_IMAGES to maxParallelImages,
                DownloadWorker.KEY_IMAGE_TIMEOUT_MS to imageTimeoutMs,
            ))
            .setConstraints(Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build())
            .addTag("content_$contentId")
            .addTag("native_download")
            .build()
        
        // CRITICAL: Explicitly cancel any old work with this tag (including anonymous work from previous versions)
        // enqueueUniqueWork only handles work with the same UNIQUE NAME, not just the same tag.
        WorkManager.getInstance(context).cancelAllWorkByTag("content_$contentId")

        // NOTE: do not call pruneWork() here. Pruning on every enqueue races
        // with other in-flight download scopes and can evict their WorkInfo.
        // Use enqueueUniqueWork with REPLACE policy to ensure new download starts fresh
        WorkManager.getInstance(context).enqueueUniqueWork(
            "content_$contentId",
            androidx.work.ExistingWorkPolicy.REPLACE,
            workRequest
        )
        return workRequest.id.toString()
    }

    fun cancelDownload(contentId: String) {
        WorkManager.getInstance(context).cancelAllWorkByTag("content_$contentId")
    }

    fun pauseDownload(contentId: String) {
        // For WorkManager, pausing is effectively cancelling.
        // Resume will re-queue and the worker skips existing files.
        cancelDownload(contentId)
    }

    fun getDownloadStatus(contentId: String): Map<String, Any?>? {
        return try {
            // Use get() with timeout to avoid blocking indefinitely
            val workInfos = WorkManager.getInstance(context)
                .getWorkInfosByTag("content_$contentId")
                .get(1, TimeUnit.SECONDS)
            
            // Priority: RUNNING > ENQUEUED > SUCCEEDED > FAILED > CANCELLED
            val workInfo = workInfos.firstOrNull { it.state == androidx.work.WorkInfo.State.RUNNING }
                ?: workInfos.firstOrNull { it.state == androidx.work.WorkInfo.State.ENQUEUED }
                ?: workInfos.firstOrNull { it.state == androidx.work.WorkInfo.State.SUCCEEDED }
                ?: workInfos.firstOrNull { it.state == androidx.work.WorkInfo.State.FAILED }
                ?: workInfos.firstOrNull() ?: return null
            
            val state = when (workInfo.state) {
                androidx.work.WorkInfo.State.RUNNING -> "RUNNING"
                androidx.work.WorkInfo.State.SUCCEEDED -> "COMPLETED"
                androidx.work.WorkInfo.State.FAILED -> "FAILED"
                androidx.work.WorkInfo.State.ENQUEUED -> "PENDING"
                androidx.work.WorkInfo.State.BLOCKED -> "PENDING"
                androidx.work.WorkInfo.State.CANCELLED -> "CANCELLED"
            }
            
            val progress = workInfo.progress
            val downloaded = progress.getInt("downloadedCount", 0)
            val total = progress.getInt("totalCount", 0)
            
            mapOf(
                "status" to state,
                "downloadedPages" to downloaded,
                "totalPages" to total,
                "contentId" to contentId
            )
        } catch (e: Exception) {
            null
        }
    }
}
