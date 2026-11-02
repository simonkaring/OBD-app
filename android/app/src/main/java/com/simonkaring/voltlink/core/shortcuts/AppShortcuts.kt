package com.simonkaring.voltlink.core.shortcuts

import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import com.simonkaring.voltlink.MainActivity
import com.simonkaring.voltlink.R

/** Actions a launcher shortcut or assistant command can ask the app to run. */
enum class AppCommand { TOGGLE_TRIP, SCAN_DTCS, OPEN_CHARGING }

/**
 * Long-press launcher shortcuts for the actions Siri/Shortcuts exposes on iOS: trip start and
 * stop, a fault-code scan, and the charging tab. The trip shortcut label tracks the recorder
 * state, so "Start trip" becomes "Stop trip" while a trip is running.
 */
object AppShortcuts {
    const val ACTION_TOGGLE_TRIP = "com.simonkaring.voltlink.action.TOGGLE_TRIP"
    const val ACTION_SCAN_DTCS = "com.simonkaring.voltlink.action.SCAN_DTCS"
    const val ACTION_OPEN_CHARGING = "com.simonkaring.voltlink.action.OPEN_CHARGING"

    private const val TRIP_ID = "shortcut_trip"
    private const val SCAN_ID = "shortcut_scan"
    private const val CHARGING_ID = "shortcut_charging"

    fun publish(context: Context, isRecordingTrip: Boolean) {
        val manager = context.getSystemService(ShortcutManager::class.java) ?: return
        val icon = Icon.createWithResource(context, R.drawable.ic_launcher_foreground)
        val shortcuts = buildList {
            add(
                ShortcutInfo.Builder(context, TRIP_ID)
                    .setShortLabel(if (isRecordingTrip) "Stop trip" else "Start trip")
                    .setLongLabel(if (isRecordingTrip) "Stop recording the current trip" else "Start recording a trip")
                    .setIcon(icon)
                    .setRank(0)
                    .setIntent(intent(context, ACTION_TOGGLE_TRIP))
                    .build(),
            )
            add(
                ShortcutInfo.Builder(context, SCAN_ID)
                    .setShortLabel("Scan codes")
                    .setLongLabel("Scan the vehicle for fault codes")
                    .setIcon(icon)
                    .setRank(1)
                    .setIntent(intent(context, ACTION_SCAN_DTCS))
                    .build(),
            )
            add(
                ShortcutInfo.Builder(context, CHARGING_ID)
                    .setShortLabel("Charging")
                    .setLongLabel("Open the live charging screen")
                    .setIcon(icon)
                    .setRank(2)
                    .setIntent(intent(context, ACTION_OPEN_CHARGING))
                    .build(),
            )
        }
        runCatching { manager.dynamicShortcuts = shortcuts }
    }

    private fun intent(context: Context, action: String): Intent =
        Intent(context, MainActivity::class.java).apply {
            this.action = action
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
}
