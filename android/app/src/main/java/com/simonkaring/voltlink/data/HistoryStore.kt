package com.simonkaring.voltlink.data

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import com.simonkaring.voltlink.core.telemetry.ChargingTimeEstimator
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

data class TripSample(
    val timestamp: Instant,
    val latitude: Double = 0.0,
    val longitude: Double = 0.0,
    val speedKmH: Double = 0.0,
    val powerKW: Double = 0.0,
    val socPct: Double = 0.0,
    val batteryTempC: Double = 25.0,
) {
    val hasValidCoordinate: Boolean
        get() = latitude in -90.0..90.0 && longitude in -180.0..180.0 && !(latitude == 0.0 && longitude == 0.0)
}

data class TripRecord(
    val id: String = UUID.randomUUID().toString(),
    val startTime: Instant = Instant.now(),
    val endTime: Instant? = null,
    val distanceKm: Double = 0.0,
    val startSocPct: Double = 0.0,
    val endSocPct: Double = 0.0,
    val totalKWhUsed: Double = 0.0,
    val totalKWhRecovered: Double? = 0.0,
    val averageSpeedKmH: Double = 0.0,
    val maxPowerKW: Double = 0.0,
    val maxRegenKW: Double = 0.0,
    val vehicleName: String = "Vehicle",
    val samples: List<TripSample> = emptyList(),
) {
    val efficiencyKWhPer100Km: Double
        get() = if (distanceKm <= 0.1) 0.0 else ((totalKWhUsed - (totalKWhRecovered ?: 0.0)) / distanceKm) * 100.0

    val duration: java.time.Duration
        get() = java.time.Duration.between(startTime, endTime ?: Instant.now())

    val computedAverageSpeedKmH: Double
        get() {
            val speeds = samples.map { it.speedKmH }.filter { it.isFinite() }
            if (speeds.isNotEmpty()) return speeds.average()
            if (averageSpeedKmH > 0) return averageSpeedKmH
            val end = endTime ?: return 0.0
            val hours = java.time.Duration.between(startTime, end).toMillis() / 3_600_000.0
            return if (hours > 0) distanceKm / hours else 0.0
        }
}

data class ChargingSample(val timestamp: Instant, val socPct: Double, val powerKW: Double)

data class ChargingSessionRecord(
    val id: String = UUID.randomUUID().toString(),
    val startTime: Instant = Instant.now(),
    val endTime: Instant? = null,
    val startSocPct: Double = 0.0,
    val endSocPct: Double = 0.0,
    val totalKWhDelivered: Double = 0.0,
    val peakPowerKW: Double = 0.0,
    val averagePowerKW: Double = 0.0,
    val locationName: String = "Fast Charger",
    /** Position captured when the session started, when a fix was already available. */
    val latitude: Double? = null,
    val longitude: Double? = null,
    val startBatteryTempC: Double? = null,
    val endBatteryTempC: Double? = null,
    val startRangeKm: Double? = null,
    val endRangeKm: Double? = null,
    /** DC classification recorded at session close; null on rows written before it existed. */
    val isDC: Boolean? = null,
    val samples: List<ChargingSample> = emptyList(),
) {
    val duration: java.time.Duration
        get() = java.time.Duration.between(startTime, endTime ?: Instant.now())

    val hasLocation: Boolean
        get() {
            val latitude = latitude ?: return false
            val longitude = longitude ?: return false
            return latitude in -90.0..90.0 && longitude in -180.0..180.0 &&
                !(latitude == 0.0 && longitude == 0.0)
        }

    /** Older rows have no stored class, so their peak power decides it. */
    val isDCCharging: Boolean
        get() = isDC ?: (peakPowerKW > ChargingTimeEstimator.DC_POWER_THRESHOLD_KW)
}

data class BatteryHealthRecord(
    val timestamp: Instant,
    val sohPct: Double,
    val vehicleName: String,
)

