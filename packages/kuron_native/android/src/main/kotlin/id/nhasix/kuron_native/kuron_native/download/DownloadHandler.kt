package id.nhasix.kuron_native.kuron_native.download

import android.content.Context
import android.util.Log
import androidx.work.WorkInfo
import androidx.work.WorkManager
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.File

/**
 * Download Method Handler for kuron_native plugin
 * Handles WorkManager-based downloads with metadata v2.1 support
 */
class DownloadHandler(
    private val context: Context,
    private val eventChannel: EventChannel
) {
    private val downloadManager = NativeDownloadManager(context)
    private var eventSink: EventChannel.EventSink? = null
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var progressJob: Job? = null
    // Cache for deduplication: contentId -> fingerprint
    private val lastEmittedStates = java.util.concurrent.ConcurrentHashMap<String, String>()
    // FIX: Track terminal states to prevent spam when multiple downloads active
    private val terminalStatesEmitted = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()
    
    // Speed calculation: ContentId -> Pair(LastBytes, LastTimestamp)
    private val lastSpeedData = java.util.concurrent.ConcurrentHashMap<String, Pair<Long, Long>>()

    companion object {
        private const val TAG = "DownloadHandler"
    }

    init {
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                Log.d(TAG, "EventChannel: Flutter started listening to download progress")
                eventSink = events
                startObservingProgress()
            }
            override fun onCancel(arguments: Any?) {
                Log.d(TAG, "EventChannel: Flutter stopped listening to download progress")
                eventSink = null
                stopObservingProgress()
            }
        })
    }

    private fun startObservingProgress() {
        Log.d(TAG, "startObservingProgress: Starting to observe WorkManager flow for tag 'native_download'")
        progressJob?.cancel()
        progressJob = scope.launch {
            // FIX: Prune old completed work to prevent notification spam on app restart/update
            // This ensures we don't get 'SUCCEEDED' events for downloads finished in previous sessions
            try {
                WorkManager.getInstance(context).pruneWork()
                Log.d(TAG, "Pruned old WorkManager history")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to prune WorkManager history: ${e.message}")
            }

            WorkManager.getInstance(context)
                .getWorkInfosByTagFlow("native_download")
                .collect { workInfos ->
                    Log.d(TAG, "WorkManager flow: Received ${workInfos.size} work items")
                    
                     // Group by contentId to handle multiple different downloads separately
                    val grouped = workInfos.groupBy { 
                        it.progress.getString("content_id") ?: it.outputData.getString("content_id") 
                    }

                    for ((contentId, items) in grouped) {
                        if (contentId == null) continue

                        // Find the most relevant work info for this contentId
                        // Priority: RUNNING > ENQUEUED > SUCCEEDED > FAILED > CANCELLED
                        val activeWork = items.firstOrNull { it.state == WorkInfo.State.RUNNING }
                            ?: items.firstOrNull { it.state == WorkInfo.State.ENQUEUED }
                            ?: items.firstOrNull { it.state == WorkInfo.State.SUCCEEDED }
                            ?: items.firstOrNull { it.state == WorkInfo.State.FAILED }
                            ?: items.firstOrNull()

                        if (activeWork != null) {
                            val workInfo = activeWork
                            val state = when (workInfo.state) {
                                WorkInfo.State.RUNNING -> "RUNNING"
                                WorkInfo.State.SUCCEEDED -> "COMPLETED"
                                WorkInfo.State.FAILED -> "FAILED"
                                WorkInfo.State.ENQUEUED -> "PENDING"
                                WorkInfo.State.BLOCKED -> "PENDING"
                                WorkInfo.State.CANCELLED -> "CANCELLED"
                            }
                            
                            val src = if (workInfo.state == WorkInfo.State.SUCCEEDED) workInfo.outputData else workInfo.progress
                            val downloaded = src.getInt("downloadedCount", 0)
                            val total = src.getInt("totalCount", 0)
                            
                            // Speed Calculation logic
                            val currentBytes = src.getLong("downloadedBytes", 0L)
                            var downloadSpeed = 0.0
                            val currentTime = System.currentTimeMillis()

                            if (currentBytes > 0) {
                                val lastData = lastSpeedData[contentId]
                                if (lastData != null) {
                                    val (lastBytes, lastTime) = lastData
                                    val deltaBytes = currentBytes - lastBytes
                                    val deltaTime = currentTime - lastTime

                                    if (deltaTime > 0 && deltaBytes >= 0) {
                                        // Speed in bytes/second
                                        downloadSpeed = (deltaBytes * 1000.0) / deltaTime
                                    }
                                }
                                // Update cache
                                lastSpeedData[contentId] = Pair(currentBytes, currentTime)
                            }
                            
                            if (total > 0 || state == "COMPLETED" || state == "FAILED") {
                                // Calculate progress percentage for smarter deduplication
                                val progressPercent = if (total > 0) (downloaded * 100 / total) else 0
                                
                                // Create fingerprint using percentage tiers (5% intervals) for better deduplication
                                // This prevents flooding with events but ensures progress updates visible to user
                                val progressTier = (progressPercent / 5) * 5
                                val stateFingerprint = "$state:tier_$progressTier:$total"
                                val lastFingerprint = lastEmittedStates[contentId]

                                // FIX: Only emit terminal states ONCE per contentId to prevent spam
                                // Previously, COMPLETED was always emitted, causing spam when multiple downloads active
                                val isTerminalState = state == "COMPLETED" || state == "FAILED"
                                val alreadyEmittedTerminal = terminalStatesEmitted.contains(contentId)
                                val shouldEmit = when {
                                    isTerminalState && alreadyEmittedTerminal -> false  // Skip - already sent
                                    isTerminalState -> true  // First terminal state - emit it
                                    else -> stateFingerprint != lastFingerprint  // Normal dedup for progress
                                }

                                if (shouldEmit) {
                                val data = mapOf(
                                    "contentId" to contentId,
                                    "downloadedPages" to downloaded,
                                    "totalPages" to total,
                                    "status" to state,
                                    "downloadSpeed" to downloadSpeed,
                                    "failedPages" to (src.getString("failedPages") ?: "")
                                )
                                    
                                    if (eventSink != null) {
                                        eventSink?.success(data)
                                        lastEmittedStates[contentId] = stateFingerprint
                                        
                                        if (isTerminalState) {
                                            terminalStatesEmitted.add(contentId)
                                            Log.i(TAG, "✅ TERMINAL STATE emitted for $contentId: $state ($downloaded/$total) - tracking to prevent spam")
                                        } else {
                                            Log.d(TAG, "Progress update for $contentId: $progressPercent% ($downloaded/$total)")
                                        }
                                    } else {
                                        Log.w(TAG, "EventSink is null, cannot emit for $contentId")
                                    }
                                } else {
                                    // Log skipped updates only occasionally to avoid log spam
                                    if (progressPercent % 20 == 0) {
                                        Log.v(TAG, "Skipped duplicate for $contentId at $progressPercent%")
                                    }
                                }
                            }
                        }
                    }
                }
        }
    }

    private fun stopObservingProgress() {
        progressJob?.cancel()
    }

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "kuronNativeStartDownload" -> handleStartDownload(call, result)
            "kuronNativeCancelDownload" -> handleCancelDownload(call, result)
            "kuronNativePauseDownload" -> handlePauseDownload(call, result)
            "kuronNativeGetDownloadStatus" -> handleGetDownloadStatus(call, result)
            "kuronNativeGetDownloadedFiles" -> handleGetDownloadedFiles(call, result)
            "kuronNativeGetDownloadPath" -> handleGetDownloadPath(call, result)
            "kuronNativeDeleteDownloadedContent" -> handleDeleteDownloadedContent(call, result)
            "kuronNativeCountDownloadedFiles" -> handleCountDownloadedFiles(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleStartDownload(call: MethodCall, result: MethodChannel.Result) {
        try {
            val contentId = call.argument<String>("contentId")
                ?: throw IllegalArgumentException("contentId is required")
            
            // FIX: Clear terminal tracking for fresh download to allow re-downloading
            terminalStatesEmitted.remove(contentId)
            lastEmittedStates.remove(contentId)
            lastSpeedData.remove(contentId)
            trimTrackingMaps()
            val sourceId = call.argument<String>("sourceId") ?: "unknown"
            val imageUrls = call.argument<List<String>>("imageUrls")
                ?: throw IllegalArgumentException("imageUrls is required")
            val destinationPath = call.argument<String>("destinationPath")
                ?: throw IllegalArgumentException("destinationPath is required")
            
            @Suppress("UNCHECKED_CAST")
            val cookies = call.argument<Map<String, String>>("cookies")

            @Suppress("UNCHECKED_CAST")
            val headers = call.argument<Map<String, String>>("headers")
            
            // Extract metadata for v2.1
            val title = call.argument<String>("title") ?: "Unknown"
            val url = call.argument<String>("url") ?: ""
            val coverUrl = call.argument<String>("coverUrl") ?: ""
            val language = call.argument<String>("language") ?: "unknown"
            val startPage = call.argument<Int>("startPage") ?: 1
            val endPage = call.argument<Int>("endPage") ?: imageUrls.size
            val totalPages = call.argument<Int>("totalPages") ?: imageUrls.size
            // ✅ NEW: Extract backup folder name from Flutter (default: "nhasix")
            val backupFolderName = call.argument<String>("backupFolderName") ?: "nhasix"
            // Feature C: Parallel download config
            val maxParallelImages = call.argument<Int>("maxParallelImages") ?: 3
            val imageTimeoutMs = call.argument<Int>("imageTimeoutMs")?.toLong() ?: 60_000L

            val workId = downloadManager.queueDownload(
                contentId, 
                sourceId, 
                imageUrls, 
                destinationPath,
                cookies,
                headers,
                title,
                url,
                coverUrl,
                language,
                startPage,
                endPage,
                totalPages,
                backupFolderName,  // ✅ NEW: Pass to download manager
                maxParallelImages,
                imageTimeoutMs,
            )
            result.success(workId)
        } catch (e: Exception) {
            result.error("DOWNLOAD_ERROR", e.message, e.stackTraceToString())
        }
    }
    private fun trimTrackingMaps() {
        if (lastEmittedStates.size > 100) {
            val toRemove = lastEmittedStates.keys().toList().take(lastEmittedStates.size - 100)
            toRemove.forEach { lastEmittedStates.remove(it) }
        }
        if (terminalStatesEmitted.size > 100) {
            val toRemove = terminalStatesEmitted.toList().take(terminalStatesEmitted.size - 100)
            toRemove.forEach { terminalStatesEmitted.remove(it) }
        }
        if (lastSpeedData.size > 100) {
            val toRemove = lastSpeedData.keys().toList().take(lastSpeedData.size - 100)
            toRemove.forEach { lastSpeedData.remove(it) }
        }
    }

    private fun handleGetDownloadStatus(call: MethodCall, result: MethodChannel.Result) {
        val contentId = call.argument<String>("contentId")
        if (contentId == null) {
            result.error("INVALID_ARGUMENT", "contentId required", null)
            return
        }
        
        scope.launch(Dispatchers.IO) {
            val status = downloadManager.getDownloadStatus(contentId)
            launch(Dispatchers.Main) {
                result.success(status)
            }
        }
    }

    private fun handleCancelDownload(call: MethodCall, result: MethodChannel.Result) {
        val contentId = call.argument<String>("contentId")
        if (contentId == null) {
            result.error("INVALID_ARGUMENT", "contentId required", null)
            return
        }
        downloadManager.cancelDownload(contentId)
        result.success(null)
    }

    private fun handlePauseDownload(call: MethodCall, result: MethodChannel.Result) {
        val contentId = call.argument<String>("contentId")
        if (contentId == null) {
            result.error("INVALID_ARGUMENT", "contentId required", null)
            return
        }
        downloadManager.pauseDownload(contentId)
        result.success(null)
    }

    private fun handleGetDownloadedFiles(call: MethodCall, result: MethodChannel.Result) {
        val contentId = call.argument<String>("contentId")
        if (contentId == null) {
            result.error("INVALID_ARGUMENT", "contentId required", null)
            return
        }

        scope.launch(Dispatchers.IO) {
            try {
                val files = getDownloadedFilesList(contentId)
                launch(Dispatchers.Main) {
                    result.success(files)
                }
            } catch (e: Exception) {
                launch(Dispatchers.Main) {
                    result.error("GET_FILES_ERROR", e.message, null)
                }
            }
        }
    }

    private fun handleGetDownloadPath(call: MethodCall, result: MethodChannel.Result) {
        val contentId = call.argument<String>("contentId")
        if (contentId == null) {
            result.error("INVALID_ARGUMENT", "contentId required", null)
            return
        }

        scope.launch(Dispatchers.IO) {
            try {
                val path = getDownloadPathForContent(contentId)
                launch(Dispatchers.Main) {
                    result.success(path)
                }
            } catch (e: Exception) {
                launch(Dispatchers.Main) {
                    result.error("GET_PATH_ERROR", e.message, null)
                }
            }
        }
    }

    private fun handleDeleteDownloadedContent(call: MethodCall, result: MethodChannel.Result) {
        val contentId = call.argument<String>("contentId")
        val dirPath = call.argument<String>("dirPath")
        if (contentId == null) {
            result.error("INVALID_ARGUMENT", "contentId required", null)
            return
        }

        scope.launch(Dispatchers.IO) {
            try {
                deleteContent(contentId, dirPath)
                launch(Dispatchers.Main) {
                    result.success(null)
                }
            } catch (e: Exception) {
                launch(Dispatchers.Main) {
                    result.error("DELETE_ERROR", e.message, null)
                }
            }
        }
    }

    private fun handleCountDownloadedFiles(call: MethodCall, result: MethodChannel.Result) {
        val contentId = call.argument<String>("contentId")
        if (contentId == null) {
            result.error("INVALID_ARGUMENT", "contentId required", null)
            return
        }

        scope.launch(Dispatchers.IO) {
            try {
                val count = countFiles(contentId)
                launch(Dispatchers.Main) {
                    result.success(count)
                }
            } catch (e: Exception) {
                launch(Dispatchers.Main) {
                    result.error("COUNT_ERROR", e.message, null)
                }
            }
        }
    }

    // Helper Methods
    private fun getDownloadedFilesList(contentId: String): List<String> {
        val dir = getDownloadPathForContent(contentId) ?: return emptyList()
        val imagesDir = File(dir, "images")
        if (!imagesDir.exists()) return emptyList()

        return imagesDir.listFiles()?.filter { it.isFile && isSupportedImageFile(it) }
            ?.sortedBy { it.name }
            ?.map { it.absolutePath }
            ?: emptyList()
    }

    private fun isSupportedImageFile(file: File): Boolean {
        return when (file.extension.lowercase()) {
            "jpg", "jpeg", "png", "gif", "webp", "avif", "bmp" -> true
            else -> false
        }
    }

    private fun getDownloadPathForContent(contentId: String): String? {
        val candidates = mutableListOf<File>()

        // 1. Check Custom Storage Paths
        getCustomStoragePath()?.let { 
            candidates.add(File(it))
        }

        // 2. Check Public External Storage
        val publicDownloads = android.os.Environment.getExternalStoragePublicDirectory(
            android.os.Environment.DIRECTORY_DOWNLOADS
        )
        candidates.add(publicDownloads)

        Log.d(TAG, "Searching for contentId: $contentId in candidates: ${candidates.map { it.absolutePath }}")

        // Iterate candidates to find the content
        for (baseDir in candidates) {
            if (!baseDir.exists()) continue

            // Strategy A: Check "nhasix" subdirectory structure (Standard)
            // Structure: [Base]/nhasix/[SourceId]/[ContentId]
            val nhasixDir = File(baseDir, "nhasix")
            if (nhasixDir.exists()) {
                nhasixDir.listFiles()?.forEach { sourceDir ->
                    if (sourceDir.isDirectory) {
                        val contentDir = File(sourceDir, contentId)
                        if (contentDir.exists()) {
                            Log.d(TAG, "Found content at: ${contentDir.absolutePath}")
                            return contentDir.absolutePath
                        }
                    }
                }
                
                // Also check direct nhasix/[ContentId] (Legacy)
                val directNhasix = File(nhasixDir, contentId)
                if (directNhasix.exists()) {
                     Log.d(TAG, "Found content at (legacy nhasix): ${directNhasix.absolutePath}")
                     return directNhasix.absolutePath
                }
            }

            // Strategy B Check direct matches
            // Structure: [Base]/[ContentId] (Unlikely but possible legacy)
            val directFile = File(baseDir, contentId)
            if (directFile.exists()) {
                Log.d(TAG, "Found content at (direct): ${directFile.absolutePath}")
                return directFile.absolutePath
            }
        }
        
        Log.w(TAG, "ContentId $contentId NOT FOUND in any storage locations.")
        return null
    }

    private fun getCustomStoragePath(): String? {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        // Key match: Dart uses 'custom_storage_root', which becomes 'flutter.custom_storage_root'
        val path = prefs.getString("flutter.custom_storage_root", null)
        Log.d(TAG, "getCustomStoragePath: $path")
        return path
    }

    private fun deleteContent(contentId: String, explicitPath: String? = null) {
        var path = explicitPath
        if (path.isNullOrEmpty()) {
            path = getDownloadPathForContent(contentId)
        }

        if (path == null) {
            Log.e(TAG, "deleteContent: Path not found for $contentId")
            return
        }
        
        Log.d(TAG, "Deleting content at: $path")
        val dir = File(path)
        
        // Try deleting everything recursively
        try {
            val deleted = dir.deleteRecursively()
            Log.d(TAG, "deleteContent: result=$deleted for $path")
        } catch (e: Exception) {
             Log.e(TAG, "deleteContent: Exception deleting $path: ${e.message}")
        }
        
        // If dir still exists, try manual cleanup
        if (dir.exists()) {
             Log.w(TAG, "deleteContent: Directory still exists, trying manual cleanup")
             val imagesDir = File(dir, "images")
             if (imagesDir.exists()) imagesDir.deleteRecursively()
             File(dir, "metadata.json").delete()
             File(dir, ".nomedia").delete()
             dir.delete()
        }
    }

    private fun countFiles(contentId: String): Int {
        val files = getDownloadedFilesList(contentId)
        return files.size
    }

    fun dispose() {
        eventChannel.setStreamHandler(null)
        stopObservingProgress()
        scope.cancel() // prevent coroutine leaks
    }
}
