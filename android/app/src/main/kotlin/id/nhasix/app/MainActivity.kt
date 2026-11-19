package id.nhasix.app

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import id.nhasix.app.download.KuronNotificationBuilder
import id.nhasix.app.widget.KuroStreakGlanceWidget
import id.nhasix.app.widget.StreakWidgetWorker

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "app_disguise"
    private val NAVIGATION_CHANNEL = "app.navigation"
    private val KURON_NOTIFICATION_CHANNEL = "id.nhasix.app/kuron_notification"

    companion object {
        @Volatile
        private var kuronNotificationChannel: MethodChannel? = null
        @Volatile
        private var pendingNotificationAction: Map<String, Any?>? = null

        @JvmStatic
        fun sendNotificationAction(action: String, contentId: String?, notificationId: Int) {
            val channel = kuronNotificationChannel
            val args = mapOf(
                "action" to action,
                "contentId" to contentId,
                "notificationId" to notificationId,
            )
            if (channel == null) {
                Log.w("KuronNotif", "No Flutter channel yet; caching pending action=$action contentId=$contentId")
                pendingNotificationAction = args
                return
            }
            try {
                channel.invokeMethod("onNotificationAction", args)
            } catch (e: Exception) {
                Log.e("KuronNotif", "Failed to forward notification action", e)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // FIX: Plant Timber for logging
        Log.d("AppDisguise", "MainActivity onCreate called")
        Log.d("AppDisguise", "Intent action: ${intent?.action}")
        Log.d("AppDisguise", "Component: ${intent?.component}")
        configureRecentsPrivacy()
        
        // Check for notification tap intent
        handleNotificationIntent(intent)
        
        // Keep the launcher streak widget fresh (hourly worker + refresh on app close)
        StreakWidgetWorker.enqueuePeriodic(this)
    }

    override fun onResume() {
        super.onResume()
        configureRecentsPrivacy()
    }
    
    override fun onStop() {
        super.onStop()
        KuroStreakGlanceWidget.updateAllWidgets(applicationContext)
    }
    
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleNotificationIntent(intent)
    }
    
    private fun handleNotificationIntent(intent: Intent?) {
        val route = intent?.getStringExtra("route")
        val contentId = intent?.getStringExtra("contentId")
            ?: intent?.getStringExtra(KuronNotificationBuilder.EXTRA_CONTENT_ID)
        
        if (contentId != null) {
            Log.d("Navigation", "Notification tapped with contentId: $contentId")
            sendNotificationAction(KuronNotificationBuilder.ACTION_OPEN, contentId, 0)
        } else if (route != null) {
            Log.d("Navigation", "Notification tapped - route: $route, contentId: $contentId")
            // Flutter will handle this via MethodChannel callback
        }
    }
    
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d("AppDisguise", "configureFlutterEngine called")

        // Setup App Disguise Channel
        try {
            val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            Log.d("AppDisguise", "MethodChannel created successfully")

            methodChannel.setMethodCallHandler { call, result ->
                Log.d("AppDisguise", "Received method call: ${call.method}")
                try {
                    when (call.method) {
                        "setDisguiseMode" -> {
                            val mode = call.argument<String>("mode")
                            Log.d("AppDisguise", "Setting disguise mode to: $mode")

                            if (mode != null) {
                                setAppDisguise(mode)
                                result.success("Mode set to: $mode")
                                Log.d("AppDisguise", "setDisguiseMode completed for mode: $mode")
                            } else {
                                result.error("INVALID_MODE", "Mode cannot be null", null)
                            }
                        }
                        "getCurrentDisguiseMode" -> {
                            Log.d("AppDisguise", "getCurrentDisguiseMode called")
                            val currentMode = getCurrentDisguise()
                            Log.d("AppDisguise", "Returning current disguise mode: $currentMode")
                            result.success(currentMode)
                        }
                        else -> {
                            Log.w("AppDisguise", "Unknown method: ${call.method}")
                            result.notImplemented()
                        }
                    }
                } catch (e: Exception) {
                    Log.e("AppDisguise", "Error processing method call", e)
                    result.error("METHOD_ERROR", e.message, null)
                }
            }
            Log.d("AppDisguise", "MethodChannel handler setup completed successfully")
        } catch (e: Exception) {
            Log.e("AppDisguise", "Error setting up MethodChannel (AppDisguise)", e)
        }

        // Setup Kuron Download Notification Channel
        try {
            val kuronChannel =
                MethodChannel(flutterEngine.dartExecutor.binaryMessenger, KURON_NOTIFICATION_CHANNEL)
            kuronNotificationChannel = kuronChannel
            pendingNotificationAction?.let { pending ->
                Log.i("KuronNotif", "Flushing pending notification action: $pending")
                kuronChannel.invokeMethod("onNotificationAction", pending)
                pendingNotificationAction = null
            }
            kuronChannel.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "updateSingleDownload", "showNotification", "updateProgress" -> {
                            val rawMap = (call.arguments as? Map<*, *>) ?: emptyMap<String, Any?>()
                            @Suppress("UNCHECKED_CAST")
                            val data = ((call.argument<Map<String, Any?>>("data")) ?: (rawMap as Map<String, Any?>))
                            val id = ((data["notificationId"] as? Number)?.toInt()
                                ?: call.argument<Int>("notificationId")
                                ?: call.argument<Long>("notificationId")?.toInt()
                                ?: 0)
                            val isBatch = call.argument<Boolean>("isBatch") ?: false
                            KuronNotificationBuilder.showOrUpdateNotification(
                                this, id, data, isBatch,
                            )
                            result.success(null)
                        }
                        "updateBatchDownload" -> {
                            val rawMap = (call.arguments as? Map<*, *>) ?: emptyMap<String, Any?>()
                            @Suppress("UNCHECKED_CAST")
                            val data = ((call.argument<Map<String, Any?>>("data")) ?: (rawMap as Map<String, Any?>))
                            val id = ((data["notificationId"] as? Number)?.toInt()
                                ?: call.argument<Int>("notificationId")
                                ?: call.argument<Long>("notificationId")?.toInt()
                                ?: 0)
                            KuronNotificationBuilder.showOrUpdateNotification(
                                this, id, data, true,
                            )
                            result.success(null)
                        }
                        "showCompleteNotification", "showDownloadCompleted" -> {
                            val rawMap = (call.arguments as? Map<*, *>) ?: emptyMap<String, Any?>()
                            @Suppress("UNCHECKED_CAST")
                            val data = ((call.argument<Map<String, Any?>>("data")) ?: (rawMap as Map<String, Any?>))
                            val id = ((data["notificationId"] as? Number)?.toInt()
                                ?: call.argument<Int>("notificationId")
                                ?: call.argument<Long>("notificationId")?.toInt()
                                ?: 0)
                            KuronNotificationBuilder.showCompleteNotification(
                                this, id, data,
                            )
                            result.success(null)
                        }
                        "updatePdfDownload", "showPdfNotification" -> {
                            val rawMap = (call.arguments as? Map<*, *>) ?: emptyMap<String, Any?>()
                            @Suppress("UNCHECKED_CAST")
                            val data = ((call.argument<Map<String, Any?>>("data")) ?: (rawMap as Map<String, Any?>))
                            val id = ((data["notificationId"] as? Number)?.toInt()
                                ?: call.argument<Int>("notificationId")
                                ?: call.argument<Long>("notificationId")?.toInt()
                                ?: 0)
                            KuronNotificationBuilder.showOrUpdatePdfNotification(
                                this, id, data,
                            )
                            result.success(null)
                        }
                        "showPdfCompleted" -> {
                            val rawMap = (call.arguments as? Map<*, *>) ?: emptyMap<String, Any?>()
                            @Suppress("UNCHECKED_CAST")
                            val data = ((call.argument<Map<String, Any?>>("data")) ?: (rawMap as Map<String, Any?>))
                            val id = ((data["notificationId"] as? Number)?.toInt()
                                ?: call.argument<Int>("notificationId")
                                ?: call.argument<Long>("notificationId")?.toInt()
                                ?: 0)
                            KuronNotificationBuilder.showPdfCompleteNotification(
                                this, id, data,
                            )
                            result.success(null)
                        }
                        "showPdfCancelled" -> {
                            val rawMap = (call.arguments as? Map<*, *>) ?: emptyMap<String, Any?>()
                            @Suppress("UNCHECKED_CAST")
                            val data = ((call.argument<Map<String, Any?>>("data")) ?: (rawMap as Map<String, Any?>))
                            val id = ((data["notificationId"] as? Number)?.toInt()
                                ?: call.argument<Int>("notificationId")
                                ?: call.argument<Long>("notificationId")?.toInt()
                                ?: 0)
                            KuronNotificationBuilder.showPdfCancelledNotification(
                                this, id, data,
                            )
                            result.success(null)
                        }
                        "cancel", "cancelNotification" -> {
                            val rawMap = (call.arguments as? Map<*, *>) ?: emptyMap<String, Any?>()
                            val id = ((rawMap["id"] as? Number)?.toInt()
                                ?: (rawMap["notificationId"] as? Number)?.toInt()
                                ?: call.argument<Int>("notificationId")
                                ?: call.argument<Long>("notificationId")?.toInt()
                                ?: 0)
                            KuronNotificationBuilder.cancelNotification(this, id)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    Log.e("KuronNotif", "Error processing ${call.method}", e)
                    result.error("KURON_NOTIF_ERROR", e.message, null)
                }
            }
            Log.d("KuronNotif", "Kuron notification channel ready")
        } catch (e: Exception) {
            Log.e("KuronNotif", "Error setting up Kuron notification channel", e)
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
    }

    private fun configureRecentsPrivacy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            setRecentsScreenshotEnabled(false)
            Log.d("MainActivity", "Recent-app screenshots disabled (API 33+ native fallback active)")
        } else {
            Log.d("MainActivity", "Recent-app screenshots use Flutter blur fallback on API < 33")
        }
    }

    private fun setAppDisguise(mode: String) {
        try {
            Log.d("AppDisguise", "setAppDisguise called with mode: $mode")

            // Disable all aliases first
            val aliases = listOf("CalculatorActivity", "NotesActivity", "WeatherActivity")
            aliases.forEach { alias ->
                try {
                    val componentName = ComponentName(packageName, "id.nhasix.app.$alias")
                    packageManager.setComponentEnabledSetting(
                        componentName,
                        PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                        PackageManager.DONT_KILL_APP
                    )
                    Log.d("AppDisguise", "Disabled alias: $alias")
                } catch (e: Exception) {
                    Log.e("AppDisguise", "Error disabling alias $alias", e)
                }
            }

            // Handle main activity and selected alias
            when (mode) {
                "calculator" -> {
                    disableMainActivity()
                    enableAlias("CalculatorActivity")
                }
                "notes" -> {
                    disableMainActivity()
                    enableAlias("NotesActivity")
                }
                "weather" -> {
                    disableMainActivity()
                    enableAlias("WeatherActivity")
                }
                else -> {
                    // Default mode - enable main activity
                    enableMainActivity()
                    Log.d("AppDisguise", "Default mode - main activity enabled")
                }
            }
        } catch (e: Exception) {
            Log.e("AppDisguise", "Error in setAppDisguise", e)
        }
    }

    private fun disableMainActivity() {
        try {
            val mainComponent = ComponentName(packageName, "id.nhasix.app.MainActivity")
            packageManager.setComponentEnabledSetting(
                mainComponent,
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP
            )
            Log.d("AppDisguise", "Disabled main activity")
        } catch (e: Exception) {
            Log.e("AppDisguise", "Error disabling main activity", e)
        }
    }

    private fun enableMainActivity() {
        try {
            val mainComponent = ComponentName(packageName, "id.nhasix.app.MainActivity")
            packageManager.setComponentEnabledSetting(
                mainComponent,
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP
            )
            Log.d("AppDisguise", "Enabled main activity")
        } catch (e: Exception) {
            Log.e("AppDisguise", "Error enabling main activity", e)
        }
    }
    
    private fun enableAlias(aliasName: String) {
        try {
            val componentName = ComponentName(packageName, "id.nhasix.app.$aliasName")
            packageManager.setComponentEnabledSetting(
                componentName,
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP
            )
            Log.d("AppDisguise", "Enabled alias: $aliasName")
        } catch (e: Exception) {
            Log.e("AppDisguise", "Error enabling alias $aliasName", e)
        }
    }
    
    private fun getCurrentDisguise(): String {
        Log.d("AppDisguise", "getCurrentDisguise called")

        // Check aliases first
        val aliases = listOf("CalculatorActivity", "NotesActivity", "WeatherActivity")
        for (alias in aliases) {
            try {
                val componentName = ComponentName(packageName, "id.nhasix.app.$alias")
                val state = packageManager.getComponentEnabledSetting(componentName)
                if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
                    val mode = when (alias) {
                        "CalculatorActivity" -> "calculator"
                        "NotesActivity" -> "notes"
                        "WeatherActivity" -> "weather"
                        else -> "default"
                    }
                    Log.d("AppDisguise", "Current disguise mode: $mode")
                    return mode
                }
            } catch (e: Exception) {
                Log.e("AppDisguise", "Error checking alias $alias", e)
            }
        }

        // Default
        return "default"
    }
}
