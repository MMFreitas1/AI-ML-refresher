package com.mmfreitas.aibrief.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.mmfreitas.aibrief.BriefViewModel
import com.mmfreitas.aibrief.GoogleSync.State
import kotlinx.coroutines.delay
import java.time.Duration
import java.time.Instant

/** What Settings needs from the activity for "Sync with Google". */
class SyncActions(val available: Boolean, val error: String?, val signIn: () -> Unit, val signOut: () -> Unit)

/** Settings → Sync: sign in once per device, with the same Google account, to share the collection. */
@Composable
fun SyncSection(model: BriefViewModel, sync: SyncActions) {
    val state by model.syncState.collectAsState()
    // Re-render every minute so "synced 3 min ago" stays true.
    var tick by remember { mutableStateOf(0) }
    LaunchedEffect(Unit) { while (true) { delay(60_000); tick++ } }

    Column(Modifier.padding(horizontal = 16.dp, vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("Sync", style = MaterialTheme.typography.titleSmall)
        when (val s = state) {
            State.Off -> {
                Text(
                    "Keep your collection the same on your phone, Mac and PC. Sign in with the same Google account on each one.",
                    style = MaterialTheme.typography.bodySmall,
                )
                Button(onClick = sync.signIn) { Text("Sync with Google") }
            }
            else -> {
                val email = when (s) {
                    is State.On -> s.email
                    is State.NeedsSignIn -> s.email
                    is State.Failed -> s.email
                    else -> null
                }
                val status = when (s) {
                    State.Syncing -> "Syncing…"
                    is State.On -> "Synced ${ago(s.lastSync, tick)}"
                    is State.NeedsSignIn -> "Google signed you out. Sign in again to keep syncing."
                    is State.Failed -> "Last sync failed: ${s.message}"
                    else -> ""
                }
                if (email != null) Text(email, style = MaterialTheme.typography.bodyMedium)
                Text(
                    status, style = MaterialTheme.typography.bodySmall,
                    color = if (s is State.Failed || s is State.NeedsSignIn) MaterialTheme.colorScheme.error
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (s is State.NeedsSignIn) Button(onClick = sync.signIn) { Text("Sign in") }
                    else TextButton(onClick = model::syncNow, enabled = s != State.Syncing) { Text("Sync now") }
                    TextButton(onClick = sync.signOut) { Text("Stop syncing") }
                }
            }
        }
        sync.error?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error) }
        HorizontalDivider(Modifier.padding(top = 4.dp))
    }
}

@Suppress("UNUSED_PARAMETER")
private fun ago(at: Instant?, tick: Int): String {
    if (at == null) return ""
    val minutes = Duration.between(at, Instant.now()).toMinutes()
    return when {
        minutes < 1 -> "just now"
        minutes < 60 -> "$minutes min ago"
        minutes < 24 * 60 -> "${minutes / 60} h ago"
        else -> "${minutes / (24 * 60)} days ago"
    }
}
