package com.mmfreitas.aibrief

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import androidx.activity.viewModels
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.mmfreitas.aibrief.ui.MainScreen
import com.mmfreitas.aibrief.ui.RefresherTheme
import com.mmfreitas.aibrief.ui.SyncActions

class MainActivity : ComponentActivity() {
    private val model: BriefViewModel by viewModels()

    /** Mirrors the setting and the system permission, for the bell button. */
    private val notificationsOn = mutableStateOf(false)

    private val askPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        model.settings.notifications = granted
        refreshNotificationState()
    }

    /** Google's account picker and "Allow" screen, for "Sync with Google". */
    private val googleConsent = registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { result ->
        lifecycleScope.launch {
            try {
                GoogleSync.complete(this@MainActivity, result.data)
                model.syncedAfterSignIn()
            } catch (e: Exception) {
                syncError.value = if (result.resultCode == RESULT_CANCELED) null else "Couldn't sign in: ${e.message}"
            }
        }
    }

    /** Sign-in problems, shown in Settings. */
    private val syncError = mutableStateOf<String?>(null)

    private fun signInToGoogle() {
        syncError.value = null
        lifecycleScope.launch {
            try {
                val consent = GoogleSync.begin(this@MainActivity)
                if (consent != null) googleConsent.launch(IntentSenderRequest.Builder(consent).build())
                else model.syncedAfterSignIn()
            } catch (e: Exception) {
                syncError.value = "Couldn't sign in: ${e.message}"
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // The intro plays on launch, not when the activity is recreated (rotation, dark mode switch).
        val playIntro = savedInstanceState == null && AppBrand.hasIntro && model.settings.playIntro
        setContent {
            RefresherTheme {
                var introDone by rememberSaveable { mutableStateOf(!playIntro) }
                LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
                    model.onResume()
                    refreshNotificationState()
                }
                if (!introDone) {
                    AppBrand.Intro(isReady = { model.brief != null || !model.isRefreshing }, onFinish = { introDone = true })
                } else {
                    MainScreen(
                        model = model,
                        notificationsOn = notificationsOn.value,
                        onToggleNotifications = ::toggleNotifications,
                        onTestNotification = { Notifier.show(this) },
                        sync = SyncActions(
                            available = GoogleSync.isAvailable(this),
                            error = syncError.value,
                            signIn = ::signInToGoogle,
                            signOut = { GoogleSync.signOut(this) },
                        ),
                    )
                }
            }
        }
    }

    private fun refreshNotificationState() {
        notificationsOn.value = model.settings.notifications && Notifier.isPermitted(this)
    }

    /** The bell button. Turning it on asks for the system permission when needed (Android 13+). */
    private fun toggleNotifications() {
        if (notificationsOn.value) {
            model.settings.notifications = false
        } else if (Notifier.isPermitted(this)) {
            model.settings.notifications = true
        } else if (model.settings.askedNotificationPermission &&
            !shouldShowRequestPermissionRationale(android.Manifest.permission.POST_NOTIFICATIONS)) {
            // Denied before: Android won't ask again, the switch is in the app's system settings.
            model.settings.notifications = true
            startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
            return
        } else {
            model.settings.askedNotificationPermission = true
            askPermission.launch(android.Manifest.permission.POST_NOTIFICATIONS)
            return
        }
        refreshNotificationState()
    }
}
