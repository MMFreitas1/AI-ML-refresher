package com.mmfreitas.aibrief

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import com.mmfreitas.aibrief.core.BriefStore
import java.io.File

class RefresherApp : Application() {
    override fun onCreate() {
        super.onCreate()
        val channel = NotificationChannel(Notifier.CHANNEL_ID, getString(R.string.channel_name), NotificationManager.IMPORTANCE_DEFAULT)
            .apply { description = getString(R.string.channel_description) }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        DailyRefresh.schedule(this)
        GoogleSync.load(this)
    }
}

/** Same files as the other apps (briefs/<day>.json, collection.json), in the app's private storage. */
val Context.store: BriefStore get() = stores.getOrPut(filesDir.path) { BriefStore(File(filesDir, "Refresher")) }
private val stores = mutableMapOf<String, BriefStore>()

/** App preferences. */
class AppSettings(context: Context) {
    private val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    /** The daily "brief is ready" notification. Opt-in, from the bell button. */
    var notifications: Boolean
        get() = prefs.getBoolean("notifications", false)
        set(value) = prefs.edit().putBoolean("notifications", value).apply()

    var askedNotificationPermission: Boolean
        get() = prefs.getBoolean("askedNotificationPermission", false)
        set(value) = prefs.edit().putBoolean("askedNotificationPermission", value).apply()

    /** The brand's launch intro (branded builds only). It plays on launch, not when returning to the app. */
    var playIntro: Boolean
        get() = prefs.getBoolean("playIntro", true)
        set(value) = prefs.edit().putBoolean("playIntro", value).apply()
}
