package com.simonkaring.voltlink.core.backup

import com.simonkaring.voltlink.data.BatteryHealthRecord
import com.simonkaring.voltlink.data.ChargingSample
import com.simonkaring.voltlink.data.ChargingSessionRecord
import com.simonkaring.voltlink.data.TripRecord
import com.simonkaring.voltlink.data.TripSample
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.time.Instant
import java.time.ZoneId

/**
 * One portable JSON document holding everything the history screens can show: trips with their
 * route samples, charging sessions with their curves, and battery-health readings.
 *
 * Times are epoch milliseconds and every value stays SI, so a backup written on one device can
 * be restored on another without unit conversion. This is the Android counterpart of the iOS
 * iCloud mirror — the file goes wherever the user points the folder picker.
 */
@Serializable
data class HistoryBackup(
    val version: Int = CURRENT_VERSION,
    val exportedAtMs: Long = System.currentTimeMillis(),
    val trips: List<BackupTrip> = emptyList(),
    val chargingSessions: List<BackupChargingSession> = emptyList(),
    val batteryHealth: List<BackupBatteryHealth> = emptyList(),
) {
    val isEmpty: Boolean
        get() = trips.isEmpty() && chargingSessions.isEmpty() && batteryHealth.isEmpty()

    fun toJson(): String = CODEC.encodeToString(serializer(), this)

    companion object {
        const val CURRENT_VERSION = 2
        private val CODEC = Json {
            prettyPrint = true
            ignoreUnknownKeys = true
            encodeDefaults = true
        }

        fun fromJson(text: String): HistoryBackup {
            val backup = CODEC.decodeFromString(serializer(), text)
            require(backup.version in 1..CURRENT_VERSION) {
                "unsupported backup version ${backup.version}"
            }
            return backup
        }

        fun capture(
            trips: List<TripRecord>,
            chargingSessions: List<ChargingSessionRecord>,
            batteryHealth: List<BatteryHealthRecord>,
        ): HistoryBackup = HistoryBackup(
            trips = trips.map { trip ->
                BackupTrip(
                    id = trip.id,
                    startTimeMs = trip.startTime.toEpochMilli(),
                    endTimeMs = trip.endTime?.toEpochMilli(),
                    distanceKm = trip.distanceKm,
                    startSocPct = trip.startSocPct,
                    endSocPct = trip.endSocPct,
                    totalKWhUsed = trip.totalKWhUsed,
                    totalKWhRecovered = trip.totalKWhRecovered,
                    averageSpeedKmH = trip.averageSpeedKmH,
                    maxPowerKW = trip.maxPowerKW,
                    maxRegenKW = trip.maxRegenKW,
                    vehicleName = trip.vehicleName,
                    samples = trip.samples.map { it.toBackup() },
                )
            },
            chargingSessions = chargingSessions.map { session ->
                BackupChargingSession(
                    id = session.id,
                    startTimeMs = session.startTime.toEpochMilli(),
                    endTimeMs = session.endTime?.toEpochMilli(),
                    startSocPct = session.startSocPct,
                    endSocPct = session.endSocPct,
                    totalKWhDelivered = session.totalKWhDelivered,
                    peakPowerKW = session.peakPowerKW,
                    averagePowerKW = session.averagePowerKW,
                    locationName = session.locationName,
                    latitude = session.latitude,
                    longitude = session.longitude,
                    startBatteryTempC = session.startBatteryTempC,
                    endBatteryTempC = session.endBatteryTempC,
                    startRangeKm = session.startRangeKm,
                    endRangeKm = session.endRangeKm,
                    isDC = session.isDC,
                    samples = session.samples.map { BackupChargingSample(it.timestamp.toEpochMilli(), it.socPct, it.powerKW) },
                )
            },
            batteryHealth = batteryHealth.map {
                BackupBatteryHealth(it.timestamp.toEpochMilli(), it.sohPct, it.vehicleName)
            },
        )
    }
}

