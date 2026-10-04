package app.trace.trace

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.text.format.DateUtils
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** "N drops waiting within 500 m" home-screen widget (spec F-15). Data is written by the app. */
class TraceWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val count = widgetData.getInt("nearby_count", 0)
        val teaser = widgetData.getString("nearest_teaser", "").orEmpty()
        val distance = widgetData.getString("nearest_distance", "").orEmpty()
        val updatedAt = widgetData.getLong("updated_at", 0L)

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.trace_widget).apply {
                setTextViewText(R.id.widget_count, if (count == 0) "–" else count.toString())
                setTextViewText(
                    R.id.widget_label,
                    when (count) {
                        0 -> "Nothing within 500 m yet"
                        1 -> "drop waiting within 500 m"
                        else -> "drops waiting within 500 m"
                    },
                )
                if (teaser.isNotEmpty()) {
                    setTextViewText(R.id.widget_teaser, "“$teaser”")
                    setViewVisibility(R.id.widget_teaser, View.VISIBLE)
                } else {
                    setViewVisibility(R.id.widget_teaser, View.GONE)
                }
                val age = if (updatedAt > 0) {
                    DateUtils.getRelativeTimeSpanString(updatedAt, System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS)
                } else {
                    "open Trace to look around"
                }
                setTextViewText(R.id.widget_footer, if (distance.isNotEmpty()) "Nearest $distance · $age" else age)
                setOnClickPendingIntent(R.id.widget_root, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
