package id.nhasix.app.download

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import id.nhasix.app.MainActivity
import id.nhasix.app.R

/**
 * Builds and posts Kuron mascot download notifications.
 *
 * Mascot name is strictly "Kuron" (never Kuro) in all user-visible copy.
 * Custom views come from res/layout/notification_kuron_*.xml.
 */
object KuronNotificationBuilder {

    const val CHANNEL_ID = "kuron_manga_downloads"
    private const val CHANNEL_NAME = "Manga Downloads"

    const val ACTION_PAUSE = "id.nhasix.app.ACTION_KURON_PAUSE"
    const val ACTION_RESUME = "id.nhasix.app.ACTION_KURON_RESUME"
    const val ACTION_CANCEL = "id.nhasix.app.ACTION_KURON_CANCEL"
    const val ACTION_PRIORITY = "id.nhasix.app.ACTION_KURON_PRIORITY"
    const val ACTION_PAUSE_ALL = "id.nhasix.app.ACTION_KURON_PAUSE_ALL"
    const val ACTION_CANCEL_ALL = "id.nhasix.app.ACTION_KURON_CANCEL_ALL"
    const val ACTION_VIEW_QUEUE = "id.nhasix.app.ACTION_KURON_VIEW_QUEUE"
    const val ACTION_OPEN = "id.nhasix.app.ACTION_KURON_OPEN"
    const val ACTION_DISMISS = "id.nhasix.app.ACTION_KURON_DISMISS"
    const val ACTION_CANCEL_PDF = "id.nhasix.app.ACTION_KURON_CANCEL_PDF"

    const val CHANNEL_ID_COMPLETE = "kuron_downloads_complete"
    private const val CHANNEL_NAME_COMPLETE = "Completed Downloads"

    const val EXTRA_NOTIFICATION_ID = "notificationId"
    const val EXTRA_CONTENT_ID = "contentId"

    private fun pendingFlags(): Int =
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