@Serializable
data class BackupTrip(
    val id: String,
    val startTimeMs: Long,
    val endTimeMs: Long? = null,
    val distanceKm: Double = 0.0,
    val startSocPct: Double = 0.0,
    val endSocPct: Double = 0.0,
    val totalKWhUsed: Double = 0.0,
    val totalKWhRecovered: Double? = null,
    val averageSpeedKmH: Double = 0.0,
    val maxPowerKW: Double = 0.0,
    val maxRegenKW: Double = 0.0,
    val vehicleName: String = "Vehicle",
    val samples: List<BackupTripSample> = emptyList(),
) {
    fun toRecord(): TripRecord = TripRecord(
        id = id,
        startTime = Instant.ofEpochMilli(startTimeMs),
        endTime = endTimeMs?.let(Instant::ofEpochMilli),
        distanceKm = distanceKm,
        startSocPct = startSocPct,
        endSocPct = endSocPct,
        totalKWhUsed = totalKWhUsed,
        totalKWhRecovered = totalKWhRecovered,
        averageSpeedKmH = averageSpeedKmH,
        maxPowerKW = maxPowerKW,
        maxRegenKW = maxRegenKW,
        vehicleName = vehicleName,
    )

    fun toSamples(): List<TripSample> = samples.map {
        TripSample(
            timestamp = Instant.ofEpochMilli(it.timestampMs),
            latitude = it.latitude,
            longitude = it.longitude,
            speedKmH = it.speedKmH,
            powerKW = it.powerKW,
            socPct = it.socPct,
            batteryTempC = it.batteryTempC,
        )
    }
}

@Serializable
data class BackupTripSample(
    val timestampMs: Long,
    val latitude: Double = 0.0,
    val longitude: Double = 0.0,
    val speedKmH: Double = 0.0,
    val powerKW: Double = 0.0,
    val socPct: Double = 0.0,
    val batteryTempC: Double = 25.0,
)

@Serializable
data class BackupChargingSession(
    val id: String,
    val startTimeMs: Long,
    val endTimeMs: Long? = null,
    val startSocPct: Double = 0.0,
    val endSocPct: Double = 0.0,
    val totalKWhDelivered: Double = 0.0,
    val peakPowerKW: Double = 0.0,
    val averagePowerKW: Double = 0.0,
    val locationName: String = "Fast Charger",
    val latitude: Double? = null,
    val longitude: Double? = null,
    val startBatteryTempC: Double? = null,
    val endBatteryTempC: Double? = null,
    val startRangeKm: Double? = null,
    val endRangeKm: Double? = null,
    val isDC: Boolean? = null,
    val samples: List<BackupChargingSample> = emptyList(),
) {
    fun toRecord(): ChargingSessionRecord = ChargingSessionRecord(
        id = id,
        startTime = Instant.ofEpochMilli(startTimeMs),
        endTime = endTimeMs?.let(Instant::ofEpochMilli),
        startSocPct = startSocPct,
        endSocPct = endSocPct,
        totalKWhDelivered = totalKWhDelivered,
        peakPowerKW = peakPowerKW,
        averagePowerKW = averagePowerKW,
        locationName = locationName,
        latitude = latitude,
        longitude = longitude,
        startBatteryTempC = startBatteryTempC,
        endBatteryTempC = endBatteryTempC,
        startRangeKm = startRangeKm,
        endRangeKm = endRangeKm,
        isDC = isDC,
        samples = samples.map { ChargingSample(Instant.ofEpochMilli(it.timestampMs), it.socPct, it.powerKW) },
    )
}

@Serializable
data class BackupChargingSample(val timestampMs: Long, val socPct: Double, val powerKW: Double)

@Serializable
data class BackupBatteryHealth(val timestampMs: Long, val sohPct: Double, val vehicleName: String) {
    /** One reading per vehicle per local day is all the trend chart draws. */
    val dayKey: String
        get() = "$vehicleName|${Instant.ofEpochMilli(timestampMs).atZone(ZoneId.systemDefault()).toLocalDate()}"
}

/** What a restore would actually add; unchanged rows are skipped rather than duplicated. */
data class BackupPlan(
    val trips: List<BackupTrip>,
    val chargingSessions: List<BackupChargingSession>,
    val batteryHealth: List<BackupBatteryHealth>,
) {
    val isEmpty: Boolean get() = trips.isEmpty() && chargingSessions.isEmpty() && batteryHealth.isEmpty()

    val summary: String
        get() = "Restored ${trips.size} trips, ${chargingSessions.size} charges, " +
            "${batteryHealth.size} battery readings"

    companion object {
        /** Merge policy: newest row wins for unknown ids, existing ids are never overwritten. */
        fun of(
            backup: HistoryBackup,
            existingTripIds: Set<String>,
            existingSessionIds: Set<String>,
            existingHealthDayKeys: Set<String>,
        ): BackupPlan = BackupPlan(
            trips = backup.trips.filter { it.id !in existingTripIds },
            chargingSessions = backup.chargingSessions.filter { it.id !in existingSessionIds },
            batteryHealth = backup.batteryHealth.filter { it.dayKey !in existingHealthDayKeys },
        )
    }
}

private fun TripSample.toBackup() = BackupTripSample(
    timestampMs = timestamp.toEpochMilli(),
    latitude = latitude,
    longitude = longitude,
    speedKmH = speedKmH,
    powerKW = powerKW,
    socPct = socPct,
    batteryTempC = batteryTempC,
)
