package com.simonkaring.voltlink.data

import android.content.Context
import com.simonkaring.voltlink.core.vehicles.VehicleProfileId
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class DistanceUnit(val label: String) { KILOMETERS("km"), MILES("mi") }

enum class TemperatureUnit(val label: String) { CELSIUS("°C"), FAHRENHEIT("°F") }

enum class PowerUnit(val label: String) { KILOWATT("kW"), HORSEPOWER("hp") }

/**
 * Persisted user preferences. Telemetry itself stays SI; conversions happen only at render
 * time, matching the iOS `UnitPreferences` contract.
 */
class SettingsStore(context: Context) {
    private val prefs = context.getSharedPreferences("voltlink_settings", Context.MODE_PRIVATE)

    private val _selectedProfile = MutableStateFlow(
        prefs.getString(KEY_PROFILE, null)
            ?.let { name -> VehicleProfileId.entries.firstOrNull { it.name == name } }
            ?: VehicleProfileId.MERCEDES_EQ_A250,
    )
    val selectedProfile: StateFlow<VehicleProfileId> = _selectedProfile.asStateFlow()

    private val _selectedModelId = MutableStateFlow(prefs.getString(KEY_MODEL_ID, null))
    val selectedModelId: StateFlow<String?> = _selectedModelId.asStateFlow()

    private val _selectedModelName = MutableStateFlow(prefs.getString(KEY_MODEL_NAME, null))
    val selectedModelName: StateFlow<String?> = _selectedModelName.asStateFlow()

    private val _distanceUnit = MutableStateFlow(
        prefs.getString(KEY_DISTANCE, null)?.let { DistanceUnit.valueOf(it) } ?: DistanceUnit.KILOMETERS,
    )
    val distanceUnit: StateFlow<DistanceUnit> = _distanceUnit.asStateFlow()

    private val _temperatureUnit = MutableStateFlow(
        prefs.getString(KEY_TEMPERATURE, null)?.let { TemperatureUnit.valueOf(it) } ?: TemperatureUnit.CELSIUS,
    )
    val temperatureUnit: StateFlow<TemperatureUnit> = _temperatureUnit.asStateFlow()

    private val _powerUnit = MutableStateFlow(
        prefs.getString(KEY_POWER, null)?.let { PowerUnit.valueOf(it) } ?: PowerUnit.KILOWATT,
    )
    val powerUnit: StateFlow<PowerUnit> = _powerUnit.asStateFlow()

    private val _demoMode = MutableStateFlow(prefs.getBoolean(KEY_DEMO, true))
    val demoMode: StateFlow<Boolean> = _demoMode.asStateFlow()

    private val _chargeTargetPercent = MutableStateFlow(prefs.getInt(KEY_CHARGE_TARGET, 80))
    val chargeTargetPercent: StateFlow<Int> = _chargeTargetPercent.asStateFlow()

    private val _tripCostPerKWh = MutableStateFlow(prefs.getFloat(KEY_TRIP_COST, 0f).toDouble())
    val tripCostPerKWh: StateFlow<Double> = _tripCostPerKWh.asStateFlow()

    private val _notificationsEnabled = MutableStateFlow(prefs.getBoolean(KEY_NOTIFICATIONS, false))
    val notificationsEnabled: StateFlow<Boolean> = _notificationsEnabled.asStateFlow()

    private val _dashboardLayout = MutableStateFlow(
        DashboardLayout.decode(prefs.getString(KEY_DASHBOARD_LAYOUT, null)),
    )
    val dashboardLayout: StateFlow<DashboardLayout> = _dashboardLayout.asStateFlow()

    private val _carTileLayout = MutableStateFlow(
        CarTileLayout.decode(prefs.getString(KEY_CAR_LAYOUT, null)),
    )
    val carTileLayout: StateFlow<CarTileLayout> = _carTileLayout.asStateFlow()

    var lastAdapterAddress: String?
        get() = prefs.getString(KEY_LAST_ADAPTER, null)
        set(value) = prefs.edit().putString(KEY_LAST_ADAPTER, value).apply()

