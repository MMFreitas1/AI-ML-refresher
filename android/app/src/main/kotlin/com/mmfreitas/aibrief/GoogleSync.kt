package com.mmfreitas.aibrief

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.Scope
import com.mmfreitas.aibrief.core.CollectionSyncer
import com.mmfreitas.aibrief.core.DriveAuthError
import com.mmfreitas.aibrief.core.DriveFile
import com.mmfreitas.aibrief.widget.BriefWidget
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.tasks.await
import java.time.Instant
import java.util.concurrent.TimeUnit

/**
 * Keeps the collection the same on every device signed in to the same Google account, through one
 * file in the user's Google Drive (see DriveFile). Only official builds have it (sync_available):
 * Google has to know the app's package name and signing key.
 *
 * Syncs when the app opens, a few seconds after each change (batched), and with the daily brief.
 */
object GoogleSync {
    sealed interface State {
        data object Off : State
        data object Syncing : State
        data class On(val email: String?, val lastSync: Instant?) : State
        /** Signed out by Google (password change, access removed): needs signing in again. */
        data class NeedsSignIn(val email: String?) : State
        data class Failed(val email: String?, val message: String) : State
    }

    private val _state = MutableStateFlow<State>(State.Off)
    val state: StateFlow<State> = _state
    private val mutex = Mutex()

    fun isAvailable(context: Context) = context.resources.getBoolean(R.bool.sync_available)

    private fun prefs(context: Context) = context.getSharedPreferences("sync", Context.MODE_PRIVATE)
    fun isOn(context: Context) = isAvailable(context) && prefs(context).getBoolean("on", false)
    private fun email(context: Context) = prefs(context).getString("email", null)
    private fun lastSync(context: Context) = prefs(context).getLong("lastSync", 0).takeIf { it > 0 }?.let(Instant::ofEpochSecond)

    /** Restores the state shown in Settings at launch. */
    fun load(context: Context) {
        _state.value = if (isOn(context)) State.On(email(context), lastSync(context)) else State.Off
    }

    private fun request() = AuthorizationRequest.builder().setRequestedScopes(listOf(Scope(DriveFile.SCOPE))).build()

    /**
     * Step 1 of "Sync with Google": asks Google for Drive access. Returns the consent screen to
     * show (the account picker and "Allow"), or null when access was already granted.
     */
    suspend fun begin(context: Context): PendingIntent? {
        val result = Identity.getAuthorizationClient(context).authorize(request()).await()
        if (result.hasResolution()) return result.pendingIntent
        finishSignIn(context, result)
        return null
    }

    /** Step 2: the consent screen's result. */
    suspend fun complete(context: Context, data: Intent?) {
        val result = Identity.getAuthorizationClient(context).getAuthorizationResultFromIntent(data)
        finishSignIn(context, result)
    }

    private suspend fun finishSignIn(context: Context, result: AuthorizationResult) {
        result.accessToken ?: error("Google didn't grant access")
        prefs(context).edit().putBoolean("on", true).apply()
        val email = runCatching { DriveFile { token(context) }.email() }.getOrNull()
        prefs(context).edit().putString("email", email).apply()
        sync(context)
    }

    fun signOut(context: Context) {
        prefs(context).edit().clear().apply()
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        _state.value = State.Off
    }

    /** A current access token without any UI (Google refreshes it as needed). */
    private suspend fun token(context: Context): String {
        val result = Identity.getAuthorizationClient(context).authorize(request()).await()
        if (result.hasResolution()) throw DriveAuthError("Google sign-in needed")
        return result.accessToken ?: throw DriveAuthError("Google sign-in needed")
    }

    /** Syncs now. Returns true when the local collection changed (reload what's on screen). */
    suspend fun sync(context: Context): Boolean = mutex.withLock {
        if (!isOn(context)) return false
        val email = email(context)
        _state.value = State.Syncing
        try {
            val outcome = CollectionSyncer(context.store, DriveFile { token(context) }).sync()
            val now = Instant.now()
            prefs(context).edit().putLong("lastSync", now.epochSecond).apply()
            _state.value = State.On(email, now)
            if (outcome.changedLocally) BriefWidget.updateAll(context)
            outcome.changedLocally
        } catch (e: DriveAuthError) {
            _state.value = State.NeedsSignIn(email)
            false
        } catch (e: Exception) {
            _state.value = State.Failed(email, e.message ?: "Sync failed")
            false
        }
    }

    private const val WORK_NAME = "collection-sync"

    /** After a change: syncs a few seconds later (so quick edits go up together) when online. */
    fun scheduleSoon(context: Context) {
        if (!isOn(context)) return
        val request = OneTimeWorkRequestBuilder<SyncWorker>()
            .setInitialDelay(5, TimeUnit.SECONDS)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.REPLACE, request)
    }
}

class SyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        GoogleSync.sync(applicationContext)
        return if (GoogleSync.state.value is GoogleSync.State.Failed) Result.retry() else Result.success()
    }
}
