package com.simonkaring.voltlink.core.backup

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import com.simonkaring.voltlink.data.HistoryStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * Opt-in mirror of the recorded history into a folder the user picks — Google Drive, OneDrive,
 * a NAS share or local storage, whichever document provider is installed.
 *
 * This is the Android counterpart of the iOS iCloud mirror, with the same rule: a local OBD
 * recorder never uploads history unless the owner turns it on and chooses a destination.
 * Every backup is a plain [HistoryBackup] JSON file; restore merges by id and never deletes.
 */
class CloudBackupService(private val context: Context) {
    companion object {
        const val PREF_FILE = "voltlink_backup"
        const val KEY_ENABLED = "cloud_backup_enabled"
        const val KEY_FOLDER = "cloud_backup_folder"
        const val KEY_LAST_BACKUP = "cloud_backup_last_ms"
        const val FILE_PREFIX = "voltlink-backup-"
        const val MIME_TYPE = "application/json"
        private val FILE_SUFFIX = ".json"
        private val TIMESTAMP = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss")
        private val DISPLAYED = DateTimeFormatter.ofPattern("d MMM yyyy, HH:mm")
    }

    private val prefs = context.getSharedPreferences(PREF_FILE, Context.MODE_PRIVATE)
    private val resolver get() = context.contentResolver

    var enabled: Boolean
        get() = prefs.getBoolean(KEY_ENABLED, false)
        set(value) = prefs.edit().putBoolean(KEY_ENABLED, value).apply()

    var folder: Uri?
        get() = prefs.getString(KEY_FOLDER, null)?.let(Uri::parse)
        private set(value) = prefs.edit().putString(KEY_FOLDER, value?.toString()).apply()

    val lastBackupAt: Instant? get() = prefs.getLong(KEY_LAST_BACKUP, 0L).takeIf { it > 0 }?.let(Instant::ofEpochMilli)

    val lastBackupLabel: String?
        get() = lastBackupAt?.let { DISPLAYED.format(it.atZone(ZoneId.systemDefault())) }

    /** Keeps the granted read/write access across launches. */
    fun rememberFolder(uri: Uri) {
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        runCatching { resolver.takePersistableUriPermission(uri, flags) }
        folder = uri
        prefs.edit().putBoolean(KEY_ENABLED, true).apply()
    }

    fun forgetFolder() {
        folder?.let { uri ->
            runCatching {
                resolver.releasePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            }
        }
        folder = null
    }

    /** "Drive/VoltLink" for the chosen tree, or null when nothing has been picked yet. */
    fun folderLabel(): String? {
        val tree = folder ?: return null
        return runCatching {
            val base = baseDocumentUri(tree)
            resolver.query(base, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)
                ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
        }.getOrNull() ?: "Selected folder"
    }

    /** Writes a timestamped snapshot; returns the file name that was created. */
    suspend fun backup(store: HistoryStore, at: Instant = Instant.now()): Result<String> = withContext(Dispatchers.IO) {
        runCatching {
            val tree = requireFolder()
            val snapshot = store.backupSnapshot()
            val name = FILE_PREFIX + TIMESTAMP.format(at.atZone(ZoneId.systemDefault())) + FILE_SUFFIX
            val fileUri = DocumentsContract.createDocument(resolver, baseDocumentUri(tree), MIME_TYPE, name)
                ?: error("the folder rejected the new file")
            resolver.openOutputStream(fileUri)?.use { stream ->
                stream.write(snapshot.toJson().toByteArray(Charsets.UTF_8))
            } ?: error("the folder could not be written")
            prefs.edit().putLong(KEY_LAST_BACKUP, at.toEpochMilli()).apply()
            name
        }
    }

    /** Reads the newest backup in the folder and merges the rows this device does not have. */
    suspend fun restore(store: HistoryStore): Result<BackupPlan> = withContext(Dispatchers.IO) {
        runCatching {
            val tree = requireFolder()
            val newest = backups(tree).maxByOrNull { it.modifiedMs } ?: error("no VoltLink backup in this folder")
            val text = resolver.openInputStream(newest.uri)?.bufferedReader()?.use { it.readText() }
                ?: error("the backup file could not be read")
            val snapshot = HistoryBackup.fromJson(text)
            val plan = BackupPlan.of(
                backup = snapshot,
                existingTripIds = store.trips.value.map { it.id }.toSet(),
                existingSessionIds = store.chargingSessions.value.map { it.id }.toSet(),
                existingHealthDayKeys = store.batteryHealth.value
                    .map { BackupBatteryHealth(it.timestamp.toEpochMilli(), it.sohPct, it.vehicleName).dayKey }
                    .toSet(),
            )
            store.restore(plan)
            plan
        }
    }

    private data class BackupFile(val name: String, val uri: Uri, val modifiedMs: Long)

    private fun backups(tree: Uri): List<BackupFile> {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        val files = mutableListOf<BackupFile>()
        resolver.query(children, columns, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val name = cursor.getString(1) ?: continue
                if (!name.startsWith(FILE_PREFIX) || !name.endsWith(FILE_SUFFIX)) continue
                files += BackupFile(
                    name = name,
                    uri = DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(0)),
                    modifiedMs = if (cursor.isNull(2)) 0L else cursor.getLong(2),
                )
            }
        }
        return files
    }

    private fun requireFolder(): Uri = folder ?: error("choose a backup folder first")

    private fun baseDocumentUri(tree: Uri): Uri =
        DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
}
