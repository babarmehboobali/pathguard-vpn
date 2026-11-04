package com.ali_babar.pathguard_vpn.vpn

import android.content.Context
import android.content.SharedPreferences
import android.net.VpnService
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config
import com.wireguard.config.Interface
import com.wireguard.crypto.KeyPair
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.concurrent.atomic.AtomicBoolean

class WarpEngine(
    private val service: VpnService,
    private val onProgress: (String) -> Unit,
    private val onConnected: (country: String, ip: String) -> Unit,
    private val onError: (String) -> Unit
) : VpnEngine {

    private val cancelled = AtomicBoolean(false)
    private val prefs: SharedPreferences =
        service.applicationContext.getSharedPreferences("warp", Context.MODE_PRIVATE)

    companion object {
        private val backendLock = Any()
        private var sharedBackend: GoBackend? = null

        private val tunnel = object : Tunnel {
            override fun getName() = "PathGuardWARP"
            override fun onStateChange(state: Tunnel.State) {}
        }
    }

    fun start(disallowedApps: List<String>, countryCode: String?) {
        cancelled.set(false)
        if (VpnService.prepare(service) != null) {
            onError("VPN permission required")
            return
        }

        try {
            onProgress("Verifying WARP credentials…")
            val privateKey = prefs.getString("private_key", null) ?: registerWarpAccount()
            if (cancelled.get() || Thread.currentThread().isInterrupted) return

            val peerPublic = prefs.getString("peer_public", null)
            if (privateKey.isNullOrBlank() || peerPublic.isNullOrBlank()) {
                if (!cancelled.get()) onError("Cloudflare WARP registration failed")
                return
            }

            val address = prefs.getString("address", "172.16.0.2/32") ?: "172.16.0.2/32"
            val configStr = """
                [Interface]
                PrivateKey = $privateKey
                Address = $address
                DNS = 1.1.1.1
                MTU = 1280
                [Peer]
                PublicKey = $peerPublic
                AllowedIPs = 0.0.0.0/0
                Endpoint = engage.cloudflareclient.com:2408
            """.trimIndent()

            val parsedPeers = Config.parse(ByteArrayInputStream(configStr.toByteArray())).peers
            val exclusions = LinkedHashSet<String>().apply {
                add(service.packageName)
                addAll(disallowedApps)
            }

            val iface = Interface.Builder()
                .parsePrivateKey(privateKey)
                .parseAddresses(address)
                .parseDnsServers("1.1.1.1")
                .setMtu(1280)
                .excludeApplications(exclusions)
                .build()

            val wgConfig = Config.Builder()
                .setInterface(iface)
                .addPeers(parsedPeers)
                .build()

            val startEpochMillis = System.currentTimeMillis()
            onProgress("Establishing WireGuard tunnel…")

            synchronized(backendLock) {
                if (cancelled.get() || Thread.currentThread().isInterrupted) return
                val backend = sharedBackend ?: GoBackend(service.applicationContext).also {
                    sharedBackend = it
                }
                try {
                    backend.setState(tunnel, Tunnel.State.DOWN, null)
                } catch (_: Exception) {}
                backend.setState(tunnel, Tunnel.State.UP, wgConfig)
            }

            // Require an actual WireGuard handshake (up to 10 seconds) before reporting connected
            var verified = false
            for (i in 0 until 20) {
                if (cancelled.get() || Thread.currentThread().isInterrupted) {
                    tearDownSynchronously()
                    return
                }
                val pct = 30 + (i * 3)
                onProgress("Handshaking WARP $pct%…")
                try {
                    Thread.sleep(500)
                } catch (_: InterruptedException) {
                    tearDownSynchronously()
                    return
                }
                if (cancelled.get() || Thread.currentThread().isInterrupted) {
                    tearDownSynchronously()
                    return
                }
                val stats = synchronized(backendLock) {
                    sharedBackend?.getStatistics(tunnel)
                }
                val handshake = stats?.peers()?.firstOrNull()?.let { k ->
                    stats.peer(k)?.latestHandshakeEpochMillis()
                } ?: 0L
                val rxBytes = stats?.totalRx() ?: 0L
                if (handshake >= startEpochMillis - 2000L || (handshake > 0L && rxBytes > 0L)) {
                    verified = true
                    break
                }
            }

            if (cancelled.get() || Thread.currentThread().isInterrupted) {
                tearDownSynchronously()
                return
            }

            if (verified) {
                onConnected(countryCode ?: "auto", "172.16.0.2 (WARP)")
            } else {
                tearDownSynchronously()
                if (!cancelled.get()) onError("WARP handshake failed")
            }
        } catch (e: InterruptedException) {
            tearDownSynchronously()
        } catch (e: Exception) {
            tearDownSynchronously()
            if (!cancelled.get()) {
                onError(e.message ?: "WARP failed")
            }
        }
    }

    private fun registerWarpAccount(): String? {
        if (cancelled.get() || Thread.currentThread().isInterrupted) return null
        onProgress("Registering WARP device…")
        val keyPair = KeyPair()
        val publicKey = keyPair.publicKey.toBase64()
        val privateKey = keyPair.privateKey.toBase64()
        val body = JSONObject().apply {
            put("key", publicKey)
            put("install_id", "")
            put("fcm_token", "")
            put("tos", Instant.now().toString())
            put("type", "Android")
            put("locale", "en_US")
        }
        val conn = (URL("https://api.cloudflareclient.com/v0a2158/reg").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 10_000
            readTimeout = 10_000
            setRequestProperty("CF-Client-Version", "a-6.30-2158")
            setRequestProperty("Content-Type", "application/json")
            doOutput = true
        }
        conn.outputStream.use { it.write(body.toString().toByteArray()) }
        if (conn.responseCode !in 200..299) return null
        val response = conn.inputStream.bufferedReader().use { it.readText() }
        val json = JSONObject(response)
        val peerPublic = json.getJSONObject("config")
            .getJSONArray("peers")
            .getJSONObject(0)
            .getString("public_key")
        val v4 = json.getJSONObject("config")
            .getJSONObject("interface")
            .getJSONObject("addresses")
            .getString("v4")
        val address = "$v4/32"

        prefs.edit()
            .putString("private_key", privateKey)
            .putString("peer_public", peerPublic)
            .putString("address", address)
            .commit()
        return privateKey
    }

    private fun tearDownSynchronously() {
        synchronized(backendLock) {
            try {
                sharedBackend?.setState(tunnel, Tunnel.State.DOWN, null)
            } catch (_: Exception) {}
        }
    }

    override fun stop() {
        cancelled.set(true)
        tearDownSynchronously()
    }
}

