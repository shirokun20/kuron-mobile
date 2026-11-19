package id.nhasix.app.download

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import id.nhasix.app.MainActivity

/**
 * Receives Kuron download notification button taps and forwards them
 * to Flutter via the "id.nhasix.app/kuron_notification" MethodChannel.
 */
class NotificationActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val contentId = intent.getStringExtra(KuronNotificationBuilder.EXTRA_CONTENT_ID)
        val notificationId = intent.getIntExtra(
            KuronNotificationBuilder.EXTRA_NOTIFICATION_ID,
            0,
        )
        Log.d(TAG, "Notification action: $action contentId=$contentId id=$notificationId")

        when (action) {
            KuronNotificationBuilder.ACTION_PAUSE,
            KuronNotificationBuilder.ACTION_RESUME,
            KuronNotificationBuilder.ACTION_CANCEL,
            KuronNotificationBuilder.ACTION_PRIORITY,
            KuronNotificationBuilder.ACTION_PAUSE_ALL,
            KuronNotificationBuilder.ACTION_CANCEL_ALL,
            KuronNotificationBuilder.ACTION_VIEW_QUEUE,
            KuronNotificationBuilder.ACTION_CANCEL_PDF,
            -> MainActivity.sendNotificationAction(action, contentId, notificationId)
            KuronNotificationBuilder.ACTION_DISMISS -> {
                KuronNotificationBuilder.cancelNotification(context, notificationId)
            }
            KuronNotificationBuilder.ACTION_OPEN -> {
                KuronNotificationBuilder.cancelNotification(context, notificationId)
                val launchIntent = Intent(context, MainActivity::class.java).apply {
                    setAction(Intent.ACTION_MAIN)
                    addCategory(Intent.CATEGORY_LAUNCHER)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    if (contentId != null) putExtra("contentId", contentId)
                }
                context.startActivity(launchIntent)
                MainActivity.sendNotificationAction(action, contentId, notificationId)
            }
            else -> Log.w(TAG, "Unknown notification action: $action")
        }
    }

    companion object {
        private const val TAG = "KuronNotifAction"
    }
}
