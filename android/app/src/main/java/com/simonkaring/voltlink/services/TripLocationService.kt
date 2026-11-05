package com.simonkaring.voltlink.services

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.simonkaring.voltlink.MainActivity
import com.simonkaring.voltlink.R
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.time.Instant

/** One accepted position fix, in SI units. */
data class LocationFix(
    val timestamp: Instant,
    val latitude: Double,
    val longitude: Double,
    val altitudeM: Double,
    val speedKmH: Double,
    val accuracyM: Float,
) {
    val hasValidCoordinate: Boolean
        get() = latitude in -90.0..90.0 && longitude in -180.0..180.0 && !(latitude == 0.0 && longitude == 0.0)
}

/**
 * Latest fix from the trip recorder, shared by the foreground service and [TripTracker].
 * A fix older than [staleAfterSeconds] is never attached to a sample.
 */
object TripLocation {
    const val staleAfterSeconds = 10.0

    private val _latest = MutableStateFlow<LocationFix?>(null)
    val latest: StateFlow<LocationFix?> = _latest.asStateFlow()

    private val _isRecording = MutableStateFlow(false)
    val isRecording: StateFlow<Boolean> = _isRecording.asStateFlow()

    fun record(fix: LocationFix) {
        _latest.value = fix
    }

    fun markRecording(recording: Boolean) {
        _isRecording.value = recording
    }

    /** A fix usable for the sample captured at [at]: recent and inside the accuracy bound. */
    fun fixFor(at: Instant): LocationFix? {
        val fix = _latest.value ?: return null
        if (!fix.hasValidCoordinate) return null
        if (fix.accuracyM > maxAccuracyMeters) return null
        // GPS time can sit a fraction of a second ahead of the device clock.
        val age = (at.toEpochMilli() - fix.timestamp.toEpochMilli()) / 1000.0
        return if (age in -2.0..staleAfterSeconds) fix else null
    }

    fun clear() {
        _latest.value = null
        _isRecording.value = false
    }

    /** Matches the iOS `TripLocationManager` accuracy bound. */
    const val maxAccuracyMeters = 100f
}

/**
 * Best last-known position for a charging session that starts while the car is parked.
 *
 * Never prompts for permission and never starts location updates: without an existing grant or
 * a recent fix it returns null and the session simply has no coordinates. The 15-minute bound
 * keeps a genuinely old position from being attached to a charge at a different place.
 */
@SuppressLint("MissingPermission")
fun lastKnownLocation(context: Context): LocationFix? {
    if (!TripLocationService.hasLocationPermission(context)) return null
    val manager = context.getSystemService(LocationManager::class.java) ?: return null
    val newest = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
        .mapNotNull { provider -> runCatching { manager.getLastKnownLocation(provider) }.getOrNull() }
        .maxByOrNull { it.time }
        ?: return null
    if (System.currentTimeMillis() - newest.time > 15 * 60_000L) return null
    return LocationFix(
        timestamp = Instant.ofEpochMilli(newest.time),
        latitude = newest.latitude,
        longitude = newest.longitude,
        altitudeM = if (newest.hasAltitude()) newest.altitude else 0.0,
        speedKmH = if (newest.hasSpeed()) newest.speed * 3.6 else 0.0,
        accuracyM = if (newest.hasAccuracy()) newest.accuracy else Float.MAX_VALUE,
    ).takeIf { it.hasValidCoordinate && it.accuracyM <= TripLocation.maxAccuracyMeters }
}

/**
 * Foreground location recorder for trips.
 *
 * Started only when a trip recording begins and the user has already granted location access
 * (the permission is requested from the Start Trip action, never at launch). The persistent
 * notification is Android's equivalent of the iOS background-location indicator.
 */
