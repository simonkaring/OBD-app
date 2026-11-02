package com.simonkaring.voltlink.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.simonkaring.voltlink.R
import com.simonkaring.voltlink.core.ai.AIKeyStore
import com.simonkaring.voltlink.core.ai.AILogAnalyzer
import com.simonkaring.voltlink.core.ai.AILogAnalyzerError
import com.simonkaring.voltlink.core.obd.ObdLogEntry
import com.simonkaring.voltlink.ui.theme.Theme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Developer card that mirrors the iOS "AI log analyzer": the key is encrypted with the Android
 * Keystore, and the raw log in the terminal above is sent to the chosen provider on demand.
 */
@Composable
fun AILogAnalysisCard(log: List<ObdLogEntry>, vehicleName: String) {
    val context = LocalContext.current
    val keyStore = remember { AIKeyStore(context) }
    var key by remember { mutableStateOf(keyStore.read()) }
    var savedKey by remember { mutableStateOf(keyStore.read()) }
    var showKey by remember { mutableStateOf(false) }
    var isAnalyzing by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf(keyStore.errorMessage) }
    val scope = rememberCoroutineScope()

    Text(
        stringResource(R.string.ai_hint),
        color = Theme.textSecondary,
        fontSize = 11.sp,
    )
    Spacer(Modifier.height(8.dp))

    OutlinedTextField(
        value = key,
        onValueChange = { key = it.trim() },
        modifier = Modifier.fillMaxWidth(),
        singleLine = true,
        label = { Text(stringResource(R.string.ai_key_label), fontSize = 11.sp) },
        visualTransformation = if (showKey) VisualTransformation.None else PasswordVisualTransformation(),
        colors = OutlinedTextFieldDefaults.colors(
            focusedTextColor = Theme.textPrimary,
            unfocusedTextColor = Theme.textPrimary,
            focusedBorderColor = Theme.electricCyan,
            unfocusedBorderColor = Theme.divider,
            focusedLabelColor = Theme.textSecondary,
            unfocusedLabelColor = Theme.textSecondary,
            cursorColor = Theme.electricCyan,
        ),
    )

    Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
        TextButton(onClick = { showKey = !showKey }, contentPadding = PaddingValues(0.dp)) {
            Text(
                if (showKey) stringResource(R.string.ai_hide_key) else stringResource(R.string.ai_show_key),
                color = Theme.textSecondary,
                fontSize = 12.sp,
            )
        }
        Spacer(Modifier.weight(1f))
        TextButton(
            onClick = {
                keyStore.save(key)
                savedKey = keyStore.read()
                error = keyStore.errorMessage
                result = null
            },
            contentPadding = PaddingValues(0.dp),
        ) {
            Text(stringResource(R.string.ai_save_key), color = Theme.electricCyan, fontSize = 12.sp)
        }
    }

    Row(
        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Button(
            onClick = {
                isAnalyzing = true
                error = null
                result = null
                scope.launch {
                    try {
                        result = withContext(Dispatchers.IO) {
                            AILogAnalyzer.analyze(log.takeLast(120), vehicleName, savedKey)
                        }
                    } catch (e: AILogAnalyzerError) {
                        error = e.message
                    } catch (e: Exception) {
                        error = context.getString(
                            R.string.ai_failed,
                            e.message ?: e.javaClass.simpleName,
                        )
                    } finally {
                        isAnalyzing = false
                    }
                }
            },
            enabled = !isAnalyzing && log.isNotEmpty() && savedKey.isNotEmpty(),
            colors = ButtonDefaults.buttonColors(containerColor = Theme.electricCyan),
        ) {
            Text(
                if (isAnalyzing) stringResource(R.string.ai_analyzing) else stringResource(R.string.ai_analyze),
                color = Theme.onAccent,
                fontWeight = FontWeight.SemiBold,
            )
        }
        if (isAnalyzing) {
            CircularProgressIndicator(
                modifier = Modifier.height(18.dp),
                color = Theme.electricCyan,
                strokeWidth = 2.dp,
            )
        } else {
            Text(
                stringResource(R.string.ai_captured, log.size),
                color = Theme.textSecondary,
                fontSize = 11.sp,
            )
        }
    }

    if (savedKey.isEmpty()) {
        Text(
            stringResource(R.string.ai_need_key),
            color = Theme.textSecondary,
            fontSize = 10.sp,
        )
    }

    error?.let { message ->
        Spacer(Modifier.height(8.dp))
        Text(message, color = Theme.criticalRed, fontSize = 12.sp)
    }

    result?.let { text ->
        Spacer(Modifier.height(8.dp))
        SelectionContainer {
            Text(
                text,
                color = Theme.textPrimary,
                fontSize = 12.sp,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 260.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(Theme.faintFill)
                    .verticalScroll(rememberScrollState())
                    .padding(10.dp),
            )
        }
    }
}
