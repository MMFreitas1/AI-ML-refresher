package com.mmfreitas.aibrief.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.ui.graphics.Color
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.mmfreitas.aibrief.AppBrand
import com.mmfreitas.aibrief.BriefViewModel
import com.mmfreitas.aibrief.BuildConfigInfo
import com.mmfreitas.aibrief.R
import com.mmfreitas.aibrief.widget.BriefWidget

/**
 * Today's brief and the collection. Side by side on tablets and unfolded foldables (like the
 * desktop apps' two panes), as two tabs on phones.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(
    model: BriefViewModel,
    notificationsOn: Boolean,
    onToggleNotifications: () -> Unit,
    onTestNotification: () -> Unit,
    sync: SyncActions,
) {
    var tab by rememberSaveable { mutableStateOf(0) }
    var menu by remember { mutableStateOf(false) }
    var showSettings by rememberSaveable { mutableStateOf(false) }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val wide = maxWidth >= 840.dp
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(stringResource(R.string.app_name)) },
                    actions = {
                        if (model.isRefreshing) {
                            Box(Modifier.padding(12.dp)) { CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp) }
                        } else {
                            IconButton(onClick = model::refresh) { Icon(Icons.Filled.Refresh, "Refresh now") }
                        }
                        IconButton(onClick = onToggleNotifications) {
                            Icon(
                                if (notificationsOn) Icons.Filled.Notifications else Icons.Outlined.Notifications,
                                if (notificationsOn) "Turn off daily notification" else "Notify me when the daily brief is ready",
                                tint = if (notificationsOn) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Box {
                            IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreVert, "More") }
                            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                                DropdownMenuItem(text = { Text("Settings") }, onClick = { menu = false; showSettings = true })
                            }
                        }
                    },
                )
            },
            bottomBar = {
                if (!wide) NavigationBar {
                    NavigationBarItem(
                        selected = tab == 0, onClick = { tab = 0 },
                        icon = { Icon(painterResource(R.drawable.ic_notification), null) },
                        label = { Text(model.dayTitle) },
                    )
                    NavigationBarItem(
                        selected = tab == 1, onClick = { tab = 1 },
                        icon = {
                            BadgedBox(badge = { if (model.collection.isNotEmpty()) Badge { Text("${model.collection.size}") } }) {
                                Icon(painterResource(R.drawable.ic_bookmark), null)
                            }
                        },
                        label = { Text("Collection") },
                    )
                }
            },
        ) { padding ->
            val modifier = Modifier.padding(padding).fillMaxSize()
            if (wide) {
                Row(modifier) {
                    TodayPane(model, Modifier.weight(1f).fillMaxHeight())
                    VerticalDivider()
                    CollectionPane(model, Modifier.weight(1f).fillMaxHeight())
                }
            } else {
                Column(modifier) {
                    if (tab == 0) TodayPane(model, Modifier.fillMaxSize())
                    else CollectionPane(model, Modifier.fillMaxSize())
                }
            }
        }
    }

    if (showSettings) SettingsDialog(model, notificationsOn, onToggleNotifications, onTestNotification, sync) { showSettings = false }
}

@Composable
private fun SettingsDialog(
    model: BriefViewModel,
    notificationsOn: Boolean,
    onToggleNotifications: () -> Unit,
    onTestNotification: () -> Unit,
    sync: SyncActions,
    onDismiss: () -> Unit,
) {
    var playIntro by remember { mutableStateOf(model.settings.playIntro) }
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = { TextButton(onClick = onDismiss) { Text("Done") } },
        title = { Text("Settings") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                if (sync.available) SyncSection(model, sync)
                ListItem(
                    headlineContent = { Text("Daily notification") },
                    supportingContent = { Text("When the brief is ready, after 12:00") },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    trailingContent = { Switch(checked = notificationsOn, onCheckedChange = { onToggleNotifications() }) },
                )
                if (notificationsOn) TextButton(onClick = onTestNotification) { Text("Send a test notification") }
                val context = LocalContext.current
                if (BriefWidget.canPin(context)) TextButton(onClick = { BriefWidget.requestPin(context) }) {
                    Text("Add widget to home screen")
                }
                if (AppBrand.hasIntro) ListItem(
                    headlineContent = { Text("Launch intro") },
                    supportingContent = { Text("Plays when the app starts") },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    trailingContent = {
                        Switch(checked = playIntro, onCheckedChange = { playIntro = it; model.settings.playIntro = it })
                    },
                )
                Text(
                    "A new brief is built every day after 12:00, in the background, when the phone is online. " +
                        "The top 5 are on the home-screen widget.",
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
                Text(
                    "Version ${BuildConfigInfo.versionName(LocalContext.current)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
            }
        },
    )
}

fun Context.openURL(url: String) {
    runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
}
