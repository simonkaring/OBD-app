package com.simonkaring.voltlink.data

import android.content.Context
import com.simonkaring.voltlink.core.obd.DtcCode
import com.simonkaring.voltlink.core.obd.DtcSeverity
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/**
 * Read-only DTC definitions: the curated VoltLink seed plus the Wal33D community tables,
 * loaded once from assets. Port of the iOS `DTCLocalDatabase`, including its alias handling
 * and the generic fallback so an unknown code still renders usefully.
 */
class DtcLocalDatabase(context: Context) {
    private val database = mutableMapOf<String, DtcCode>()
    private val definitions = mutableMapOf<String, Map<String, String>>()

    var loadError: String? = null
        private set

    /** Completes once the bundled tables are parsed, so a scan never reads half a database. */
    private val loaded = CompletableDeferred<Unit>()

    init {
        // The Wal33D table is over a megabyte of JSON; parsing it off the main thread keeps
        // app startup inside the activity-start timeout.
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                loadBundleDatabase(context)
                loadWal33d(context)
            } finally {
                loaded.complete(Unit)
            }
        }
    }

    suspend fun awaitLoaded() = loaded.await()

    fun lookup(code: String, manufacturer: String? = null): DtcCode {
        val upperCode = code.uppercase().trim()
        val category = when (upperCode.firstOrNull()) {
            'P' -> "Powertrain"
            'C' -> "Chassis"
            'B' -> "Body"
            'U' -> "Network / CAN"
            else -> "General System"
        }
        val brand = manufacturer?.uppercase()?.trim() ?: ""
        val aliases = mapOf(
            "MERCEDES-BENZ" to "MERCEDES",
            "MERCEDES BENZ" to "MERCEDES",
            "CHEVROLET" to "CHEVY",
            "VW" to "VOLKSWAGEN",
            "GENERAL MOTORS" to "GM",
        )
        val manufacturerDefinition = if (brand == "GENERIC") null else definitions[aliases[brand] ?: brand]?.get(upperCode)

        database[upperCode]?.let { return it }
        val description = definitions["GENERIC"]?.get(upperCode) ?: manufacturerDefinition
        if (description != null) {
            return DtcCode(
                code = upperCode,
                title = description,
                category = category,
                severity = DtcSeverity.UNKNOWN,
                description = description,
                definitionSource = "Wal33D/dtc-database (MIT) · Community definition",
            )
        }
        return DtcCode(
            code = upperCode,
            title = "Diagnostic Code $upperCode",
            category = category,
            severity = DtcSeverity.UNKNOWN,
            description = "Vehicle reported diagnostic trouble code $upperCode. Consult vehicle technical manual.",
            possibleFixes = listOf("Perform system scan using professional diagnostic tool"),
        )
    }

    private fun loadBundleDatabase(context: Context) {
        try {
            val text = context.assets.open("dtc_definitions.json").bufferedReader().use { it.readText() }
            val array = JSONArray(text)
            loadError = null
            for (index in 0 until array.length()) {
                val item = array.getJSONObject(index)
                val code = item.getString("code").uppercase()
                database[code] = DtcCode(
                    code = code,
                    title = item.optString("title", code),
                    category = item.optString("category", "Powertrain"),
                    severity = DtcSeverity.from(item.optString("severity")),
                    description = item.optString("description", ""),
                    symptoms = item.optJSONArray("symptoms").toStringList(),
                    possibleFixes = item.optJSONArray("possibleFixes").toStringList(),
                )
            }
        } catch (e: Exception) {
            loadError = "DTC definitions could not be loaded — code descriptions are limited."
        }
    }

    private fun loadWal33d(context: Context) {
        try {
            val text = context.assets.open("wal33d_dtc.json").bufferedReader().use { it.readText() }
            val root = JSONObject(text)
            val defs = root.getJSONObject("definitions")
            for (brand in defs.keys()) {
                val table = defs.getJSONObject(brand)
                val entries = buildMap {
                    for (code in table.keys()) put(code.uppercase(), table.getString(code))
                }
                definitions[brand.uppercase()] = entries
            }
        } catch (e: Exception) {
            loadError = listOfNotNull(
                loadError,
                "Wal33D DTC definitions could not be loaded — code descriptions are limited.",
            ).joinToString(" ")
        }
    }

    private fun JSONArray?.toStringList(): List<String> {
        if (this == null) return emptyList()
        return (0 until length()).mapNotNull { optString(it, null) }
    }
}
