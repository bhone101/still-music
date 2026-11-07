package com.stillmusic.player

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable internal fun SleepTimerSheet(remaining: Long, timerAtEnd: Boolean, close: () -> Unit, start: (Int, Boolean) -> Unit) {
    var minutes by rememberSaveable { mutableStateOf(if(remaining > 0) ((remaining + 59999) / 60000).toString() else "25") }
    var endOfSong by rememberSaveable { mutableStateOf(timerAtEnd) }
    val value = timerMinutes(minutes)
    val chipColor = MaterialTheme.colorScheme.onSurface.copy(alpha = .06f)
    ModalBottomSheet(onDismissRequest = close, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp)) {
        Column(Modifier.fillMaxWidth().imePadding().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 16.dp)) {
            Text("Sleep timer", fontSize = 20.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(16.dp))
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(15,30,45,60).forEach { preset ->
                    Surface(onClick = { minutes = preset.toString(); endOfSong = false }, shape = CircleShape, color = chipColor,
                        border = if(!endOfSong && value == preset) BorderStroke(1.5.dp, StillBlue) else null) {
                        Text("$preset min", Modifier.heightIn(min = 48.dp).padding(horizontal = 16.dp, vertical = 14.dp), fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
                Surface(onClick = { endOfSong = true }, shape = CircleShape, color = chipColor, border = if(endOfSong) BorderStroke(1.5.dp, StillBlue) else null) {
                    Text("End of song", Modifier.heightIn(min = 48.dp).padding(horizontal = 16.dp, vertical = 14.dp), fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                }
            }
            Spacer(Modifier.height(16.dp)); Text("Custom", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp)
            Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally)) {
                FilledIconButton(onClick = { minutes = ((value ?: 25)-1).coerceAtLeast(1).toString(); endOfSong = false }, enabled = value != 1,
                    modifier = Modifier.size(48.dp), colors = IconButtonDefaults.filledIconButtonColors(containerColor = chipColor, contentColor = MaterialTheme.colorScheme.onSurface)) {
                    Text("−", Modifier.semantics { contentDescription = "Decrease minutes" }, fontSize = 24.sp)
                }
                OutlinedTextField(minutes, { minutes = it.filter(Char::isDigit).take(4); endOfSong = false }, modifier = Modifier.width(80.dp).semantics { contentDescription = "Custom timer minutes" }, singleLine = true,
                    shape = RoundedCornerShape(12.dp), textStyle = LocalTextStyle.current.copy(fontSize = 20.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), isError = !endOfSong && value == null,
                    colors = OutlinedTextFieldDefaults.colors(unfocusedBorderColor = if(!endOfSong) StillBlue else MaterialTheme.colorScheme.outlineVariant))
                Text("min", color = MaterialTheme.colorScheme.onSurfaceVariant)
                FilledIconButton(onClick = { minutes = ((value ?: 25)+1).coerceAtMost(1440).toString(); endOfSong = false }, enabled = value != 1440,
                    modifier = Modifier.size(48.dp), colors = IconButtonDefaults.filledIconButtonColors(containerColor = chipColor, contentColor = MaterialTheme.colorScheme.onSurface)) {
                    Icon(Icons.Default.Add, "Increase minutes")
                }
            }
            if(!endOfSong && value == null) Text("Enter 1–1440 minutes", color = MaterialTheme.colorScheme.error, fontSize = 12.sp)
            if(remaining > 0 || timerAtEnd) TextButton(onClick = { start(0, false) }, modifier = Modifier.fillMaxWidth()) { Text("Turn off timer") }
            Spacer(Modifier.height(16.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(onClick = close, modifier = Modifier.weight(1f).heightIn(min = 48.dp), shape = RoundedCornerShape(12.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = chipColor, contentColor = MaterialTheme.colorScheme.onSurface)) { Text("Cancel", fontSize = 14.sp) }
                Button(onClick = { start(if(endOfSong) 0 else value ?: return@Button, endOfSong) }, enabled = endOfSong || value != null,
                    modifier = Modifier.weight(1f).heightIn(min = 48.dp), shape = RoundedCornerShape(12.dp)) { Text("Start", fontSize = 14.sp) }
            }
        }
    }
}
