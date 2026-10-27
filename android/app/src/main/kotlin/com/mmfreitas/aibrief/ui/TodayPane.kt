package com.mmfreitas.aibrief.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.mmfreitas.aibrief.BriefViewModel
import com.mmfreitas.aibrief.R
import com.mmfreitas.aibrief.core.BriefItem

/** The selected day's ranked items, with ‹ › to browse past days. Tap an item to open it. */
@Composable
fun TodayPane(model: BriefViewModel, modifier: Modifier = Modifier) {
    var showErrors by remember { mutableStateOf(false) }
    Column(modifier) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = model::stepOlder, enabled = model.canStepOlder) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "Previous day")
            }
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(model.dayTitle, style = MaterialTheme.typography.titleMedium)
                if (model.daySubtitle.isNotEmpty()) Text(
                    model.daySubtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (model.brief?.errors?.isNotEmpty() == true) IconButton(onClick = { showErrors = true }) {
                Icon(Icons.Filled.Warning, "Some sources failed", tint = MaterialTheme.colorScheme.error)
            }
            IconButton(onClick = model::stepNewer, enabled = model.canStepNewer) {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Next day")
            }
        }
        HorizontalDivider()

        val items = model.brief?.items.orEmpty()
        if (items.isEmpty()) {
            EmptyState(
                title = if (model.isRefreshing) "Fetching today's brief…" else "No brief yet",
                message = model.lastError ?: "A new brief is built every day after 12:00.",
            )
        } else {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(vertical = 4.dp)) {
                itemsIndexed(items, key = { _, item -> item.id }) { i, item ->
                    BriefRow(i + 1, item, saved = model.isSaved(item), onToggleSaved = { model.toggleSaved(item) })
                    if (i < items.lastIndex) HorizontalDivider(Modifier.padding(start = 52.dp))
                }
            }
        }
    }

    val errors = model.brief?.errors.orEmpty()
    if (showErrors) AlertDialog(
        onDismissRequest = { showErrors = false },
        confirmButton = { TextButton(onClick = { showErrors = false }) { Text("OK") } },
        title = { Text("Some sources failed") },
        text = { Text(errors.joinToString("\n")) },
    )
}

@Composable
private fun BriefRow(rank: Int, item: BriefItem, saved: Boolean, onToggleSaved: () -> Unit) {
    val context = LocalContext.current
    Row(
        Modifier.fillMaxWidth().clickable { context.openURL(item.url) }.padding(start = 12.dp, top = 10.dp, bottom = 10.dp),
        verticalAlignment = Alignment.Top,
    ) {
        // The widget shows the top 5; they're marked here too.
        Text(
            "$rank",
            Modifier.width(28.dp).padding(top = 2.dp),
            style = MaterialTheme.typography.titleSmall,
            fontWeight = if (rank <= 5) FontWeight.Bold else FontWeight.Normal,
            color = if (rank <= 5) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(item.title, style = MaterialTheme.typography.titleSmall, maxLines = 3, overflow = TextOverflow.Ellipsis)
            if (item.summary.isNotEmpty()) Text(
                item.summary, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 3, overflow = TextOverflow.Ellipsis,
            )
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FieldChip(item.field.label)
                Text(
                    "${item.source} · ${item.metric}", style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
            }
            item.discussionURL?.let { url ->
                Text(
                    "Discussion",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.clickable { context.openURL(url) }.padding(vertical = 2.dp),
                )
            }
        }
        IconButton(onClick = onToggleSaved) {
            Icon(
                painterResource(if (saved) R.drawable.ic_bookmark else R.drawable.ic_bookmark_border),
                if (saved) "Remove from collection" else "Save to collection",
                tint = if (saved) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
fun FieldChip(label: String) {
    Surface(color = MaterialTheme.colorScheme.secondaryContainer, shape = RoundedCornerShape(6.dp)) {
        Text(
            label, Modifier.padding(horizontal = 6.dp, vertical = 1.dp),
            style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSecondaryContainer, maxLines = 1,
        )
    }
}

@Composable
fun EmptyState(title: String, message: String) {
    Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.widthIn(max = 360.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
            Spacer(Modifier.height(6.dp))
            Text(message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
        }
    }
}
