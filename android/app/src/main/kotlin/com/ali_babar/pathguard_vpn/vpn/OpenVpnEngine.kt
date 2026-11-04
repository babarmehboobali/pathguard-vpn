package com.ali_babar.pathguard_vpn.vpn

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.TrafficStats
import android.os.IBinder
import android.preference.PreferenceManager
import android.util.Base64
import de.blinkt.openvpn.VpnProfile
import de.blinkt.openvpn.core.ConfigParser
import de.blinkt.openvpn.core.ConnectionStatus
import de.blinkt.openvpn.core.IOpenVPNServiceInternal
import de.blinkt.openvpn.core.OpenVPNService
import de.blinkt.openvpn.core.ProfileManager
import de.blinkt.openvpn.core.VPNLaunchHelper
import de.blinkt.openvpn.core.VpnStatus
import java.io.StringReader
import java.net.HttpURLConnection
import java.net.NetworkInterface
import java.net.URL
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class OpenVpnEngine(
    private val context: Context,
    private val onProgress: (String) -> Unit,
    private val onConnected: (country: String, ip: String) -> Unit,
    private val onError: (String) -> Unit
) : VpnEngine, VpnStatus.StateListener {

    private val cancelled = AtomicBoolean(false)
    private val isBound = AtomicBoolean(false)
    private val hasSeenActive = AtomicBoolean(false)
    private val connectedLatch = CountDownLatch(1)
    private val disconnectLatch = CountDownLatch(1)

    @Volatile
    private var remoteService: IOpenVPNServiceInternal? = null
    @Volatile
    private var lastOpenVpnError: String? = null
    private var targetCountry: String = "auto"
    private var targetIp: String = "vpn-gate"

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            val svc = IOpenVPNServiceInternal.Stub.asInterface(binder)
            remoteService = svc
            if (cancelled.get()) {
                try {
                    svc?.stopVPN(false)
                } catch (_: Exception) {}
                unbindSafe()
                disconnectLatch.countDown()
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            remoteService = null
            disconnectLatch.countDown()
        }
    }

    fun start(
        configBase64: String,
        preferUdp: Boolean,
        disallowedApps: List<String>,
        countryCode: String?,
        serverIp: String?,
        forceTcp443: Boolean = false
    ) {
        cancelled.set(false)
        hasSeenActive.set(false)
        targetCountry = countryCode?.takeIf { it.isNotBlank() } ?: "auto"
        targetIp = serverIp?.takeIf { it.isNotBlank() } ?: "vpn-gate"

        if (configBase64.isBlank()) {
            onError("Empty OpenVPN config")
            return
        }

        val rawConfig = try {
            Base64.decode(configBase64, Base64.DEFAULT).toString(Charsets.UTF_8)
        } catch (_: Exception) {
            onError("Invalid Base64 config")
            return
        }

        try {
            var patched = rawConfig
            if (forceTcp443) {
                patched = patched
                    .replace(Regex("proto\\s+udp\\d*", RegexOption.IGNORE_CASE), "proto tcp-client")
                    .replace(Regex("proto\\s+tcp\\b", RegexOption.IGNORE_CASE), "proto tcp-client")
                patched = patched.replace(
                    Regex("remote\\s+(\\S+)\\s+\\d+", RegexOption.IGNORE_CASE),
                    "remote $1 443"
                )
            }
            if (!patched.contains("data-ciphers")) {
                patched += "\ndata-ciphers AES-128-CBC:AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305\ncipher AES-128-CBC\n"
            }
            if (!patched.contains("connect-timeout")) {
                patched += "\nconnect-timeout 10\nconnect-retry-max 1\n"
            }

            val parser = ConfigParser()
            parser.parseConfig(StringReader(patched))
            val profile: VpnProfile = parser.convertProfile().apply {
                mName = if (forceTcp443) "PathGuard_Stealth_TCP443" else "PathGuard_Free"
                mAllowedAppsVpnAreDisallowed = true
                mAllowedAppsVpn = HashSet<String>(disallowedApps)
                mUseDefaultRoute = true
            }

            if (cancelled.get() || Thread.currentThread().isInterrupted) return

            onProgress("Connecting to $targetIp…")
            clearAlwaysOnPrefs(context)
            ProfileManager.setTemporaryProfile(context, profile)
            VpnStatus.addStateListener(this)

            val bound = context.bindService(
                Intent(context, OpenVPNService::class.java).apply {
                    action = OpenVPNService.START_SERVICE
                },
                connection,
                Context.BIND_AUTO_CREATE
            )
            isBound.set(bound)

            if (cancelled.get() || Thread.currentThread().isInterrupted) {
                stop()
                return
            }

            VPNLaunchHelper.startOpenVpn(profile, context, "user", true)

            val connected = try {
                connectedLatch.await(12, TimeUnit.SECONDS)
            } catch (_: InterruptedException) {
                false
            }

            if (cancelled.get() || Thread.currentThread().isInterrupted) {
                stop()
                return
            }

            if (!connected || lastOpenVpnError != null) {
                val err = lastOpenVpnError ?: "Server $targetIp timed out"
                stop()
                onError(err)
                return
            }

            onProgress("Verifying tunnel traffic…")
            val verified = verifyTunnelTraffic()
            if (cancelled.get() || Thread.currentThread().isInterrupted) {
                stop()
                return
            }

            if (!verified) {
                stop()
                onError("Server $targetIp connected but no traffic flowed")
                return
            }

            onConnected(targetCountry, targetIp)
        } catch (e: Exception) {
            stop()
            if (!cancelled.get()) {
                onError(e.message ?: "OpenVPN launch failed")
            }
        }
    }

    private fun isTunInterfaceUp(): Boolean {
        return try {
            val interfaces = Collections.list(NetworkInterface.getNetworkInterfaces())
            interfaces.any { nif ->
                nif.isUp && (nif.name.startsWith("tun") || nif.name.startsWith("tap"))
            }
        } catch (_: Exception) {
            true
        }
    }

    private fun verifyTunnelTraffic(): Boolean {
        if (!isTunInterfaceUp()) return false
        val startRx = TrafficStats.getTotalRxBytes()
        val testUrls = listOf(
            "http://connectivitycheck.gstatic.com/generate_204",
            "https://cp.cloudflare.com/generate_204",
            "http://example.com"
        )
        for (url in testUrls) {
            if (cancelled.get() || Thread.currentThread().isInterrupted) return false
            try {
                val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 4_000
                    readTimeout = 4_000
                    instanceFollowRedirects = false
                }
                val code = conn.responseCode
                conn.disconnect()
                if (code in 200..399) {
                    return true
                }
            } catch (_: Exception) {}
        }
        val deltaRx = TrafficStats.getTotalRxBytes() - startRx
        return isTunInterfaceUp() && deltaRx > 512L
    }

    override fun updateState(
        state: String?,
        logMessage: String?,
        localizedResId: Int,
        level: ConnectionStatus?,
        intent: Intent?
    ) {
        if (cancelled.get()) {
            try {
                remoteService?.stopVPN(false)
            } catch (_: Exception) {}
            return
        }

        when (level) {
            ConnectionStatus.LEVEL_CONNECTED -> {
                hasSeenActive.set(true)
                connectedLatch.countDown()
            }
            ConnectionStatus.LEVEL_CONNECTING_SERVER_REPLIED -> {
                hasSeenActive.set(true)
                onProgress("Authenticating with $targetIp…")
            }
            ConnectionStatus.LEVEL_CONNECTING_NO_SERVER_REPLY_YET,
            ConnectionStatus.LEVEL_START -> {
                hasSeenActive.set(true)
                onProgress("Handshaking with $targetIp…")
            }
            ConnectionStatus.LEVEL_AUTH_FAILED -> {
                hasSeenActive.set(true)
                lastOpenVpnError = "Authentication failed on $targetIp"
                connectedLatch.countDown()
                if (!cancelled.get()) {
                    onError(lastOpenVpnError!!)
                }
            }
            ConnectionStatus.LEVEL_NOTCONNECTED -> {
                if (hasSeenActive.get()) {
                    lastOpenVpnError = logMessage?.takeIf { it.isNotBlank() } ?: "Connection closed by $targetIp"
                    connectedLatch.countDown()
                    disconnectLatch.countDown()
                    if (!cancelled.get()) {
                        onError(lastOpenVpnError!!)
                    }
                }
            }
            else -> {}
        }
    }

    override fun setConnectedVPN(uuid: String?) {}

    override fun stop() {
        cancelled.set(true)
        connectedLatch.countDown()
        VpnStatus.removeStateListener(this)
        clearAlwaysOnPrefs(context)

        try {
            ProfileManager.setConnectedVpnProfileDisconnected(context)
        } catch (_: Exception) {}

        val svc = remoteService
        if (svc != null) {
            try {
                svc.stopVPN(false)
            } catch (_: Exception) {}
        }

        unbindSafe()

        try {
            context.stopService(Intent(context, OpenVPNService::class.java))
        } catch (_: Exception) {}

        try {
            disconnectLatch.await(800, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {}
    }

    private fun unbindSafe() {
        if (isBound.compareAndSet(true, false)) {
            try {
                context.unbindService(connection)
            } catch (_: Exception) {}
        }
    }

    companion object {
        @Suppress("DEPRECATION")
        fun clearAlwaysOnPrefs(context: Context) {
            try {
                PreferenceManager.getDefaultSharedPreferences(context).edit()
                    .remove("alwaysOnVpn")
                    .remove("lastConnectedVpn")
                    .remove("lastConnectedProfile")
                    .commit()
            } catch (_: Exception) {}
            try {
                context.getSharedPreferences("openvpn", Context.MODE_PRIVATE).edit()
                    .remove("alwaysOnVpn")
                    .remove("lastConnectedVpn")
                    .remove("lastConnectedProfile")
                    .commit()
            } catch (_: Exception) {}
        }
    }
}

