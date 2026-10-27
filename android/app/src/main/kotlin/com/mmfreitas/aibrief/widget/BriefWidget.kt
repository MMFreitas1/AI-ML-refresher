package com.mmfreitas.aibrief.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity as actionStartIntent
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.itemsIndexed
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.ColorFilter
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import com.mmfreitas.aibrief.GoogleSync
import com.mmfreitas.aibrief.MainActivity
import com.mmfreitas.aibrief.R
import com.mmfreitas.aibrief.core.BriefItem
import com.mmfreitas.aibrief.core.Day
import com.mmfreitas.aibrief.store
import java.time.Instant
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * Home-screen widget: today's top 5. Tap an item to open it, the bookmark to save it, the header
 * to open the app. Updated by the app whenever the brief or the collection changes.
 */
class BriefWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val store = context.store
        val brief = store.latestBrief()
        val saved = store.loadCollection().mapTo(HashSet()) { it.id }
        val title = context.getString(R.string.app_name)
        provideContent {
            GlanceTheme {
                Content(title, brief?.day, brief?.items.orEmpty().take(5), saved)
            }
        }
    }

    /** The picture in the launcher's widget picker (Android 15+): the real top 5 when there is a brief. */
    override suspend fun providePreview(context: Context, widgetCategory: Int) {
        val items = context.store.latestBrief()?.items.orEmpty().take(5)
        val title = context.getString(R.string.app_name)
        provideContent { GlanceTheme { Content(title, null, items, emptySet()) } }
    }

    @Composable
    private fun Content(title: String, day: String?, items: List<BriefItem>, saved: Set<String>) {
        Column(
            GlanceModifier.fillMaxSize().background(GlanceTheme.colors.widgetBackground).cornerRadius(20.dp)
                .padding(horizontal = 12.dp, vertical = 10.dp),
        ) {
            Row(
                GlanceModifier.fillMaxWidth().clickable(actionStartActivity<MainActivity>()),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    title, GlanceModifier.defaultWeight(),
                    style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Bold, color = GlanceTheme.colors.onSurface),
                    maxLines = 1,
                )
                Text(dayLabel(day), style = TextStyle(fontSize = 12.sp, color = GlanceTheme.colors.onSurfaceVariant))
            }
            Spacer(GlanceModifier.height(6.dp))
            if (items.isEmpty()) {
                Text(
                    "A new brief is built every day after 12:00.",
                    GlanceModifier.clickable(actionStartActivity<MainActivity>()),
                    style = TextStyle(fontSize = 13.sp, color = GlanceTheme.colors.onSurfaceVariant),
                )
            } else {
                LazyColumn {
                    itemsIndexed(items, itemId = { _, item -> item.id.hashCode().toLong() }) { i, item ->
                        ItemRow(i + 1, item, item.id in saved)
                    }
                }
            }
        }
    }

    @Composable
    private fun ItemRow(rank: Int, item: BriefItem, saved: Boolean) {
        Row(GlanceModifier.fillMaxWidth().padding(vertical = 5.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                "$rank", GlanceModifier.width(18.dp),
                style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Bold, color = GlanceTheme.colors.primary),
            )
            Column(GlanceModifier.defaultWeight().clickable(actionStartIntent(Intent(Intent.ACTION_VIEW, Uri.parse(item.url))))) {
                Text(item.title, style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Medium, color = GlanceTheme.colors.onSurface), maxLines = 2)
                Text(
                    "${item.field.label} · ${item.source}",
                    style = TextStyle(fontSize = 11.sp, color = GlanceTheme.colors.onSurfaceVariant), maxLines = 1,
                )
            }
            Image(
                ImageProvider(if (saved) R.drawable.ic_bookmark else R.drawable.ic_bookmark_border),
                contentDescription = if (saved) "Saved" else "Save to collection",
                colorFilter = ColorFilter.tint(if (saved) GlanceTheme.colors.primary else GlanceTheme.colors.onSurfaceVariant),
                modifier = GlanceModifier.size(36.dp).padding(8.dp)
                    .clickable(actionRunCallback<SaveAction>(actionParametersOf(SaveAction.itemId to item.id))),
            )
        }
    }

    private fun dayLabel(day: String?): String = when (day) {
        null -> ""
        Day.string(Instant.now()) -> "Today"
        else -> runCatching { LocalDate.parse(day).format(DateTimeFormatter.ofPattern("EEE d MMM")) }.getOrDefault(day)
    }

    companion object {
        suspend fun updateAll(context: Context) {
            BriefWidget().updateAll(context)
            if (Build.VERSION.SDK_INT >= 35) {
                // The system rate-limits preview updates; a failed one keeps the previous picture.
                runCatching { GlanceAppWidgetManager(context).setWidgetPreviews(BriefWidgetReceiver::class) }
            }
        }

        fun canPin(context: Context) = AppWidgetManager.getInstance(context).isRequestPinAppWidgetSupported

        /** Asks the launcher to add the widget (the user confirms in a system dialog). */
        fun requestPin(context: Context) {
            AppWidgetManager.getInstance(context)
                .requestPinAppWidget(ComponentName(context, BriefWidgetReceiver::class.java), null, null)
        }
    }
}

/** The bookmark: adds the item to the collection (removing is done in the app, where tags and notes are visible). */
class SaveAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val id = parameters[itemId] ?: return
        val item = context.store.latestBrief()?.items?.firstOrNull { it.id == id } ?: return
        if (context.store.save(item)) {
            BriefWidget().update(context, glanceId)
            GoogleSync.scheduleSoon(context)
        }
    }

    companion object {
        val itemId = ActionParameters.Key<String>("itemId")
    }
}

class BriefWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = BriefWidget()
}
