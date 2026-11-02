package com.simonkaring.voltlink.data

import android.content.Context
import com.simonkaring.voltlink.core.vehicles.ServiceReminderStore

/** Persists service-interval readings the same way iOS keeps them in `UserDefaults`. */
class PreferencesServiceReminderStore(context: Context) : ServiceReminderStore {
    private val prefs = context.applicationContext.getSharedPreferences("service_reminders", Context.MODE_PRIVATE)

    override fun getDouble(key: String): Double? =
        if (prefs.contains(key)) prefs.getFloat(key, 0f).toDouble() else null

    override fun putDouble(key: String, value: Double) {
        prefs.edit().putFloat(key, value.toFloat()).apply()
    }

    override fun getLong(key: String): Long? = if (prefs.contains(key)) prefs.getLong(key, 0L) else null

    override fun putLong(key: String, value: Long) {
        prefs.edit().putLong(key, value).apply()
    }
}