/** SQLite schema mirroring the SwiftData V3 models used by the iOS app. */
private class VoltLinkDatabase(context: Context) : SQLiteOpenHelper(context, "voltlink.db", null, 2) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """CREATE TABLE trips(
                id TEXT PRIMARY KEY, start_time INTEGER NOT NULL, end_time INTEGER,
                distance_km REAL NOT NULL, start_soc REAL NOT NULL, end_soc REAL NOT NULL,
                kwh_used REAL NOT NULL, kwh_recovered REAL, avg_speed REAL NOT NULL,
                max_power REAL NOT NULL, max_regen REAL NOT NULL, vehicle_name TEXT NOT NULL)""",
        )
        db.execSQL(
            """CREATE TABLE trip_samples(
                id INTEGER PRIMARY KEY AUTOINCREMENT, trip_id TEXT NOT NULL,
                timestamp INTEGER NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL,
                speed REAL NOT NULL, power REAL NOT NULL, soc REAL NOT NULL, battery_temp REAL NOT NULL)""",
        )
        db.execSQL("CREATE INDEX idx_trip_samples ON trip_samples(trip_id, timestamp)")
        db.execSQL(
            """CREATE TABLE charging_sessions(
                id TEXT PRIMARY KEY, start_time INTEGER NOT NULL, end_time INTEGER,
                start_soc REAL NOT NULL, end_soc REAL NOT NULL, kwh REAL NOT NULL,
                peak_power REAL NOT NULL, avg_power REAL NOT NULL, location_name TEXT NOT NULL,
                latitude REAL, longitude REAL, start_temp REAL, end_temp REAL,
                start_range REAL, end_range REAL, is_dc INTEGER)""",
        )
        db.execSQL(
            """CREATE TABLE charging_samples(
                id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL,
                timestamp INTEGER NOT NULL, soc REAL NOT NULL, power REAL NOT NULL)""",
        )
        db.execSQL("CREATE INDEX idx_charging_samples ON charging_samples(session_id, timestamp)")
        db.execSQL(
            """CREATE TABLE battery_health(
                id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL,
                soh REAL NOT NULL, vehicle_name TEXT NOT NULL)""",
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            // Additive columns: existing sessions keep their rows and simply have no location,
            // temperature, range or recorded AC/DC class.
            listOf(
                "latitude REAL",
                "longitude REAL",
                "start_temp REAL",
                "end_temp REAL",
                "start_range REAL",
                "end_range REAL",
                "is_dc INTEGER",
            ).forEach { column -> db.execSQL("ALTER TABLE charging_sessions ADD COLUMN $column") }
        }
    }
}

/**
 * Persistence for trips, charging sessions and battery-health readings. Writes happen on
 * [Dispatchers.IO]; published lists refresh after every write so the UI stays in sync.
 */
class HistoryStore(context: Context, private val scope: CoroutineScope) {
    private val db = VoltLinkDatabase(context.applicationContext)

    private val _trips = MutableStateFlow<List<TripRecord>>(emptyList())
    val trips: StateFlow<List<TripRecord>> = _trips.asStateFlow()

    private val _chargingSessions = MutableStateFlow<List<ChargingSessionRecord>>(emptyList())
    val chargingSessions: StateFlow<List<ChargingSessionRecord>> = _chargingSessions.asStateFlow()

    private val _batteryHealth = MutableStateFlow<List<BatteryHealthRecord>>(emptyList())
    val batteryHealth: StateFlow<List<BatteryHealthRecord>> = _batteryHealth.asStateFlow()

    /** Serialises row writes so the periodic progress save and the final save cannot interleave. */
    private val tripWrites = Mutex()

    init {
        refreshAll()
    }

    fun refreshAll() {
        refreshTrips()
        refreshChargingSessions()
        refreshBatteryHealth()
    }

    /** Reloads only the trip list, so a trip write does not re-read the whole database. */
    fun refreshTrips() {
        scope.launch { _trips.value = loadTrips() }
    }

    fun refreshChargingSessions() {
        scope.launch { _chargingSessions.value = loadChargingSessions() }
    }

    fun refreshBatteryHealth() {
        scope.launch { _batteryHealth.value = loadBatteryHealth() }
    }

    suspend fun saveTrip(trip: TripRecord, samples: List<TripSample> = trip.samples) =
        tripWrites.withLock {
            withContext(Dispatchers.IO) {
                upsertTrip(trip)
                db.writableDatabase.delete("trip_samples", "trip_id = ?", arrayOf(trip.id))
                if (samples.isNotEmpty()) insertTripSamples(trip.id, samples)
                refreshTrips()
            }
        }

    /** Saves the in-progress trip row and appends only the samples recorded since the last save. */
    suspend fun saveTripProgress(trip: TripRecord, newSamples: List<TripSample> = emptyList()) =
        tripWrites.withLock {
            withContext(Dispatchers.IO) {
                upsertTrip(trip)
                if (newSamples.isNotEmpty()) insertTripSamples(trip.id, newSamples)
                refreshTrips()
            }
        }

