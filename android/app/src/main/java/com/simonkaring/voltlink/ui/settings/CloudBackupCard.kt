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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.simonkaring.voltlink.R
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
            status = context.getString(R.string.backup_folder_saved)
        }
    }

    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(stringResource(R.string.backup_title), color = Theme.textPrimary, fontSize = 14.sp)
            Text(
                stringResource(R.string.backup_subtitle),
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
            stringResource(R.string.backup_hint),
            color = Theme.textSecondary,
            fontSize = 10.sp,
        )
        return
    }

    Spacer(Modifier.height(6.dp))
    Text(
        folderLabel?.let { stringResource(R.string.backup_folder, it) }
            ?: stringResource(R.string.backup_no_folder),
        color = Theme.textPrimary,
        fontSize = 12.sp,
    )
    TextButton(onClick = { folderPicker.launch(null) }, contentPadding = PaddingValues(0.dp)) {
        Text(
            if (folderLabel == null) {
                stringResource(R.string.backup_choose_folder)
            } else {
                stringResource(R.string.backup_change_folder)
            },
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
                        onSuccess = {
                            context.getString(
                                R.string.backup_success,
                                store.trips.value.size,
                                store.chargingSessions.value.size,
                                it,
                            )
                        },
                        onFailure = { context.getString(R.string.backup_failed, it.message ?: "") },
                    )
                    isWorking = false
                }
            },
            enabled = !isWorking && folderLabel != null,
            colors = ButtonDefaults.buttonColors(containerColor = Theme.electricCyan),
        ) {
            Text(
                if (isWorking) stringResource(R.string.backup_working) else stringResource(R.string.backup_now),
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
                            if (plan.isEmpty) context.getString(R.string.backup_all_present) else plan.summary
                        },
                        onFailure = { context.getString(R.string.backup_restore_failed, it.message ?: "") },
                    )
                    isWorking = false
                }
            },
            enabled = !isWorking && folderLabel != null,
            contentPadding = PaddingValues(horizontal = 8.dp),
        ) {
            Text(stringResource(R.string.backup_restore), color = Theme.textSecondary, fontSize = 13.sp)
        }
    }

    Text(
        lastBackup?.let { stringResource(R.string.backup_last, it) } ?: stringResource(R.string.backup_none),
        color = Theme.textSecondary,
        fontSize = 10.sp,
    )
    status?.let { message ->
        Text(message, color = Theme.textSecondary, fontSize = 11.sp)
    }
    Text(
        stringResource(R.string.backup_footer),
        color = Theme.textSecondary,
        fontSize = 10.sp,
    )
}