class TripLocationService : Service(), LocationListener {
    companion object {
        const val ACTION_START = "com.simonkaring.voltlink.action.START_TRIP_LOCATION"
        const val ACTION_STOP = "com.simonkaring.voltlink.action.STOP_TRIP_LOCATION"
        private const val CHANNEL = "voltlink_trip_location"
        private const val NOTIFICATION_ID = 1003
        private const val INTERVAL_MS = 1_000L

        fun hasLocationPermission(context: Context): Boolean =
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED

        /** Starts the recorder; a no-op without location permission. */
        fun start(context: Context) {
            if (!hasLocationPermission(context)) return
            val intent = Intent(context, TripLocationService::class.java).setAction(ACTION_START)
            ContextCompat.startForegroundService(context, intent)
        }

        /** Stops the recorder; safe to call when it is not running. */
        fun stop(context: Context) {
            if (!TripLocation.isRecording.value) return
            val intent = Intent(context, TripLocationService::class.java).setAction(ACTION_STOP)
            // An already-running location service may be re-addressed even from the background.
            ContextCompat.startForegroundService(context, intent)
        }
    }

    private val locationManager by lazy { getSystemService(LocationManager::class.java) }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (TripLocationCommand.of(intent?.action)) {
            TripLocationCommand.STOP -> {
                stopRecording()
                stopSelf()
                return START_NOT_STICKY
            }
            TripLocationCommand.IGNORE -> {
                // A sticky restart arrives with a null intent and the trip died with the
                // process: leave a live recording alone, stop a phantom one.
                if (!TripLocation.isRecording.value) stopSelf()
                return START_NOT_STICKY
            }
            TripLocationCommand.START -> Unit
        }
        if (!hasLocationPermission(this)) {
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(NOTIFICATION_ID, ongoingNotification())
        requestUpdates()
        TripLocation.markRecording(true)
        return START_NOT_STICKY
    }

    override fun onLocationChanged(location: Location) {
        // Keep accuracy filtering in one place: bad fixes never reach the trip samples.
        if (location.hasAccuracy() && location.accuracy > TripLocation.maxAccuracyMeters) return
        TripLocation.record(
            LocationFix(
                timestamp = Instant.ofEpochMilli(location.time),
                latitude = location.latitude,
                longitude = location.longitude,
                altitudeM = if (location.hasAltitude()) location.altitude else 0.0,
                speedKmH = if (location.hasSpeed()) location.speed * 3.6 else 0.0,
                accuracyM = if (location.hasAccuracy()) location.accuracy else Float.MAX_VALUE,
            ),
        )
    }

    @Deprecated("Required by the platform LocationListener contract below API 30.")
    override fun onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) = Unit

    override fun onProviderEnabled(provider: String) = Unit

    override fun onProviderDisabled(provider: String) = Unit

    override fun onDestroy() {
        stopRecording()
        super.onDestroy()
    }

    private fun requestUpdates() {
        val manager = locationManager ?: return
        // Checked here as well as in onStartCommand so lint and the runtime agree.
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER).forEach { provider ->
            runCatching {
                if (manager.isProviderEnabled(provider)) {
                    manager.requestLocationUpdates(provider, INTERVAL_MS, 0f, this, Looper.getMainLooper())
                }
            }
        }
    }

    private fun stopRecording() {
        runCatching { locationManager?.removeUpdates(this) }
        TripLocation.clear()
        TripLocation.markRecording(false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        }
    }

    private fun createChannel() {
        val system = getSystemService(NotificationManager::class.java) ?: return
        system.createNotificationChannel(
            NotificationChannel(CHANNEL, "Trip GPS", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shown while a trip records its route"
                setShowBadge(false)
            },
        )
    }

    private fun ongoingNotification(): android.app.Notification {
        val content = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = android.app.PendingIntent.getActivity(
            this,
            0,
            content,
            android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Recording trip route")
            .setContentText("GPS logging stops when the trip ends")
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(pending)
            .build()
    }
}

/**
 * What the recorder should do for the intent it was started with. A sticky restart
 * delivers a null intent, which must never begin recording: the trip lives in
 * `TripTracker` and did not survive the process death that caused the restart.
 */
internal enum class TripLocationCommand {
    START,
    STOP,
    IGNORE,
    ;

    companion object {
        fun of(action: String?): TripLocationCommand = when (action) {
            TripLocationService.ACTION_START -> START
            TripLocationService.ACTION_STOP -> STOP
            else -> IGNORE
        }
    }
}
