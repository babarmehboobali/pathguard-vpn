package com.ali_babar.pathguard_vpn.vpn

import android.net.TrafficStats
import kotlinx.coroutines.*
import java.io.File

class TrafficStatsMonitor {
    private var job: Job? = null

    fun start(onUpdate: (bytesIn: Long, bytesOut: Long) -> Unit) {
        stop()
        job = CoroutineScope(Dispatchers.IO + SupervisorJob()).launch {
            val basePair = readTunOrTotalBytes()
            val baseRx = basePair.first
            val baseTx = basePair.second

            while (isActive) {
                delay(1000)
                val current = readTunOrTotalBytes()
                val totalRx = (current.first - baseRx).coerceAtLeast(0L)
                val totalTx = (current.second - baseTx).coerceAtLeast(0L)
                onUpdate(totalRx, totalTx)
            }
        }
    }

    private fun readTunOrTotalBytes(): Pair<Long, Long> {
        // 1. Prefer reading directly from /proc/net/dev for tun0/tun1 so counters reflect real tunnel traffic
        try {
            val lines = File("/proc/net/dev").readLines()
            for (line in lines) {
                val trimmed = line.trim()
                if (trimmed.startsWith("tun0:") || trimmed.startsWith("tun1:")) {
                    val afterColon = trimmed.substringAfter(":").trim()
                    val parts = afterColon.split(Regex("\\s+"))
                    if (parts.size >= 9) {
                        val rx = parts[0].toLongOrNull() ?: 0L
                        val tx = parts[8].toLongOrNull() ?: 0L
                        if (rx > 0L || tx > 0L) {
                            return Pair(rx, tx)
                        }
                    }
                }
            }
        } catch (_: Exception) {}

        // 2. Fallback to device-wide TrafficStats
        val rx = TrafficStats.getTotalRxBytes().coerceAtLeast(0L)
        val tx = TrafficStats.getTotalTxBytes().coerceAtLeast(0L)
        return Pair(rx, tx)
    }

    fun stop() {
        job?.cancel()
        job = null
    }
}