    private fun actionIntent(
        context: Context,
        action: String,
        notificationId: Int,
        contentId: String?,
    ): PendingIntent {
        val intent = Intent(context, NotificationActionReceiver::class.java)
            .setAction(action)
            .setPackage(context.packageName)
            .putExtra(EXTRA_NOTIFICATION_ID, notificationId)
        if (contentId != null) intent.putExtra(EXTRA_CONTENT_ID, contentId)
        val requestCode = (action.hashCode() * 31 + notificationId)
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            pendingFlags(),
        )
    }

    private fun contentIntent(context: Context, contentId: String?): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            if (contentId != null) putExtra(EXTRA_CONTENT_ID, contentId)
        }
        return PendingIntent.getActivity(context, 9001, intent, pendingFlags())
    }

    private fun str(data: Map<String, Any?>, key: String, fallback: String): String =
        (data[key] as? String) ?: fallback

    private fun int(data: Map<String, Any?>, key: String, fallback: Int): Int =
        when (val v = data[key]) {
            is Number -> v.toInt()
            is String -> v.toIntOrNull() ?: fallback
            else -> fallback
        }

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Kuron manga download progress"
                setSound(null, null)
                enableVibration(false)
                vibrationPattern = null
                enableLights(false)
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            }
            manager.createNotificationChannel(channel)
        }
        if (manager.getNotificationChannel(CHANNEL_ID_COMPLETE) == null) {
            val completeChannel = NotificationChannel(
                CHANNEL_ID_COMPLETE,
                CHANNEL_NAME_COMPLETE,
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Notifications for finished Kuron downloads"
                enableLights(true)
                setShowBadge(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(completeChannel)
        }
    }

    fun buildSingleExpanded(context: Context, data: Map<String, Any?>): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.notification_kuron_single_expanded)
        val progress = int(data, "progress", 0)
        val max = int(data, "max", 100).coerceAtLeast(1)
        val status = str(data, "status", "downloading").lowercase()
        val avatarRes = when {
            status == "paused" -> R.drawable.kuro_frozen_cry
            progress >= max -> R.drawable.kuro_happy
            else -> R.drawable.kuro_tsundere
        }
        views.setImageViewResource(R.id.kuro_avatar_img, avatarRes)
        views.setTextViewText(
            R.id.kuro_speech_txt,
            str(data, "speech", "🐾 Kuron: Packing your chapters~"),
        )
        views.setTextViewText(
            R.id.notif_title_txt,
            str(data, "title", "Downloading chapter"),
        )
        views.setProgressBar(R.id.notif_progress_bar, max, progress.coerceIn(0, max), false)
        views.setTextViewText(
            R.id.notif_meta_txt,
            str(data, "meta", "$progress/$max"),
        )
        val notificationId = int(data, "notificationId", 0)
        val contentId = data["contentId"] as? String
        // Nap button toggles: paused state offers resume, otherwise pause.
        val pauseOrResume = if (status == "paused") ACTION_RESUME else ACTION_PAUSE
        views.setOnClickPendingIntent(
            R.id.btn_pause,
            actionIntent(context, pauseOrResume, notificationId, contentId),
        )
        views.setOnClickPendingIntent(
            R.id.btn_cancel,
            actionIntent(context, ACTION_CANCEL, notificationId, contentId),
        )
        views.setOnClickPendingIntent(
            R.id.btn_priority,
            actionIntent(context, ACTION_PRIORITY, notificationId, contentId),
        )
        return views
    }

    fun buildSingleCollapsed(context: Context, data: Map<String, Any?>): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.notification_kuron_single_collapsed)
        val progress = int(data, "progress", 0)
        val max = int(data, "max", 100).coerceAtLeast(1)
        val status = str(data, "status", "downloading").lowercase()
        val avatarRes = when {
            status == "paused" -> R.drawable.kuro_frozen_cry
            progress >= max -> R.drawable.kuro_happy
            else -> R.drawable.kuro_tsundere
        }
        views.setImageViewResource(R.id.notif_mini_avatar, avatarRes)
        views.setTextViewText(
            R.id.notif_collapsed_title,
            str(data, "title", "Downloading chapter"),
        )
        views.setProgressBar(R.id.notif_collapsed_progress, max, progress.coerceIn(0, max), false)
        views.setTextViewText(
            R.id.notif_collapsed_meta,
            str(data, "meta", "$progress%"),
        )
        return views
    }

    fun buildBatchExpanded(context: Context, data: Map<String, Any?>): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.notification_kuron_batch_expanded)
        val progress = int(data, "progress", 0)
        val max = int(data, "max", 100).coerceAtLeast(1)
        val status = str(data, "status", "downloading").lowercase()
        val avatarRes = when {
            status == "paused" -> R.drawable.kuro_frozen_cry
            progress >= max -> R.drawable.kuro_happy
            else -> R.drawable.kuro_reader
        }
        views.setImageViewResource(R.id.batch_avatar_img, avatarRes)
        views.setTextViewText(
            R.id.batch_speech_txt,
            str(data, "speech", "🐾 Kuron: Packing the whole queue~"),
        )
        views.setTextViewText(
            R.id.batch_active_title,
            str(data, "activeTitle", str(data, "title", "Downloading queue")),
        )
        views.setProgressBar(R.id.batch_progress_bar, max, progress.coerceIn(0, max), false)
        views.setTextViewText(
            R.id.batch_queue_meta,
            str(data, "meta", "$progress/$max"),
        )
        views.setTextViewText(
            R.id.batch_up_next_txt,
            str(data, "upNext", ""),
        )
        val notificationId = int(data, "notificationId", 0)
        val contentId = data["contentId"] as? String
        views.setOnClickPendingIntent(
            R.id.btn_batch_pause,
            actionIntent(context, ACTION_PAUSE_ALL, notificationId, contentId),
        )
        views.setOnClickPendingIntent(
            R.id.btn_batch_cancel,
            actionIntent(context, ACTION_CANCEL_ALL, notificationId, contentId),
        )
        views.setOnClickPendingIntent(
            R.id.btn_batch_view_queue,
            actionIntent(context, ACTION_VIEW_QUEUE, notificationId, contentId),
        )
        return views
    }

    fun buildBatchCollapsed(context: Context, data: Map<String, Any?>): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.notification_kuron_batch_collapsed)
        val progress = int(data, "progress", 0)
        val max = int(data, "max", 100).coerceAtLeast(1)
        val status = str(data, "status", "downloading").lowercase()
        val avatarRes = when {
            status == "paused" -> R.drawable.kuro_frozen_cry
            progress >= max -> R.drawable.kuro_happy
            else -> R.drawable.kuro_reader
        }
        views.setImageViewResource(R.id.notif_batch_mini_icon, avatarRes)
        views.setTextViewText(
            R.id.notif_batch_collapsed_title,
            str(data, "title", "Downloading queue"),
        )
        views.setProgressBar(
            R.id.notif_batch_collapsed_progress,
            max,
            progress.coerceIn(0, max),
            false,
        )
        views.setTextViewText(
            R.id.notif_batch_collapsed_meta,
            str(data, "meta", "$progress%"),
        )
        return views
    }

    fun buildNotification(
        context: Context,
        data: Map<String, Any?>,
        isBatch: Boolean,
    ): Notification {
        ensureChannel(context)
        val contentId = data["contentId"] as? String
        val ongoing = (data["ongoing"] as? Boolean) ?: true
        val collapsed = if (isBatch) buildBatchCollapsed(context, data)
        else buildSingleCollapsed(context, data)
        val expanded = if (isBatch) buildBatchExpanded(context, data)
        else buildSingleExpanded(context, data)
        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification_kuron)
            .setCustomContentView(collapsed)
            .setCustomBigContentView(expanded)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setOngoing(ongoing)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setContentIntent(contentIntent(context, contentId))
            .build()
    }

    fun showOrUpdateNotification(
        context: Context,
        notificationId: Int,
        data: Map<String, Any?>,
        isBatch: Boolean,
    ) {
        val merged = data + mapOf("notificationId" to notificationId)
        val notification = buildNotification(context, merged, isBatch)
        NotificationManagerCompat.from(context).notify(notificationId, notification)
    }

    fun buildCompleteExpanded(context: Context, data: Map<String, Any?>): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.notification_kuron_complete_expanded)
        views.setImageViewResource(R.id.kuro_complete_avatar, R.drawable.kuro_happy)
        views.setTextViewText(
            R.id.kuro_complete_speech,
            str(data, "speech", "🐾 Kuron: Delivery arrived! Ready to read~ 🎉"),
        )
        views.setTextViewText(
            R.id.notif_complete_title,
            str(data, "title", "Download Complete"),
        )
        views.setTextViewText(
            R.id.notif_complete_meta,
            str(data, "meta", "All pages packed! • 100% Complete • Ready offline"),
        )
        val notificationId = int(data, "notificationId", 0)
        val contentId = data["contentId"] as? String
        views.setOnClickPendingIntent(
            R.id.btn_complete_dismiss,
            actionIntent(context, ACTION_DISMISS, notificationId, contentId),
        )
        views.setOnClickPendingIntent(
            R.id.btn_complete_read,
            actionIntent(context, ACTION_OPEN, notificationId, contentId),
        )
        return views
    }

    fun buildCompleteCollapsed(context: Context, data: Map<String, Any?>): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.notification_kuron_complete_collapsed)
        views.setImageViewResource(R.id.notif_complete_mini_avatar, R.drawable.kuro_happy)
        views.setTextViewText(
            R.id.notif_complete_collapsed_title,
            str(data, "title", "Download Complete"),
        )
        views.setTextViewText(
            R.id.notif_complete_collapsed_meta,
            str(data, "meta", "🐾 Kuron: All packed! Tap to read offline • 100%"),
        )
        return views
    }

    fun showCompleteNotification(
        context: Context,
        notificationId: Int,
        data: Map<String, Any?>,
    ) {
        ensureChannel(context)
        val merged = data + mapOf("notificationId" to notificationId)
        val contentId = data["contentId"] as? String
        val collapsed = buildCompleteCollapsed(context, merged)
        val expanded = buildCompleteExpanded(context, merged)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID_COMPLETE)
            .setSmallIcon(R.drawable.ic_notification_kuron)
            .setCustomContentView(collapsed)
            .setCustomBigContentView(expanded)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setOngoing(false)
            .setAutoCancel(true)
            .setShowWhen(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setContentIntent(contentIntent(context, contentId))
            .build()
        NotificationManagerCompat.from(context).notify(notificationId, notification)
    }

    // ─── PDF conversion mode (reuses single/complete layouts, no new XML) ───

    fun buildPdfExpanded(context: Context, data: Map<String, Any?>): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.notification_kuron_single_expanded)
        val progress = int(data, "progress", 0)
        val max = int(data, "max", 100).coerceAtLeast(1)
        val status = str(data, "status", "converting").lowercase()
        val avatarRes = when {
            status == "cancelled" || status == "canceled" -> R.drawable.kuro_frozen_cry
            progress >= max -> R.drawable.kuro_happy
            else -> R.drawable.kuro_tsundere
        }
        views.setImageViewResource(R.id.kuro_avatar_img, avatarRes)
        views.setTextViewText(
            R.id.kuro_speech_txt,
            str(data, "speech", "🐾 Kuron: Merangkai halaman jadi PDF..."),
        )
        views.setTextViewText(
            R.id.notif_title_txt,
            str(data, "title", "Converting to PDF"),
        )
        views.setProgressBar(R.id.notif_progress_bar, max, progress.coerceIn(0, max), false)
        views.setTextViewText(
            R.id.notif_meta_txt,
            str(data, "meta", "$progress%"),
        )
        val notificationId = int(data, "notificationId", 0)
        val contentId = data["contentId"] as? String
        // No pause for conversions: hide Nap, Cancel PDF aborts, Open PDF reads.
        views.setViewVisibility(R.id.btn_pause, android.view.View.GONE)
        views.setTextViewText(R.id.btn_cancel, "Cancel PDF")
        views.setOnClickPendingIntent(
            R.id.btn_cancel,
            actionIntent(context, ACTION_CANCEL_PDF, notificationId, contentId),
        )
        views.setTextViewText(R.id.btn_priority, "Open PDF")
        views.setOnClickPendingIntent(
            R.id.btn_priority,
            actionIntent(context, ACTION_OPEN, notificationId, contentId),
        )
        return views
    }

    fun buildPdfCollapsed(context: Context, data: Map<String, Any?>): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.notification_kuron_single_collapsed)
        val progress = int(data, "progress", 0)
        val max = int(data, "max", 100).coerceAtLeast(1)
        val status = str(data, "status", "converting").lowercase()
        val avatarRes = when {
            status == "cancelled" || status == "canceled" -> R.drawable.kuro_frozen_cry
            progress >= max -> R.drawable.kuro_happy
            else -> R.drawable.kuro_tsundere
        }
        views.setImageViewResource(R.id.notif_mini_avatar, avatarRes)
        views.setTextViewText(
            R.id.notif_collapsed_title,
            str(data, "title", "Converting to PDF"),
        )
        views.setProgressBar(R.id.notif_collapsed_progress, max, progress.coerceIn(0, max), false)
        views.setTextViewText(
            R.id.notif_collapsed_meta,
            str(data, "meta", "$progress%"),
        )
        return views
    }

    fun showOrUpdatePdfNotification(
        context: Context,
        notificationId: Int,
        data: Map<String, Any?>,
    ) {
        ensureChannel(context)
        val merged = data + mapOf("notificationId" to notificationId)
        val contentId = data["contentId"] as? String
        val ongoing = (data["ongoing"] as? Boolean) ?: true
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification_kuron)
            .setCustomContentView(buildPdfCollapsed(context, merged))
            .setCustomBigContentView(buildPdfExpanded(context, merged))
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setOngoing(ongoing)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setContentIntent(contentIntent(context, contentId))
            .build()
        NotificationManagerCompat.from(context).notify(notificationId, notification)
    }

    fun showPdfCompleteNotification(
        context: Context,
        notificationId: Int,
        data: Map<String, Any?>,
    ) {
        ensureChannel(context)
        val merged = data + mapOf(
            "notificationId" to notificationId,
            "speech" to str(data, "speech", "🐾 Kuron: PDF siap dibaca! Rapi & bersih ✨"),
        )
        val contentId = data["contentId"] as? String
        val notification = NotificationCompat.Builder(context, CHANNEL_ID_COMPLETE)
            .setSmallIcon(R.drawable.ic_notification_kuron)
            .setCustomContentView(buildCompleteCollapsed(context, merged))
            .setCustomBigContentView(buildCompleteExpanded(context, merged))
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setOngoing(false)
            .setAutoCancel(true)
            .setShowWhen(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setContentIntent(contentIntent(context, contentId))
            .build()
        NotificationManagerCompat.from(context).notify(notificationId, notification)
    }

    fun showPdfCancelledNotification(
        context: Context,
        notificationId: Int,
        data: Map<String, Any?>,
    ) {
        ensureChannel(context)
        val merged = data + mapOf(
            "notificationId" to notificationId,
            "speech" to str(data, "speech", "⚠️ PDF Cancelled"),
            "title" to str(data, "title", "PDF Cancelled"),
            "meta" to str(data, "meta", "Conversion cancelled • Nothing saved"),
        )
        val collapsed = RemoteViews(
            context.packageName,
            R.layout.notification_kuron_complete_collapsed,
        )
        collapsed.setImageViewResource(R.id.notif_complete_mini_avatar, R.drawable.kuro_frozen_cry)
        collapsed.setTextViewText(R.id.notif_complete_collapsed_title, str(merged, "title", "PDF Cancelled"))
        collapsed.setTextViewText(R.id.notif_complete_collapsed_meta, str(merged, "meta", ""))
        val expanded = RemoteViews(
            context.packageName,
            R.layout.notification_kuron_complete_expanded,
        )
        expanded.setImageViewResource(R.id.kuro_complete_avatar, R.drawable.kuro_frozen_cry)
        expanded.setTextViewText(R.id.kuro_complete_speech, str(merged, "speech", "⚠️ PDF Cancelled"))
        expanded.setTextViewText(R.id.notif_complete_title, str(merged, "title", "PDF Cancelled"))
        expanded.setTextViewText(R.id.notif_complete_meta, str(merged, "meta", ""))
        // No file to read: keep Close, drop the Read button.
        expanded.setViewVisibility(R.id.btn_complete_read, android.view.View.GONE)
        val contentId = data["contentId"] as? String
        expanded.setOnClickPendingIntent(
            R.id.btn_complete_dismiss,
            actionIntent(context, ACTION_DISMISS, notificationId, contentId),
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification_kuron)
            .setCustomContentView(collapsed)
            .setCustomBigContentView(expanded)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setOngoing(false)
            .setAutoCancel(true)
            .setShowWhen(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setContentIntent(contentIntent(context, contentId))
            .build()
        NotificationManagerCompat.from(context).notify(notificationId, notification)
    }

    fun cancelNotification(context: Context, notificationId: Int) {
        NotificationManagerCompat.from(context).cancel(notificationId)
    }
}
