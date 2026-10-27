package com.mmfreitas.aibrief

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.mmfreitas.aibrief.core.BriefBuilder
import com.mmfreitas.aibrief.core.DailyBrief
import com.mmfreitas.aibrief.core.Schedule
import com.mmfreitas.aibrief.widget.BriefWidget
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.Duration
import java.time.Instant
import java.util.concurrent.TimeUnit

/**
 * Builds the brief once a day after 12:00, with the app closed.
 *
 * One WorkManager job, waiting for the next 12:00 and for a network connection. Each run schedules
 * the next one. WorkManager keeps the job across reboots, and runs it late (as soon as the phone
 * is on and online) if it was off at noon.
 */
object DailyRefresh {
    private const val WORK_NAME = "daily-refresh"
    private val mutex = Mutex()

    /** At app start, keeps the job that's already waiting (or running: the app process may have been
     *  started to run it). The worker itself passes [fromWorker] to queue the next day's run after it. */
    fun schedule(context: Context, fromWorker: Boolean = false) {
        val now = Instant.now()
        val next = if (!fromWorker && Schedule.isDue(now, context.store.availableDays().firstOrNull())) now else Schedule.nextRefresh(now)
        val request = OneTimeWorkRequestBuilder<RefreshWorker>()
            .setInitialDelay(Duration.between(now, next).toMillis().coerceAtLeast(0), TimeUnit.MILLISECONDS)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        val policy = if (fromWorker) ExistingWorkPolicy.APPEND_OR_REPLACE else ExistingWorkPolicy.KEEP
        WorkManager.getInstance(context).enqueueUniqueWork(WORK_NAME, policy, request)
    }

    /** Builds today's brief now. Used by the worker and by the app's refresh button; one at a time. */
    suspend fun run(context: Context): DailyBrief = mutex.withLock {
        val brief = BriefBuilder().run(context.store)
        BriefWidget.updateAll(context)
        brief
    }
}

class RefreshWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val store = applicationContext.store
        if (Schedule.isDue(Instant.now(), store.availableDays().firstOrNull())) {
            val brief = DailyRefresh.run(applicationContext)
            // Nothing fetched (offline or every source failing): try again shortly.
            if (brief.items.isEmpty()) return Result.retry()
            Notifier.briefReady(applicationContext)
        }
        GoogleSync.sync(applicationContext)
        DailyRefresh.schedule(applicationContext, fromWorker = true)
        return Result.success()
    }
}

/** The daily "new brief" notification: opt-in from the bell button. Tapping it opens the app. */
object Notifier {
    const val CHANNEL_ID = "daily-brief"
    private const val NOTIFICATION_ID = 1

    fun isPermitted(context: Context) =
        android.os.Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    fun briefReady(context: Context) {
        if (AppSettings(context).notifications) show(context)
    }

    fun show(context: Context) {
        if (!isPermitted(context)) return
        val open = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Most recent AI & ML trends for you")
            .setContentText("Today's top picks are ready in ${context.getString(R.string.app_name)}.")
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // Permission revoked between the check and the call.
        }
    }
}
