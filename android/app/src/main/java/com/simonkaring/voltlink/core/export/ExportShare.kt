package com.simonkaring.voltlink.core.export

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/** Writes an export into the app cache and hands it to the Android share sheet. */
object ExportShare {
    private const val MIME_CSV = "text/csv"
    private const val MIME_GPX = "application/gpx+xml"
    private const val MIME_JSON = "application/json"

    const val csvMimeType = MIME_CSV
    const val gpxMimeType = MIME_GPX
    const val jsonMimeType = MIME_JSON

    /** The other apps that can receive a route file; used to hide the GPX action when none do. */
    fun hasReceiver(context: Context, mimeType: String): Boolean =
        Intent(Intent.ACTION_SEND).setType(mimeType).let { intent ->
            context.packageManager.queryIntentActivities(intent, 0).isNotEmpty()
        }

    suspend fun share(context: Context, fileName: String, mimeType: String, content: String) {
        val uri = withContext(Dispatchers.IO) {
            val directory = File(context.cacheDir, "exports").apply { mkdirs() }
            // Keep the cache from growing across repeated exports of the same session.
            directory.listFiles()?.forEach { it.delete() }
            val file = File(directory, fileName)
            file.writeText(content)
            FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        }
        val send = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, fileName)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(
            Intent.createChooser(send, "Export $fileName").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }
}