    fun setProfile(id: VehicleProfileId) {
        _selectedProfile.value = id
        prefs.edit().putString(KEY_PROFILE, id.name).apply()
    }

    /** Records the catalog row picked in Settings; null falls back to the profile's own name. */
    fun setSelectedModel(id: String?, displayName: String?) {
        _selectedModelId.value = id
        _selectedModelName.value = displayName
        prefs.edit().putString(KEY_MODEL_ID, id).putString(KEY_MODEL_NAME, displayName).apply()
    }

    fun setDistanceUnit(unit: DistanceUnit) {
        _distanceUnit.value = unit
        prefs.edit().putString(KEY_DISTANCE, unit.name).apply()
    }

    fun setTemperatureUnit(unit: TemperatureUnit) {
        _temperatureUnit.value = unit
        prefs.edit().putString(KEY_TEMPERATURE, unit.name).apply()
    }

    fun setPowerUnit(unit: PowerUnit) {
        _powerUnit.value = unit
        prefs.edit().putString(KEY_POWER, unit.name).apply()
    }

    fun setDemoMode(enabled: Boolean) {
        _demoMode.value = enabled
        prefs.edit().putBoolean(KEY_DEMO, enabled).apply()
    }

    fun setChargeTargetPercent(percent: Int) {
        _chargeTargetPercent.value = percent.coerceIn(50, 100)
        prefs.edit().putInt(KEY_CHARGE_TARGET, _chargeTargetPercent.value).apply()
    }

    fun setTripCostPerKWh(value: Double) {
        _tripCostPerKWh.value = value
        prefs.edit().putFloat(KEY_TRIP_COST, value.toFloat()).apply()
    }

    fun setNotificationsEnabled(enabled: Boolean) {
        _notificationsEnabled.value = enabled
        prefs.edit().putBoolean(KEY_NOTIFICATIONS, enabled).apply()
    }

    fun setDashboardLayout(layout: DashboardLayout) {
        _dashboardLayout.value = layout
        prefs.edit().putString(KEY_DASHBOARD_LAYOUT, layout.encode()).apply()
    }

    fun setCarTileLayout(layout: CarTileLayout) {
        _carTileLayout.value = layout
        prefs.edit().putString(KEY_CAR_LAYOUT, layout.encode()).apply()
    }

    companion object {
        private const val KEY_PROFILE = "selected_profile"
        private const val KEY_MODEL_ID = "selected_model_id"
        private const val KEY_MODEL_NAME = "selected_model_name"
        private const val KEY_DISTANCE = "distance_unit"
        private const val KEY_TEMPERATURE = "temperature_unit"
        private const val KEY_POWER = "power_unit"
        private const val KEY_DEMO = "demo_mode"
        private const val KEY_CHARGE_TARGET = "charge_target"
        private const val KEY_TRIP_COST = "trip_cost_per_kwh"
        private const val KEY_NOTIFICATIONS = "notifications_enabled"
        private const val KEY_DASHBOARD_LAYOUT = "dashboard_layout"
        private const val KEY_CAR_LAYOUT = "car_tile_layout"
        private const val KEY_LAST_ADAPTER = "last_adapter"
    }
}

/** Display-unit conversions. Telemetry stays SI; exports always use SI. */
object UnitFormatter {
    fun speed(kmh: Double, unit: DistanceUnit): Double = if (unit == DistanceUnit.MILES) kmh * 0.621371 else kmh

    fun distance(km: Double, unit: DistanceUnit): Double = if (unit == DistanceUnit.MILES) km * 0.621371 else km

    fun temperature(celsius: Double, unit: TemperatureUnit): Double =
        if (unit == TemperatureUnit.FAHRENHEIT) celsius * 9.0 / 5.0 + 32.0 else celsius

    fun power(kw: Double, unit: PowerUnit): Double = if (unit == PowerUnit.HORSEPOWER) kw * 1.34102 else kw

    fun speedLabel(unit: DistanceUnit): String = if (unit == DistanceUnit.MILES) "mph" else "km/h"

    fun distanceLabel(unit: DistanceUnit): String = if (unit == DistanceUnit.MILES) "mi" else "km"

    fun powerLabel(unit: PowerUnit): String = unit.label
}
