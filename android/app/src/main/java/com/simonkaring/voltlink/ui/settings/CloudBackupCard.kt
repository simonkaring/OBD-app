package com.simonkaring.voltlink.ui.settings

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.simonkaring.voltlink.core.backup.CloudBackupService
import com.simonkaring.voltlink.data.HistoryStore
import com.simonkaring.voltlink.ui.theme.Theme
import kotlinx.coroutines.launch

/**
 * Backs up trips, charging sessions and battery-health readings to a folder picked with the
 * system picker (Drive, OneDrive, local storage …) and restores the newest file by merging.
 */
@Composable
fun CloudBackupCard(store: HistoryStore) {
    val context = LocalContext.current
    val service = remember { CloudBackupService(context) }
    var enabled by remember { mutableStateOf(service.enabled) }
    var folderLabel by remember { mutableStateOf(service.folderLabel()) }
    var lastBackup by remember { mutableStateOf(service.lastBackupLabel) }
    var status by remember { mutableStateOf<String?>(null) }
    var isWorking by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    val folderPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            service.rememberFolder(uri)
            enabled = service.enabled
            folderLabel = service.folderLabel()
            status = "Backup folder saved."
        }
    }

    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text("Cloud backup", color = Theme.textPrimary, fontSize = 14.sp)
            Text(
                "Mirror history to a folder you choose",
                color = Theme.textSecondary,
                fontSize = 11.sp,
            )
        }
        Switch(
            checked = enabled,
            onCheckedChange = { value ->
                enabled = value
                service.enabled = value
                if (value && service.folder == null) folderPicker.launch(null)
            },
        )
    }

    if (!enabled) {
        Text(
            "Off by default: trip and charging history stays on this device until you turn this on.",
            color = Theme.textSecondary,
            fontSize = 10.sp,
        )
        return
    }

    Spacer(Modifier.height(6.dp))
    Text(
        folderLabel?.let { "Folder: $it" } ?: "No folder chosen yet",
        color = Theme.textPrimary,
        fontSize = 12.sp,
    )
    TextButton(onClick = { folderPicker.launch(null) }, contentPadding = PaddingValues(0.dp)) {
        Text(
            if (folderLabel == null) "Choose folder" else "Change folder",
            color = Theme.electricCyan,
            fontSize = 12.sp,
        )
    }

    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Button(
            onClick = {
                isWorking = true
                status = null
                scope.launch {
                    val result = service.backup(store)
                    lastBackup = service.lastBackupLabel
                    status = result.fold(
                        onSuccess = { "Backed up ${store.trips.value.size} trips and " +
                            "${store.chargingSessions.value.size} charging sessions to $it." },
                        onFailure = { "Backup failed: ${it.message}" },
                    )
                    isWorking = false
                }
            },
            enabled = !isWorking && folderLabel != null,
            colors = ButtonDefaults.buttonColors(containerColor = Theme.electricCyan),
        ) {
            Text(
                if (isWorking) "Working…" else "Back up now",
                color = Theme.onAccent,
                fontWeight = FontWeight.SemiBold,
            )
        }
        TextButton(
            onClick = {
                isWorking = true
                status = null
                scope.launch {
                    val result = service.restore(store)
                    status = result.fold(
                        onSuccess = { plan ->
                            if (plan.isEmpty) "Everything in the backup is already on this device." else plan.summary
                        },
                        onFailure = { "Restore failed: ${it.message}" },
                    )
                    isWorking = false
                }
            },
            enabled = !isWorking && folderLabel != null,
            contentPadding = PaddingValues(horizontal = 8.dp),
        ) {
            Text("Restore", color = Theme.textSecondary, fontSize = 13.sp)
        }
    }

    Text(
        lastBackup?.let { "Last backup: $it" } ?: "No backup written yet",
        color = Theme.textSecondary,
        fontSize = 10.sp,
    )
    status?.let { message ->
        Text(message, color = Theme.textSecondary, fontSize = 11.sp)
    }
    Text(
        "Files are named voltlink-backup-<date>.json. Restore merges the newest file and never deletes local rows.",
        color = Theme.textSecondary,
        fontSize = 10.sp,
    )
}
