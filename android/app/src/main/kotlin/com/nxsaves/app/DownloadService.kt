package com.nxsaves.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/**
 * Foreground service that keeps the process (and the yt-dlp child processes) alive while
 * downloads are queued or running, and shows their progress in a notification.
 */
class DownloadService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification(
            this,
            intent?.getStringExtra(EXTRA_TITLE) ?: "Downloading",
            intent?.getStringExtra(EXTRA_TEXT) ?: "",
            intent?.getIntExtra(EXTRA_PROGRESS, -1) ?: -1,
        )
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // Starting a foreground service can be refused (e.g. from the background on Android 12+).
            // Downloads still run while the app stays in memory; just don't crash.
            running = false
            stopSelf()
            return START_NOT_STICKY
        }
        acquireWakeLock()
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        // Android 15+ limits dataSync services to 6h per day; stop cleanly instead of crashing.
        running = false
        stopSelf()
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        running = false
        super.onDestroy()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "NxSaves:downloads").apply {
            setReferenceCounted(false)
            acquire(6 * 60 * 60 * 1000L)
        }
    }

    companion object {
        private const val CHANNEL_ID = "downloads"
        private const val NOTIFICATION_ID = 4242
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_PROGRESS = "progress"

        private const val MIN_RUN_MS = 2000L

        @Volatile private var running = false
        private var startedAt = 0L
        private var desiredActive = 0
        private val handler = Handler(Looper.getMainLooper())

        /** Starts, updates or stops the service. [active] = queued + running downloads. */
        fun setState(context: Context, active: Int, title: String, text: String, progress: Int) {
            desiredActive = active
            if (active <= 0) {
                if (!running) return
                // Stopping a service before it reached startForeground() crashes the app, so give
                // a just-started service a moment before stopping it.
                val wait = MIN_RUN_MS - (SystemClock.elapsedRealtime() - startedAt)
                if (wait > 0) {
                    handler.postDelayed({ if (desiredActive <= 0) setState(context, 0, "", "", -1) }, wait)
                    return
                }
                running = false
                context.stopService(Intent(context, DownloadService::class.java))
                return
            }
            if (!running) {
                ensureChannel(context)
                val intent = Intent(context, DownloadService::class.java)
                    .putExtra(EXTRA_TITLE, title)
                    .putExtra(EXTRA_TEXT, text)
                    .putExtra(EXTRA_PROGRESS, progress)
                try {
                    ContextCompat.startForegroundService(context, intent)
                    running = true
                    startedAt = SystemClock.elapsedRealtime()
                } catch (e: Exception) {
                    running = false
                }
                return
            }
            val manager = NotificationManagerCompat.from(context)
            if (manager.areNotificationsEnabled()) {
                try {
                    manager.notify(NOTIFICATION_ID, buildNotification(context, title, text, progress))
                } catch (e: SecurityException) {
                    // POST_NOTIFICATIONS denied: the service still runs, just without visible updates.
                }
            }
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < 26) return
            val manager = context.getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(CHANNEL_ID, "Downloads", NotificationManager.IMPORTANCE_LOW)
                channel.description = "Progress of active downloads"
                channel.setShowBadge(false)
                manager.createNotificationChannel(channel)
            }
        }

        private fun buildNotification(context: Context, title: String, text: String, progress: Int) =
            NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_download)
                .setContentTitle(title)
                .setContentText(text)
                .setOnlyAlertOnce(true)
                .setOngoing(true)
                .setSilent(true)
                .setCategory(NotificationCompat.CATEGORY_PROGRESS)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .setProgress(100, progress.coerceIn(0, 100), progress < 0)
                .setContentIntent(
                    PendingIntent.getActivity(
                        context,
                        0,
                        Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    ),
                )
                .build()
    }
}