    private fun upsertTrip(trip: TripRecord) {
        val values = ContentValues().apply {
            put("id", trip.id)
            put("start_time", trip.startTime.toEpochMilli())
            put("end_time", trip.endTime?.toEpochMilli())
            put("distance_km", trip.distanceKm)
            put("start_soc", trip.startSocPct)
            put("end_soc", trip.endSocPct)
            put("kwh_used", trip.totalKWhUsed)
            put("kwh_recovered", trip.totalKWhRecovered)
            put("avg_speed", trip.averageSpeedKmH)
            put("max_power", trip.maxPowerKW)
            put("max_regen", trip.maxRegenKW)
            put("vehicle_name", trip.vehicleName)
        }
        db.writableDatabase.insertWithOnConflict("trips", null, values, SQLiteDatabase.CONFLICT_REPLACE)
    }

    private fun insertTripSamples(tripId: String, samples: List<TripSample>) {
        db.writableDatabase.beginTransaction()
        try {
            samples.forEach { sample ->
                db.writableDatabase.insert(
                    "trip_samples",
                    null,
                    ContentValues().apply {
                        put("trip_id", tripId)
                        put("timestamp", sample.timestamp.toEpochMilli())
                        put("latitude", sample.latitude)
                        put("longitude", sample.longitude)
                        put("speed", sample.speedKmH)
                        put("power", sample.powerKW)
                        put("soc", sample.socPct)
                        put("battery_temp", sample.batteryTempC)
                    },
                )
            }
            db.writableDatabase.setTransactionSuccessful()
        } finally {
            db.writableDatabase.endTransaction()
        }
    }

    suspend fun deleteTrip(id: String) = withContext(Dispatchers.IO) {
        db.writableDatabase.delete("trip_samples", "trip_id = ?", arrayOf(id))
        db.writableDatabase.delete("trips", "id = ?", arrayOf(id))
        refreshTrips()
    }

    suspend fun clearAllTrips() = withContext(Dispatchers.IO) {
        db.writableDatabase.delete("trip_samples", null, null)
        db.writableDatabase.delete("trips", null, null)
        refreshTrips()
    }

