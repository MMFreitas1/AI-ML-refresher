package com.mmfreitas.aibrief.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.mmfreitas.aibrief.BriefViewModel
import com.mmfreitas.aibrief.ReadFilter
import com.mmfreitas.aibrief.core.SavedItem
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** Saved items, kept forever, with search, read/unread and tag filters. Tap one to edit its tags and note. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CollectionPane(model: BriefViewModel, modifier: Modifier = Modifier) {
    var editing by rememberSaveable { mutableStateOf<String?>(null) }

    Column(modifier) {
        OutlinedTextField(
            value = model.search,
            onValueChange = { model.search = it },
            modifier = Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 8.dp),
            placeholder = { Text("Search the collection") },
            leadingIcon = { Icon(Icons.Filled.Search, null) },
            trailingIcon = {
                if (model.search.isNotEmpty()) IconButton(onClick = { model.search = "" }) { Icon(Icons.Filled.Clear, "Clear search") }
            },
            singleLine = true,
        )
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp)) {
            ReadFilter.entries.forEachIndexed { i, filter ->
                SegmentedButton(
                    selected = model.readFilter == filter,
                    onClick = { model.readFilter = filter },
                    shape = SegmentedButtonDefaults.itemShape(i, ReadFilter.entries.size),
                ) { Text(filter.label) }
            }
        }
        if (model.allTags.isNotEmpty()) LazyRow(
            contentPadding = PaddingValues(horizontal = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            items(model.allTags) { tag ->
                FilterChip(
                    selected = model.tagFilter == tag,
                    onClick = { model.tagFilter = if (model.tagFilter == tag) null else tag },
                    label = { Text(tag) },
                )
            }
        }
        HorizontalDivider(Modifier.padding(top = 4.dp))

        when {
            model.collection.isEmpty() -> EmptyState("Your collection is empty", "Tap the bookmark on any item to keep it here, with tags and notes.")
            model.filteredCollection.isEmpty() -> EmptyState("No matches", "Nothing in your collection matches these filters.")
            else -> LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(vertical = 4.dp)) {
                items(model.filteredCollection, key = { it.id }) { saved ->
                    SavedRow(saved, onClick = { editing = saved.id }, onToggleRead = { model.toggleRead(saved.id) })
                    HorizontalDivider(Modifier.padding(start = 40.dp))
                }
            }
        }
    }

    val current = model.collection.firstOrNull { it.id == editing }
    if (current != null) {
        ModalBottomSheet(onDismissRequest = { editing = null }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
            SavedEditor(model, current, onRemoved = { editing = null })
        }
    }
}

private val savedDate = DateTimeFormatter.ofPattern("d MMM yyyy")

private fun SavedItem.meta() =
    "${item.field.label} · ${item.source} · saved ${savedAt.atZone(ZoneId.systemDefault()).format(savedDate)}"

@Composable
private fun SavedRow(saved: SavedItem, onClick: () -> Unit, onToggleRead: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(end = 16.dp, top = 10.dp, bottom = 10.dp)) {
        // Unread dot; tap to toggle.
        IconButton(onClick = onToggleRead, modifier = Modifier.size(40.dp)) {
            Surface(
                Modifier.size(10.dp),
                shape = CircleShape,
                color = if (saved.isRead) MaterialTheme.colorScheme.outlineVariant else MaterialTheme.colorScheme.primary,
            ) {}
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                saved.item.title, style = MaterialTheme.typography.titleSmall,
                fontWeight = if (saved.isRead) FontWeight.Normal else FontWeight.SemiBold,
                maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
            Text(saved.meta(), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
            if (saved.tags.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                saved.tags.take(4).forEach { FieldChip(it) }
            }
            if (saved.note.isNotEmpty()) Text(
                saved.note.replace('\n', ' '), style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun SavedEditor(model: BriefViewModel, saved: SavedItem, onRemoved: () -> Unit) {
    val context = LocalContext.current
    var tags by rememberSaveable(saved.id) { mutableStateOf(saved.tags.joinToString(", ")) }
    var note by rememberSaveable(saved.id) { mutableStateOf(saved.note) }
    // Tags are applied on Done or when the sheet closes, so half-typed tags don't appear as filters.
    val focus = LocalFocusManager.current
    val currentTags by rememberUpdatedState(tags)
    DisposableEffect(saved.id) { onDispose { model.setTags(saved.id, currentTags) } }

    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 16.dp).navigationBarsPadding(),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(saved.item.title, style = MaterialTheme.typography.titleMedium)
        Text(saved.meta(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (saved.item.summary.isNotEmpty()) Text(saved.item.summary, style = MaterialTheme.typography.bodyMedium)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = { context.openURL(saved.item.url); if (!saved.isRead) model.toggleRead(saved.id) }) { Text("Open") }
            saved.item.discussionURL?.let { url -> OutlinedButton(onClick = { context.openURL(url) }) { Text("Discussion") } }
            Spacer(Modifier.weight(1f))
            TextButton(onClick = { model.toggleRead(saved.id) }) { Text(if (saved.isRead) "Mark unread" else "Mark read") }
        }
        OutlinedTextField(
            value = tags,
            onValueChange = { tags = it },
            label = { Text("Tags") },
            placeholder = { Text("comma, separated") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { model.setTags(saved.id, tags); focus.clearFocus() }),
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = note,
            onValueChange = { note = it; model.setNote(saved.id, it) },
            label = { Text("Note") },
            minLines = 4,
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(4.dp))
        TextButton(onClick = { model.remove(saved.id); onRemoved() }) {
            Text("Remove from collection", color = MaterialTheme.colorScheme.error)
        }
    }
}
