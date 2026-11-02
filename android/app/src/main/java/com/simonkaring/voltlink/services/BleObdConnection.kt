package com.simonkaring.voltlink.services

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import com.simonkaring.voltlink.core.bluetooth.BleConstants
import com.simonkaring.voltlink.core.obd.BleConnectionState
import com.simonkaring.voltlink.core.obd.ObdConnection
import com.simonkaring.voltlink.core.obd.ObdLogEntry
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import java.util.UUID

data class BleDeviceInfo(val name: String, val address: String, val rssi: Int)

/**
 * CoreBluetooth → Android BLE port of the iOS `BluetoothManager`: scan, connect, discover a
 * UART service from the known adapter profiles, subscribe to notifications, then serialise
 * commands through a mutex with an ELM-style timeout and stale-response drain.
 */
class BleObdConnection(
    private val context: Context,
    private val scope: CoroutineScope,
) : ObdConnection {
    private val _state = MutableStateFlow<BleConnectionState>(BleConnectionState.Disconnected)
    override val state: StateFlow<BleConnectionState> = _state.asStateFlow()

    private val _log = MutableStateFlow<List<ObdLogEntry>>(emptyList())
    override val log: StateFlow<List<ObdLogEntry>> = _log.asStateFlow()

    private val _discoveredDevices = MutableStateFlow<List<BleDeviceInfo>>(emptyList())
    val discoveredDevices: StateFlow<List<BleDeviceInfo>> = _discoveredDevices.asStateFlow()

    private val bluetoothManager: BluetoothManager? =
        context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    private val adapter: BluetoothAdapter? get() = bluetoothManager?.adapter

    private var gatt: BluetoothGatt? = null
    private var writeCharacteristic: BluetoothGattCharacteristic? = null
    private var notifyCharacteristic: BluetoothGattCharacteristic? = null
    private var discoveryDeferred: CompletableDeferred<Boolean>? = null

    private val commandMutex = Mutex()
    private val bufferLock = Any()
    private val responseBuffer = StringBuilder()
    private var pending: CompletableDeferred<String>? = null
    private var quietJob: kotlinx.coroutines.Job? = null

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device ?: return
            val name = try {
                device.name ?: result.scanRecord?.deviceName
            } catch (e: SecurityException) {
                null
            } ?: return
            val info = BleDeviceInfo(name, device.address, result.rssi)
            val current = _discoveredDevices.value
            _discoveredDevices.value = (current.filterNot { it.address == info.address } + info)
                .sortedByDescending { it.rssi }
        }

        override fun onScanFailed(errorCode: Int) {
            _state.value = BleConnectionState.Error("Bluetooth scan failed (code $errorCode)")
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    val name = safeName(gatt)
                    _state.value = BleConnectionState.Connecting(name)
                    discoveryDeferred = CompletableDeferred()
                    gatt.discoverServices()
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    val name = safeName(gatt)
                    val wasReady = _state.value is BleConnectionState.Ready
                    closeGatt()
                    _state.value = if (wasReady && status != BluetoothGatt.GATT_SUCCESS) {
                        BleConnectionState.Error("Adapter $name disconnected unexpectedly")
                    } else {
                        BleConnectionState.Disconnected
                    }
                }
            }
        }

        @SuppressLint("MissingPermission")
        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                discoveryDeferred?.complete(false)
                return
            }
            val services = gatt.services ?: emptyList()
            // Prefer a known adapter profile, then any service exposing a write+notify pair.
            val known = services.firstOrNull { it.uuid in BleConstants.SUPPORTED_SERVICES }
            val candidates = listOfNotNull(known) + services.filter { it.uuid !in BleConstants.IGNORED_STANDARD_SERVICES }
            for (service in candidates) {
                val writable = service.characteristics.firstOrNull {
                    it.uuid in BleConstants.KNOWN_WRITE_CHARACTERISTICS ||
                        it.properties and (BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0
                } ?: continue
                val notifiable = service.characteristics.firstOrNull {
                    it.uuid in BleConstants.KNOWN_NOTIFY_CHARACTERISTICS ||
                        it.properties and (BluetoothGattCharacteristic.PROPERTY_NOTIFY or BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0
                } ?: writable.takeIf { it.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0 } ?: continue

                writeCharacteristic = writable
                notifyCharacteristic = notifiable
                gatt.setCharacteristicNotification(notifiable, true)
                val cccd = notifiable.getDescriptor(UUID.fromString(BleConstants.CLIENT_CHARACTERISTIC_CONFIG))
                if (cccd != null) {
                    cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    gatt.writeDescriptor(cccd)
                }
                gatt.requestMtu(185)
                _state.value = BleConnectionState.Ready(safeName(gatt))
                discoveryDeferred?.complete(true)
                return
            }
            discoveryDeferred?.complete(false)
        }

        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
            onAdapterData(value)
        }

        // Deprecated overload still called on API < 33 devices.
        @Deprecated("Deprecated in Java")
        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            val value = characteristic.value ?: return
            onAdapterData(value)
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) = Unit
    }

    private fun onAdapterData(value: ByteArray) {
        val text = String(value, Charsets.UTF_8)
        val complete: Boolean
        synchronized(bufferLock) {
            responseBuffer.append(text)
            complete = isComplete(responseBuffer.toString())
        }
        if (complete) {
            finishResponse()
        } else {
            // Multi-frame replies arrive as several notifications; complete on a short quiet gap.
            quietJob?.cancel()
            quietJob = scope.launch {
                delay(120)
                finishResponse()
            }
        }
    }

    private fun isComplete(text: String): Boolean {
        val trimmed = text.trimEnd()
        if (trimmed.isEmpty()) return false
        if (trimmed.contains('>')) return true
        return Regex("(?im)^(OK|NO DATA|ERROR|\\?|STOPPED|SEARCHING\\.\\.\\.).*$").containsMatchIn(trimmed) ||
            trimmed.contains("NO DATA") || trimmed.contains("ERROR")
    }

    private fun finishResponse() {
        val text: String
        synchronized(bufferLock) {
            text = responseBuffer.toString()
            responseBuffer.setLength(0)
        }
        pending?.complete(text)
        pending = null
    }

    override fun startScan() {
        val adapter = adapter
        if (adapter == null || !adapter.isEnabled) {
            _state.value = BleConnectionState.Error("Bluetooth is off or unavailable")
            return
        }
        if (!hasScanPermission()) {
            _state.value = BleConnectionState.Error("Bluetooth permission is required to scan")
            return
        }
        _discoveredDevices.value = emptyList()
        _state.value = BleConnectionState.Scanning
        try {
            val scanner = adapter.bluetoothLeScanner ?: run {
                _state.value = BleConnectionState.Error("BLE scanning is unavailable on this device")
                return
            }
            val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
            scanner.startScan(null, settings, scanCallback)
        } catch (e: SecurityException) {
            _state.value = BleConnectionState.Error("Bluetooth permission is required to scan")
        }
    }

    override fun stopScan() {
        try {
            adapter?.bluetoothLeScanner?.stopScan(scanCallback)
        } catch (e: SecurityException) {
            // Permission revoked mid-scan; nothing to stop.
        }
        if (_state.value is BleConnectionState.Scanning) _state.value = BleConnectionState.Disconnected
    }

    @SuppressLint("MissingPermission")
    override suspend fun connect(deviceAddress: String?) {
        val adapter = adapter ?: run {
            _state.value = BleConnectionState.Error("This device does not support Bluetooth")
            return
        }
        if (!adapter.isEnabled) {
            _state.value = BleConnectionState.Error("Bluetooth is off")
            return
        }
        stopScan()
        val address = deviceAddress
            ?: _discoveredDevices.value.firstOrNull()?.address
            ?: run {
                _state.value = BleConnectionState.Error("No OBD adapter selected")
                return
            }
        val device = try {
            adapter.getRemoteDevice(address)
        } catch (e: IllegalArgumentException) {
            _state.value = BleConnectionState.Error("Unknown adapter address $address")
            return
        }
        val name = try {
            device.name
        } catch (e: SecurityException) {
            null
        } ?: "OBD Adapter"

        _state.value = BleConnectionState.Connecting(name)
        try {
            gatt?.close()
            gatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                device.connectGatt(context, false, gattCallback, android.bluetooth.BluetoothDevice.TRANSPORT_LE)
            } else {
                device.connectGatt(context, false, gattCallback)
            }
        } catch (e: SecurityException) {
            _state.value = BleConnectionState.Error("Bluetooth permission is required to connect")
            return
        }

        val discovered = withTimeoutOrNull(BleConstants.CONNECTION_TIMEOUT_MS) {
            discoveryDeferred?.await() ?: false
        }
        if (discovered != true) {
            closeGatt()
            _state.value = BleConnectionState.Error("Connection to $name timed out")
        }
    }

    override fun disconnect() {
        closeGatt()
        _state.value = BleConnectionState.Disconnected
    }

    @SuppressLint("MissingPermission")
    override suspend fun sendCommand(command: String): Result<String> {
        if (!_state.value.isConnected || gatt == null) {
            return Result.failure(IllegalStateException("BLE not connected"))
        }
        val timeout = if (command.uppercase().startsWith("AT Z")) {
            (BleConstants.DEFAULT_TIMEOUT_MS * 1.5).toLong()
        } else {
            BleConstants.DEFAULT_TIMEOUT_MS
        }

        return commandMutex.withLock {
            val deferred = CompletableDeferred<String>()
            synchronized(bufferLock) {
                responseBuffer.setLength(0)
                pending = deferred
            }
            val writeResult = writeBytes("$command\r")
            if (writeResult.isFailure) {
                clearPending()
                return@withLock Result.failure(writeResult.exceptionOrNull() ?: IllegalStateException("Write failed"))
            }

            val raw = withTimeoutOrNull(timeout) { deferred.await() }
            if (raw == null) {
                clearPending()
                // Let the late reply drain before the next command is written.
                delay(BleConstants.STALE_RESPONSE_DRAIN_DELAY_MS)
                synchronized(bufferLock) { responseBuffer.setLength(0) }
                appendLog(command, "ERROR: Command Timeout")
                Result.failure(java.util.concurrent.TimeoutException("Command Timeout"))
            } else {
                appendLog(command, raw)
                Result.success(raw)
            }
        }
    }

    private fun clearPending() {
        synchronized(bufferLock) {
            pending = null
            responseBuffer.setLength(0)
        }
    }

    @SuppressLint("MissingPermission")
    private suspend fun writeBytes(payload: String): Result<Unit> {
        val gatt = gatt ?: return Result.failure(IllegalStateException("BLE not connected"))
        val characteristic = writeCharacteristic
            ?: return Result.failure(IllegalStateException("Adapter write channel not ready"))
        val bytes = payload.toByteArray(Charsets.UTF_8)
        val chunkSize = 20
        try {
            var offset = 0
            while (offset < bytes.size) {
                val end = minOf(offset + chunkSize, bytes.size)
                val chunk = bytes.copyOfRange(offset, end)
                val writeType = if (characteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0) {
                    BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                } else {
                    BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
                }
                val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    gatt.writeCharacteristic(characteristic, chunk, writeType) == BluetoothStatusCodes.SUCCESS
                } else {
                    @Suppress("DEPRECATION")
                    characteristic.writeType = writeType
                    @Suppress("DEPRECATION")
                    characteristic.value = chunk
                    @Suppress("DEPRECATION")
                    gatt.writeCharacteristic(characteristic)
                }
                if (!ok) return Result.failure(IllegalStateException("Adapter write rejected"))
                offset = end
                delay(20)
            }
            return Result.success(Unit)
        } catch (e: SecurityException) {
            return Result.failure(IllegalStateException("Bluetooth permission is required to write"))
        }
    }

    private fun appendLog(command: String, response: String) {
        _log.value = (_log.value + ObdLogEntry(sent = command, response = response)).takeLast(500)
    }

    override fun clearLog() {
        _log.value = emptyList()
    }

    @SuppressLint("MissingPermission")
    private fun closeGatt() {
        try {
            gatt?.disconnect()
            gatt?.close()
        } catch (e: SecurityException) {
            // Ignore: the link is gone either way.
        }
        gatt = null
        writeCharacteristic = null
        notifyCharacteristic = null
        discoveryDeferred = null
        clearPending()
    }

    @SuppressLint("MissingPermission")
    private fun safeName(gatt: BluetoothGatt): String =
        try {
            gatt.device.name ?: "OBD Adapter"
        } catch (e: SecurityException) {
            "OBD Adapter"
        }

    private fun hasScanPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.checkSelfPermission(android.Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
        } else {
            context.checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        }
    }
}
