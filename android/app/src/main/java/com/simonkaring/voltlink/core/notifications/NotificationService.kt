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
            NotificationChannel(
                CHANNEL_ALERTS,
                context.getString(R.string.notif_channel_alerts),
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = context.getString(R.string.notif_channel_alerts_desc)
            },
        )
        system.createNotificationChannel(
            NotificationChannel(
                CHANNEL_CHARGING,
                context.getString(R.string.notif_channel_charging),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = context.getString(R.string.notif_channel_charging_desc)
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
                if (minutes >= 60) {
                    context.getString(R.string.notif_eta_hours, minutes / 60, minutes % 60, target)
                } else {
                    context.getString(R.string.notif_eta_minutes, minutes, target)
                }
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
            append(context.getString(R.string.notif_charging_text, powerKW, target))
            eta?.let { append(" · ").append(it) }
        }

        val notification = NotificationCompat.Builder(context, CHANNEL_CHARGING)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.notif_charging_title, soc))
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
            context.getString(R.string.notif_finished_title),
            context.getString(R.string.notif_finished_body, startSocPct, endSocPct, energyKWh),
        )
    }

    fun notifyChargeTargetReached(targetPct: Int, socPct: Double) {
        notify(
            context.getString(R.string.notif_target_title),
            context.getString(R.string.notif_target_body, socPct, targetPct),
        )
    }

    fun notifyFaultCodes(count: Int) {
        if (count <= 0) return
        notify(
            if (count == 1) {
                context.getString(R.string.notif_faults_one)
            } else {
                context.getString(R.string.notif_faults_many, count)
            },
            context.getString(R.string.notif_faults_body),
        )
    }

    fun notifyAdapterLost(tripInProgress: Boolean) {
        notify(
            context.getString(R.string.notif_adapter_title),
            context.getString(if (tripInProgress) R.string.notif_adapter_trip else R.string.notif_adapter_idle),
        )
    }

    fun notifyServiceDue(distanceKm: Double) {
        notify(
            context.getString(R.string.notif_service_title),
            context.getString(R.string.notif_service_body, distanceKm),
        )
    }

    private fun notify(title: String, text: String) {
        if (!enabled) return
        ensureChannels()
        val notification = NotificationCompat.Builder(context, CHANNEL_ALERTS)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .setContentIntent(contentIntent())
            .build()
        post(ALERT_ID, notification)
    }
}