    suspend fun loadTripSamples(tripId: String): List<TripSample> = withContext(Dispatchers.IO) {
        val samples = mutableListOf<TripSample>()
        db.readableDatabase.rawQuery(
            "SELECT timestamp, latitude, longitude, speed, power, soc, battery_temp FROM trip_samples WHERE trip_id = ? ORDER BY timestamp",
            arrayOf(tripId),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                samples += TripSample(
                    timestamp = Instant.ofEpochMilli(cursor.getLong(0)),
                    latitude = cursor.getDouble(1),
                    longitude = cursor.getDouble(2),
                    speedKmH = cursor.getDouble(3),
                    powerKW = cursor.getDouble(4),
                    socPct = cursor.getDouble(5),
                    batteryTempC = cursor.getDouble(6),
                )
            }
        }
        samples
    }

    suspend fun loadChargingSamples(sessionId: String): List<ChargingSample> = withContext(Dispatchers.IO) {
        val samples = mutableListOf<ChargingSample>()
        db.readableDatabase.rawQuery(
            "SELECT timestamp, soc, power FROM charging_samples WHERE session_id = ? ORDER BY timestamp",
            arrayOf(sessionId),
        ).use { cursor ->
            while (cursor.moveToNext()) {
                samples += ChargingSample(
                    timestamp = Instant.ofEpochMilli(cursor.getLong(0)),
                    socPct = cursor.getDouble(1),
                    powerKW = cursor.getDouble(2),
                )
            }
        }
        samples
    }

    /** Everything the history screens show, in the portable backup shape. */
    suspend fun backupSnapshot(): com.simonkaring.voltlink.core.backup.HistoryBackup = withContext(Dispatchers.IO) {
        val trips = loadTrips().map { trip -> trip.copy(samples = loadTripSamples(trip.id)) }
        com.simonkaring.voltlink.core.backup.HistoryBackup.capture(trips, loadChargingSessions(), loadBatteryHealth())
    }

    /** Applies only the rows a [BackupPlan] decided are missing. */
    suspend fun restore(plan: com.simonkaring.voltlink.core.backup.BackupPlan) = withContext(Dispatchers.IO) {
        plan.trips.forEach { trip -> saveTrip(trip.toRecord(), trip.toSamples()) }
        plan.chargingSessions.forEach { session -> saveChargingSession(session.toRecord()) }
        plan.batteryHealth.forEach { reading ->
            recordBatteryHealth(reading.sohPct, reading.vehicleName, Instant.ofEpochMilli(reading.timestampMs))
        }
        refreshAll()
    }

    suspend fun saveChargingSession(session: ChargingSessionRecord) = withContext(Dispatchers.IO) {
        db.writableDatabase.insertWithOnConflict(
            "charging_sessions",
            null,
            ContentValues().apply {
                put("id", session.id)
                put("start_time", session.startTime.toEpochMilli())
                put("end_time", session.endTime?.toEpochMilli())
                put("start_soc", session.startSocPct)
                put("end_soc", session.endSocPct)
                put("kwh", session.totalKWhDelivered)
                put("peak_power", session.peakPowerKW)
                put("avg_power", session.averagePowerKW)
                put("location_name", session.locationName)
                putNullable("latitude", session.latitude)
                putNullable("longitude", session.longitude)
                putNullable("start_temp", session.startBatteryTempC)
                putNullable("end_temp", session.endBatteryTempC)
                putNullable("start_range", session.startRangeKm)
                putNullable("end_range", session.endRangeKm)
                putNullable("is_dc", session.isDC?.let { if (it) 1 else 0 })
            },
            SQLiteDatabase.CONFLICT_REPLACE,
        )
        db.writableDatabase.delete("charging_samples", "session_id = ?", arrayOf(session.id))
        session.samples.forEach { sample ->
            db.writableDatabase.insert(
                "charging_samples",
                null,
                ContentValues().apply {
                    put("session_id", session.id)
                    put("timestamp", sample.timestamp.toEpochMilli())
                    put("soc", sample.socPct)
                    put("power", sample.powerKW)
                },
            )
        }
        refreshChargingSessions()
    }

    suspend fun deleteChargingSession(id: String) = withContext(Dispatchers.IO) {
        db.writableDatabase.delete("charging_samples", "session_id = ?", arrayOf(id))
        db.writableDatabase.delete("charging_sessions", "id = ?", arrayOf(id))
        refreshChargingSessions()
    }

    /** One reading per day per vehicle; a second reading on the same day updates the first. */
    suspend fun recordBatteryHealth(sohPct: Double, vehicleName: String, at: Instant = Instant.now()) =
        withContext(Dispatchers.IO) {
            if (!sohPct.isFinite() || sohPct !in 50.0..100.0) return@withContext
            // "One reading per day" means the driver's day. A UTC bucket would merge two
            // local evenings west of UTC and split a local day east of it.
            val zone = ZoneId.systemDefault()
            val day = at.atZone(zone).toLocalDate()
            val dayStart = day.atStartOfDay(zone).toInstant().toEpochMilli()
            val dayEnd = day.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
            val existing = db.readableDatabase.rawQuery(
                "SELECT id FROM battery_health WHERE timestamp >= ? AND timestamp < ? AND vehicle_name = ?",
                arrayOf(dayStart.toString(), dayEnd.toString(), vehicleName),
            ).use { if (it.moveToFirst()) it.getLong(0) else null }
            val values = ContentValues().apply {
                put("timestamp", at.toEpochMilli())
                put("soh", sohPct)
                put("vehicle_name", vehicleName)
            }
            if (existing != null) {
                db.writableDatabase.update("battery_health", values, "id = ?", arrayOf(existing.toString()))
            } else {
                db.writableDatabase.insert("battery_health", null, values)
            }
            refreshBatteryHealth()
        }

    private fun ContentValues.putNullable(key: String, value: Double?) {
        if (value == null || !value.isFinite()) putNull(key) else put(key, value)
    }

    private fun ContentValues.putNullable(key: String, value: Int?) {
        if (value == null) putNull(key) else put(key, value)
    }

    private suspend fun loadTrips(): List<TripRecord> = withContext(Dispatchers.IO) {
        val trips = mutableListOf<TripRecord>()
        db.readableDatabase.rawQuery(
            "SELECT id, start_time, end_time, distance_km, start_soc, end_soc, kwh_used, kwh_recovered, avg_speed, max_power, max_regen, vehicle_name FROM trips ORDER BY start_time DESC",
            null,
        ).use { cursor ->
            while (cursor.moveToNext()) {
                trips += TripRecord(
                    id = cursor.getString(0),
                    startTime = Instant.ofEpochMilli(cursor.getLong(1)),
                    endTime = if (cursor.isNull(2)) null else Instant.ofEpochMilli(cursor.getLong(2)),
                    distanceKm = cursor.getDouble(3),
                    startSocPct = cursor.getDouble(4),
                    endSocPct = cursor.getDouble(5),
                    totalKWhUsed = cursor.getDouble(6),
                    totalKWhRecovered = if (cursor.isNull(7)) null else cursor.getDouble(7),
                    averageSpeedKmH = cursor.getDouble(8),
                    maxPowerKW = cursor.getDouble(9),
                    maxRegenKW = cursor.getDouble(10),
                    vehicleName = cursor.getString(11),
                )
            }
        }
        trips
    }

    private suspend fun loadChargingSessions(): List<ChargingSessionRecord> = withContext(Dispatchers.IO) {
        val sessions = mutableListOf<ChargingSessionRecord>()
        db.readableDatabase.rawQuery(
            "SELECT id, start_time, end_time, start_soc, end_soc, kwh, peak_power, avg_power, location_name, latitude, longitude, start_temp, end_temp, start_range, end_range, is_dc FROM charging_sessions ORDER BY start_time DESC",
            null,
        ).use { cursor ->
            while (cursor.moveToNext()) {
                sessions += ChargingSessionRecord(
                    id = cursor.getString(0),
                    startTime = Instant.ofEpochMilli(cursor.getLong(1)),
                    endTime = if (cursor.isNull(2)) null else Instant.ofEpochMilli(cursor.getLong(2)),
                    startSocPct = cursor.getDouble(3),
                    endSocPct = cursor.getDouble(4),
                    totalKWhDelivered = cursor.getDouble(5),
                    peakPowerKW = cursor.getDouble(6),
                    averagePowerKW = cursor.getDouble(7),
                    locationName = cursor.getString(8),
                    latitude = if (cursor.isNull(9)) null else cursor.getDouble(9),
                    longitude = if (cursor.isNull(10)) null else cursor.getDouble(10),
                    startBatteryTempC = if (cursor.isNull(11)) null else cursor.getDouble(11),
                    endBatteryTempC = if (cursor.isNull(12)) null else cursor.getDouble(12),
                    startRangeKm = if (cursor.isNull(13)) null else cursor.getDouble(13),
                    endRangeKm = if (cursor.isNull(14)) null else cursor.getDouble(14),
                    isDC = if (cursor.isNull(15)) null else cursor.getInt(15) != 0,
                )
            }
        }
        // Archived sessions keep their curve: both the card and the detail sheet draw it.
        // One grouped query replaces a per-session query, which cost hundreds of statements
        // per refresh once the history was a few months old.
        val curves = loadAllChargingSamples()
        sessions.map { session -> session.copy(samples = curves[session.id].orEmpty()) }
    }

    private suspend fun loadAllChargingSamples(): Map<String, List<ChargingSample>> = withContext(Dispatchers.IO) {
        val grouped = mutableMapOf<String, MutableList<ChargingSample>>()
        db.readableDatabase.rawQuery(
            "SELECT session_id, timestamp, soc, power FROM charging_samples ORDER BY session_id, timestamp",
            null,
        ).use { cursor ->
            while (cursor.moveToNext()) {
                grouped.getOrPut(cursor.getString(0)) { mutableListOf() } += ChargingSample(
                    timestamp = Instant.ofEpochMilli(cursor.getLong(1)),
                    socPct = cursor.getDouble(2),
                    powerKW = cursor.getDouble(3),
                )
            }
        }
        grouped
    }

    private suspend fun loadBatteryHealth(): List<BatteryHealthRecord> = withContext(Dispatchers.IO) {
        val readings = mutableListOf<BatteryHealthRecord>()
        db.readableDatabase.rawQuery(
            "SELECT timestamp, soh, vehicle_name FROM battery_health ORDER BY timestamp",
            null,
        ).use { cursor ->
            while (cursor.moveToNext()) {
                readings += BatteryHealthRecord(
                    timestamp = Instant.ofEpochMilli(cursor.getLong(0)),
                    sohPct = cursor.getDouble(1),
                    vehicleName = cursor.getString(2),
                )
            }
        }
        readings
    }
}
