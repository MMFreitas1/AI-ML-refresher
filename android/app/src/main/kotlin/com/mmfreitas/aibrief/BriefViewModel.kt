package com.mmfreitas.aibrief

import android.app.Application
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.mmfreitas.aibrief.core.BriefItem
import com.mmfreitas.aibrief.core.Day
import com.mmfreitas.aibrief.core.DailyBrief
import com.mmfreitas.aibrief.core.SavedItem
import com.mmfreitas.aibrief.core.Schedule
import com.mmfreitas.aibrief.widget.BriefWidget
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

enum class ReadFilter(val label: String) { All("All"), Unread("Unread"), Read("Read") }

class BriefViewModel(app: Application) : AndroidViewModel(app) {
    private val store = app.store
    val settings = AppSettings(app)

    // MARK: Daily refresh

    var isRefreshing by mutableStateOf(false)
        private set
    var lastError by mutableStateOf<String?>(null)
        private set

    /** Called when the app comes to the foreground. Also picks up changes made from the widget. */
    fun onResume() {
        reloadDays()
        if (selectedDay == null || selectedDay !in days) selectDay(days.firstOrNull())
        reloadCollection()
        if (Schedule.isDue(Instant.now(), days.firstOrNull())) refresh()
        syncNow()
    }

    // MARK: Sync

    val syncState get() = GoogleSync.state

    fun syncNow() {
        viewModelScope.launch {
            if (GoogleSync.sync(getApplication())) reloadCollection()
        }
    }

    /** After signing in: the first sync already ran, show its result. */
    fun syncedAfterSignIn() = reloadCollection()

    fun refresh() {
        if (isRefreshing) return
        isRefreshing = true
        viewModelScope.launch {
            try {
                val brief = withContext(Dispatchers.IO) { DailyRefresh.run(getApplication()) }
                lastError = if (brief.items.isEmpty()) "No items fetched — check your connection." else null
                reloadDays()
                selectDay(brief.day)
            } catch (e: Exception) {
                lastError = e.message
            } finally {
                isRefreshing = false
            }
        }
    }

    // MARK: Day navigation

    /** Newest first. */
    var days by mutableStateOf(emptyList<String>())
        private set
    var selectedDay by mutableStateOf<String?>(null)
        private set
    var brief by mutableStateOf<DailyBrief?>(null)
        private set

    private fun reloadDays() {
        days = store.availableDays()
    }

    fun selectDay(day: String?) {
        selectedDay = day
        brief = day?.let(store::brief)
    }

    private val selectedIndex get() = days.indexOf(selectedDay)
    val canStepOlder get() = selectedIndex >= 0 && selectedIndex + 1 < days.size
    val canStepNewer get() = selectedIndex > 0
    fun stepOlder() { if (canStepOlder) selectDay(days[selectedIndex + 1]) }
    fun stepNewer() { if (canStepNewer) selectDay(days[selectedIndex - 1]) }

    val dayTitle: String
        get() {
            val day = selectedDay ?: return "Today"
            if (day == Day.string(Instant.now())) return "Today"
            return runCatching { LocalDate.parse(day).format(DateTimeFormatter.ofPattern("EEEE, d MMM")) }.getOrDefault(day)
        }

    val daySubtitle: String
        get() = brief?.let {
            val time = it.generatedAt.atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT))
            "${it.items.size} items · built $time"
        } ?: ""

    // MARK: Collection

    var collection by mutableStateOf(emptyList<SavedItem>())
        private set
    val savedIDs by derivedStateOf { collection.mapTo(HashSet()) { it.id } }

    var search by mutableStateOf("")
    var readFilter by mutableStateOf(ReadFilter.All)
    /** null = all tags. */
    var tagFilter by mutableStateOf<String?>(null)

    val allTags by derivedStateOf { collection.flatMap { it.tags }.distinct().sorted() }

    val filteredCollection by derivedStateOf {
        val tag = tagFilter?.takeIf { it in allTags }
        collection.filter { s ->
            (tag == null || tag in s.tags) &&
                (readFilter == ReadFilter.All || s.isRead == (readFilter == ReadFilter.Read)) &&
                (search.isBlank() || listOf(s.item.title, s.item.summary, s.note, s.tags.joinToString(" "))
                    .any { it.contains(search.trim(), ignoreCase = true) })
        }
    }

    fun reloadCollection() {
        collection = store.loadCollection()
    }

    fun isSaved(item: BriefItem) = item.id in savedIDs

    /** The bookmark button: saves, or removes when already saved. */
    fun toggleSaved(item: BriefItem) =
        if (isSaved(item)) remove(item.id)
        else mutate(widget = true) { items -> if (items.none { it.id == item.id }) items.add(0, SavedItem(item)) }

    fun remove(id: String) = mutate(widget = true) { items -> items.removeAll { it.id == id } }

    fun toggleRead(id: String) = update(id) { it.copy(isRead = !it.isRead) }

    fun setNote(id: String, note: String) = update(id) { it.copy(note = note) }

    /** Comma separated, lowercased, no duplicates. */
    fun setTags(id: String, text: String) {
        val tags = text.split(',').map { it.trim().lowercase() }.filter { it.isNotEmpty() }.distinct()
        update(id) { if (it.tags == tags) it else it.copy(tags = tags) }
    }

    private fun update(id: String, change: (SavedItem) -> SavedItem) = mutate { items ->
        val i = items.indexOfFirst { it.id == id }
        if (i >= 0) items[i] = change(items[i])
    }

    /** [widget]: the change affects the widget's bookmark icons. */
    private fun mutate(widget: Boolean = false, change: (MutableList<SavedItem>) -> Unit) {
        try {
            collection = store.updateCollection(mutate = change)
        } catch (e: Exception) {
            lastError = "Could not save collection: ${e.message}"
            return
        }
        if (widget) viewModelScope.launch { BriefWidget.updateAll(getApplication()) }
        GoogleSync.scheduleSoon(getApplication())
    }
}
