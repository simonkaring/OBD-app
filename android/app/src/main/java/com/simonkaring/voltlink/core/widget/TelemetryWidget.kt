package com.simonkaring.voltlink.core.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.simonkaring.voltlink.MainActivity
import com.simonkaring.voltlink.R
import com.simonkaring.voltlink.core.telemetry.TelemetrySnapshot
import java.util.Locale

/**
 * Home-screen telemetry widget — the Android counterpart of the iOS `VoltLinkWidget`.
 *
 * The app process cannot reach the widget directly, so every published snapshot is written to
 * shared preferences first; the widget reads that snapshot when the launcher asks for an
 * update. Values are throttled to one broadcast every few seconds so a 1 Hz poll does not
 * wake the launcher constantly.
 */
class TelemetryWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val views = TelemetryWidgetStore.views(context)
        appWidgetIds.forEach { id -> appWidgetManager.updateAppWidget(id, views) }
    }
}

object TelemetryWidgetStore {
    private const val PREFS = "voltlink_widget"
    private const val KEY_UPDATED_AT = "updated_at"
    private const val MIN_UPDATE_INTERVAL_MS = 5_000L
    private const val STALE_AFTER_MS = 120_000L

    /** Persists the newest snapshot and refreshes any placed widgets. */
    fun publish(
        context: Context,
        snapshot: TelemetrySnapshot,
        vehicleName: String,
        isConnected: Boolean,
        isCharging: Boolean,
        isDemoMode: Boolean,
    ) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        prefs.edit()
            .putLong("time", now)
            .putString("vehicle", vehicleName)
            .putFloat("soc", snapshot.stateOfChargePct.toFloat())
            .putFloat("power", snapshot.powerKW.toFloat())
            .putFloat("speed", snapshot.speedKmH.toFloat())
            .putFloat("charge_power", snapshot.chargePowerKW.toFloat())
            .putBoolean("connected", isConnected)
            .putBoolean("charging", isCharging)
            .putBoolean("demo", isDemoMode)
            .apply()

        val lastPush = prefs.getLong(KEY_UPDATED_AT, 0L)
        if (now - lastPush < MIN_UPDATE_INTERVAL_MS) return
        prefs.edit().putLong(KEY_UPDATED_AT, now).apply()
        refresh(context)
    }

    /** Repaints every widget instance; a no-op when none are placed. */
    fun refresh(context: Context) {
        val manager = AppWidgetManager.getInstance(context) ?: return
        val ids = manager.getAppWidgetIds(ComponentName(context, TelemetryWidgetProvider::class.java))
        if (ids.isEmpty()) return
        val views = views(context)
        ids.forEach { id -> manager.updateAppWidget(id, views) }
    }

    fun views(context: Context): RemoteViews {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val views = RemoteViews(context.packageName, R.layout.widget_telemetry)
        val time = prefs.getLong("time", 0L)
        val hasReading = time > 0
        // After the app process stops publishing, the last values stay but stop claiming to be live.
        val stale = hasReading && System.currentTimeMillis() - time > STALE_AFTER_MS
        val connected = prefs.getBoolean("connected", false)
        val charging = prefs.getBoolean("charging", false)
        val demo = prefs.getBoolean("demo", false)
        val soc = prefs.getFloat("soc", 0f).toDouble()
        val power = prefs.getFloat("power", 0f).toDouble()
        val speed = prefs.getFloat("speed", 0f).toDouble()
        val chargePower = prefs.getFloat("charge_power", 0f).toDouble()

        views.setTextViewText(
            R.id.widget_vehicle,
            prefs.getString("vehicle", null) ?: context.getString(R.string.widget_offline),
        )
        views.setTextViewText(
            R.id.widget_status,
            when {
                !hasReading || (!connected && !demo) -> context.getString(R.string.widget_offline)
                stale -> context.getString(R.string.widget_stale)
                demo -> context.getString(R.string.widget_demo)
                charging -> context.getString(R.string.widget_charging)
                else -> context.getString(R.string.widget_live)
            },
        )
        views.setTextViewText(
            R.id.widget_soc,
            if (hasReading) String.format(Locale.US, "%.0f%%", soc) else "—",
        )
        views.setProgressBar(R.id.widget_progress, 100, soc.toInt().coerceIn(0, 100), false)
        views.setTextViewText(
            R.id.widget_power,
            when {
                charging -> String.format(Locale.US, "%.0f kW", chargePower)
                hasReading -> String.format(Locale.US, "%.0f kW", power)
                else -> "—"
            },
        )
        views.setTextViewText(
            R.id.widget_speed,
            if (hasReading) String.format(Locale.US, "%.0f km/h", speed) else "—",
        )

        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        views.setOnClickPendingIntent(R.id.widget_root, open)
        return views
    }
}
