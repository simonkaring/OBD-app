package com.simonkaring.voltlink.core.notifications

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.simonkaring.voltlink.MainActivity
import com.simonkaring.voltlink.R
import java.util.Locale

/**
 * Opt-in local alerts and the ongoing charging notification (the Android counterpart of the
 * iOS Live Activity). Permission is only ever requested from the Settings toggle, never at
 * launch.
 */
class NotificationService(private val context: Context) {
    companion object {
        const val CHANNEL_ALERTS = "voltlink_alerts"
        const val CHANNEL_CHARGING = "voltlink_charging"
        const val ONGOING_ID = 1001
        private const val ALERT_ID = 1002
        /** Matches `Theme.regenGreen`; the notification layer must not depend on the UI package. */
        private const val COLOR_CHARGED = 0xFF30D158.toInt()
        private const val COLOR_TRACK = 0x33FFFFFF
    }

    private val manager: NotificationManagerCompat = NotificationManagerCompat.from(context)
    private val enabled: Boolean
        get() = NotificationManagerCompat.from(context).areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED)

    /** Posts a notification, tolerating a permission revoked after the toggle was enabled. */
    private fun post(id: Int, notification: android.app.Notification): Boolean =
        try {
            manager.notify(id, notification)
            true
        } catch (e: SecurityException) {
            false
        }

    fun ensureChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val system = context.getSystemService(NotificationManager::class.java) ?: return
        system.createNotificationChannel(
            NotificationChannel(CHANNEL_ALERTS, "Vehicle alerts", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Charging finished, charge target reached, fault codes and adapter loss"
            },
        )
        system.createNotificationChannel(
            NotificationChannel(CHANNEL_CHARGING, "Charging status", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Ongoing notification while the vehicle is charging"
                setShowBadge(false)
            },
        )
    }

    private fun contentIntent(): PendingIntent = PendingIntent.getActivity(
        context,
        0,
        Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        },
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    /**
     * Ongoing charging status, promoted to a Live Update card on Android 16+.
     *
     * The progress style draws the charged portion up to [socPct] and marks the target SoC, so
     * the lock screen shows "how far to my target" without opening the app. Older releases fall
     * back to the plain progress bar set on the notification itself.
     */
    fun showChargingStatus(
        socPct: Double,
        powerKW: Double,
        targetPct: Int,
        secondsToTarget: Double? = null,
    ) {
        if (!enabled) return
        ensureChannels()

        val soc = socPct.coerceIn(0.0, 100.0)
        val target = targetPct.coerceIn(1, 100)
        val eta = secondsToTarget
            ?.takeIf { it.isFinite() && it > 0 }
            ?.let { seconds ->
                val minutes = (seconds / 60).toInt().coerceAtLeast(1)
                if (minutes >= 60) String.format(Locale.US, "%dh %02dmin to %d%%", minutes / 60, minutes % 60, target)
                else String.format(Locale.US, "%d min to %d%%", minutes, target)
            }

        val progressStyle = NotificationCompat.ProgressStyle()
            .setStyledByProgress(false)
            .setProgress(soc.toInt())
            .setProgressSegments(
                listOf(
                    NotificationCompat.ProgressStyle.Segment(soc.toInt())
                        .setColor(COLOR_CHARGED),
                    NotificationCompat.ProgressStyle.Segment((100 - soc.toInt()).coerceAtLeast(0))
                        .setColor(COLOR_TRACK),
                ),
            )
            .setProgressPoints(
                listOf(
                    NotificationCompat.ProgressStyle.Point(target)
                        .setColor(COLOR_CHARGED),
                ),
            )

        val text = buildString {
            append(String.format(Locale.US, "%.1f kW", powerKW))
            append(" · target ").append(target).append('%')
            eta?.let { append(" · ").append(it) }
        }

        val notification = NotificationCompat.Builder(context, CHANNEL_CHARGING)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(String.format(Locale.US, "Charging · %.0f%%", soc))
            .setContentText(text)
            .setSubText(eta)
            .setProgress(100, soc.toInt(), false)
            .setStyle(progressStyle)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setShortCriticalText(String.format(Locale.US, "%.0f%%", soc))
            .setRequestPromotedOngoing(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setSilent(true)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentIntent())
            .build()
        post(ONGOING_ID, notification)
    }

    fun cancelChargingStatus() {
        try {
            manager.cancel(ONGOING_ID)
        } catch (e: SecurityException) {
            // Permission revoked mid-session; nothing to clear.
        }
    }

    fun notifyChargingFinished(startSocPct: Double, endSocPct: Double, energyKWh: Double) {
        notify(
            "Charging finished",
            String.format(
                Locale.US,
                "%.0f%% → %.0f%% (%.1f kWh delivered)",
                startSocPct,
                endSocPct,
                energyKWh,
            ),
        )
    }

    fun notifyChargeTargetReached(targetPct: Int, socPct: Double) {
        notify(
            "Charge target reached",
            String.format(Locale.US, "Battery at %.0f%%, target %d%%", socPct, targetPct),
        )
    }

    fun notifyFaultCodes(count: Int) {
        if (count <= 0) return
        notify(
            if (count == 1) "1 fault code found" else "$count fault codes found",
            "Open VoltLink diagnostics for details and repair guidance.",
        )
    }

    fun notifyAdapterLost(tripInProgress: Boolean) {
        notify(
            "OBD adapter disconnected",
            if (tripInProgress) {
                "The adapter dropped during a trip recording. Reconnect the scanner."
            } else {
                "Reconnect the scanner to resume live telemetry."
            },
        )
    }

    fun notifyServiceDue(distanceKm: Double) {
        notify(
            "Service due",
            String.format(Locale.US, "%.0f km until the next vehicle service", distanceKm),
        )
    }

    private fun notify(title: String, text: String) {
        if (!enabled) return
        ensureChannels()
        val notification = NotificationCompat.Builder(context, CHANNEL_ALERTS)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .setContentIntent(contentIntent())
            .build()
        post(ALERT_ID, notification)
    }
}
