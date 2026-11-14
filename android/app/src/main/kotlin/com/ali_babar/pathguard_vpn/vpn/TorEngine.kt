package com.ali_babar.pathguard_vpn.vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import hev.htproxy.TProxyService
import org.json.JSONObject
import org.torproject.jni.TorService
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.Socket
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean

class TorEngine(
    private val service: VpnService,
    private val onProgress: (String) -> Unit,
    private val onConnected: (country: String, ip: String) -> Unit,
    private val onError: (String) -> Unit
) : VpnEngine {

    private val cancelled = AtomicBoolean(false)
    private val tunnelLock = Any()
    private var tunFd: ParcelFileDescriptor? = null
    private var tproxyStarted = false

    companion object {
        @Volatile private var iptController: IPtProxy.Controller? = null
        @Volatile
        private var torBootstrapped = false
        @Volatile
        private var torDaemonStarted = false
        @Volatile
        private var activeTorrcSignature: String = ""
        private var receiverRegistered = false

        // Bundled default Tor obfs4 bridges (official Tor Browser default bridges)
        private val BUNDLED_OBFS4_BRIDGES = listOf(
            "obfs4 192.95.36.142:443 CDF2E852BF539B82BD10E27E9115A31734E378C2 cert=qUVQ0srL1JI/vO6V6m/24anYXiJD3QP2HgzUKQtQ7GRqqUvs7P+tG43RtAqdhLOALP7DJQ iat-mode=1",
            "obfs4 37.218.245.14:38224 D9A82D2F9C2F65A18407B1D2B764F130847F8B5D cert=bjRaMrr1BRiAW8IE9U5z27fQaYgOhX1UCmOpg2pFpoMvo6ZgQMzLsaTzzQNTlm7hNcb+Sg iat-mode=0",
            "obfs4 85.31.186.98:443 011F2599C0E9B27EE74B353155E244813763C3E5 cert=ayq0XzCwhpdysn5o0EyDUbmSOx3X/oTEbzDMvczHOdBJKlvIdHHLJGkZARtT4dcBFArPPg iat-mode=0",
            "obfs4 85.31.186.26:443 91A6354697E6B02A386312F68D82CF86824D3606 cert=PBwr+S8JTVZo6MPdHnkTwXJPILWADLqfMGoVvhZClMq/Urndyd42BwX9YFJHZnBB3H0XCw iat-mode=0",
            "obfs4 193.11.166.194:27015 2D82C2E354D531A68469ADF7F878FA6060C6BACA cert=4TLQPJrTSaDffMK7Nbao6LC7G9OW/NHkUwIdjLSS3KYf0Nv4/nQiiI8dY2TcsQx01NniOg iat-mode=0",
            "obfs4 193.11.166.194:27020 86AC7B8D430DAC4117E9F42C9EAED18133863AAF cert=0LDeJH4JzMDtkJJrFphJCiPqKx7loozKN7VNfuukMGfHO0Z8OGdzHVkhVAOfo1mUdv9cMg iat-mode=0",
            "obfs4 193.11.166.194:27025 1AE2C08904527FEA90C4C4F8C1083EA59FBC6FAF cert=ItvYZzW5tn6v3G4UnQa6Qz04Npro6e81AP70YujmK/KXwDFPTs3aHXcHp4n8Vt6w/bv8cA iat-mode=0",
            "obfs4 209.148.46.65:443 74FAD13168806246602538555B5521A0383A1875 cert=ssH+9rP8dG2NLDN2XuFw63hIO/9MNNinLmxQDpVa+7kTOa9/m+tGWT1SmSYpQ9uTBGa6Hw iat-mode=0",
            "obfs4 146.57.248.225:22 10A6CD36A537FCE513A322361547444B393989F0 cert=K1gDtDAIcUfeLqbstggjIw2rtgIKqdIhUlHp82XRqNSq/mtAjp1BIC9vHKJ2FAEpGssTPw iat-mode=0",
            "obfs4 45.145.95.6:27015 C5B7CD6946FF10C5B3E89691A7D3F2C122D2117C cert=TD7PbUO0/0k6xYHMPW3vJxICfkMZNdkRrb63Zhl5j9dW3iRGiCx0A7mPhe5T2EDzQ35+Zw iat-mode=0",
            "obfs4 51.222.13.177:80 5EDAC3B810E12B01F6FD8050D2FD3E277B289A08 cert=2uplIpLQ0q9+0qMFrK5pkaYRDOe460LL9WHBvatgkuRr/SL31wBOEupaMMJ6koRE6Ld0ew iat-mode=0"
        )

        private val BUNDLED_SNOWFLAKE_BRIDGES = listOf(
            "snowflake 192.0.2.3:80 2B280B23E1107BB62ABFC40DDCC8824814F80A72 fingerprint=2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://1098762253.rsc.cdn77.org/ fronts=www.cdn77.com,www.phpmyadmin.net ice=stun:stun.l.google.com:19302,stun:stun.antisip.com:3478,stun:stun.bluesip.net:3478,stun:stun.dus.net:3478,stun:stun.epygi.com:3478,stun:stun.sonetel.com:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.voys.nl:3478 utls-imitate=hellorandomizedalpn",
            "snowflake 192.0.2.4:80 8838024498816A039FCBBAB14E6F40A0843051FA fingerprint=8838024498816A039FCBBAB14E6F40A0843051FA url=https://1098762253.rsc.cdn77.org/ fronts=www.cdn77.com,www.phpmyadmin.net ice=stun:stun.l.google.com:19302,stun:stun.antisip.com:3478,stun:stun.bluesip.net:3478,stun:stun.dus.net:3478,stun:stun.epygi.com:3478,stun:stun.sonetel.net:3478,stun:stun.uls.co.za:3478,stun:stun.voipgate.com:3478,stun:stun.voys.nl:3478 utls-imitate=hellorandomizedalpn"
        )

        private fun ensureTorReceiver(appContext: Context) {
            synchronized(this) {
                if (receiverRegistered) return
                val filter = IntentFilter(TorService.ACTION_STATUS)
                val receiver = object : BroadcastReceiver() {
                    override fun onReceive(c: Context?, i: Intent?) {
                        when (i?.getStringExtra(TorService.EXTRA_STATUS)) {
                            TorService.STATUS_ON, "ON" -> torBootstrapped = true
                            TorService.STATUS_OFF, "OFF" -> {
                                torBootstrapped = false
                                torDaemonStarted = false
                            }
                        }
                    }
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    appContext.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
                } else {
                    appContext.registerReceiver(receiver, filter)
                }
                receiverRegistered = true
            }
        }

        private fun isSocksPortListening(): Boolean {
            return try {
                Socket().use { s ->
                    s.connect(InetSocketAddress("127.0.0.1", 9050), 400)
                    true
                }
            } catch (_: Exception) {
                false
            }
        }
    }

    fun start(exitCountry: String?, disallowedApps: List<String>, stealthMode: Boolean = false) {
        cancelled.set(false)
        val appContext = service.applicationContext
        ensureTorReceiver(appContext)

        try {
            if (stealthMode) {
                val connectedTransport = startStealthTorFlow(appContext, exitCountry)
                if (cancelled.get() || Thread.currentThread().isInterrupted) {
                    stop()
                    return
                }
                if (connectedTransport == null) {
                    stop()
                    onError("Stealth Tor transports (obfs4 & Snowflake) timed out")
                    return
                }
                if (!verifyRequestedCountry(exitCountry, connectedTransport)) {
                    stop()
                    onError("No free server available right now")
                    return
                }
                establishTunAndHev(exitCountry, disallowedApps, connectedTransport)
            } else {
                onProgress("Bootstrapping Tor 5%…")
                val torrcContent = buildDirectTorrc(exitCountry)
                applyTorConfigAndEnsureRunning(appContext, torrcContent, "direct:${exitCountry ?: "any"}")

                val ready = waitForTorBootstrap(maxWaitMs = 75_000L, prefix = "Bootstrapping Tor")
                if (cancelled.get() || Thread.currentThread().isInterrupted) {
                    stop()
                    return
                }
                if (!ready) {
                    stop()
                    onError("Tor bootstrap timed out")
                    return
                }

                onProgress("Verifying Tor circuit (check.torproject.org) 80%…")
                val verifiedIp = verifyTorCheckWithFallback(maxWaitMs = 30_000L, labelPrefix = "Tor")
                if (cancelled.get() || Thread.currentThread().isInterrupted) {
                    stop()
                    return
                }
                if (verifiedIp == null) {
                    stop()
                    onError("Tor circuit verification failed — try Stealth or WARP")
                    return
                }
                if (!verifyRequestedCountry(exitCountry, verifiedIp)) {
                    stop()
                    onError("No free server available right now")
                    return
                }
                establishTunAndHev(exitCountry, disallowedApps, verifiedIp)
            }
        } catch (e: InterruptedException) {
            stop()
        } catch (e: Exception) {
            stop()
            if (!cancelled.get()) {
                onError(e.message ?: "Tor tunnel error")
            }
        }
    }

    /**
     * Runs Stealth transport sequence:
     * 1. obfs4 bridges (Moat fetched + bundled defaults, via IPtProxy / obfs4proxy)
     * 2. Snowflake pluggable transport fallback
     * Returns descriptive connected label (e.g. "185.220.101.7 (Stealth obfs4)") or null if both fail.
     */
    private fun startStealthTorFlow(appContext: Context, exitCountry: String?): String? {
        // 1. Try obfs4 first
        onProgress("Stealth: Fetching obfs4 bridges… 10%")
        val moatBridges = fetchMoatObfs4Bridges()
        if (cancelled.get() || Thread.currentThread().isInterrupted) return null

        val allObfs4 = (moatBridges + BUNDLED_OBFS4_BRIDGES).distinct()
        val obfs4PluginLine = resolveTransportPluginLine(appContext, "obfs4")

        onProgress("Stealth: Bootstrapping Tor (obfs4)… 20%")
        val obfs4Torrc = buildStealthTorrc(
            exitCountry = exitCountry,
            pluginLine = obfs4PluginLine,
            bridges = allObfs4
        )
        applyTorConfigAndEnsureRunning(appContext, obfs4Torrc, "stealth:obfs4:${exitCountry ?: "any"}")

        val obfs4PortReady = waitForTorBootstrap(maxWaitMs = 35_000L, prefix = "Stealth obfs4")
        if (cancelled.get() || Thread.currentThread().isInterrupted) return null

        if (obfs4PortReady) {
            onProgress("Stealth: Verifying obfs4 circuit… 80%")
            val verifiedObfs4 = verifyTorCheckWithFallback(maxWaitMs = 22_000L, labelPrefix = "Stealth obfs4")
            if (verifiedObfs4 != null) {
                stopIptProxySafely()
                return if (verifiedObfs4.contains("obfs4", ignoreCase = true)) {
                    verifiedObfs4
                } else {
                    "$verifiedObfs4 (Stealth obfs4)"
                }
            }
        }

        if (cancelled.get() || Thread.currentThread().isInterrupted) return null

        // 2. Fallback to Snowflake
        onProgress("Stealth: Falling back to Snowflake… 50%")
        val snowflakePluginLine = resolveTransportPluginLine(appContext, "snowflake")
        val snowflakeTorrc = buildStealthTorrc(
            exitCountry = exitCountry,
            pluginLine = snowflakePluginLine,
            bridges = BUNDLED_SNOWFLAKE_BRIDGES
        )
        applyTorConfigAndEnsureRunning(appContext, snowflakeTorrc, "stealth:snowflake:${exitCountry ?: "any"}")

        val snowReady = waitForTorBootstrap(maxWaitMs = 35_000L, prefix = "Stealth Snowflake")
        if (cancelled.get() || Thread.currentThread().isInterrupted) return null

        if (snowReady) {
            onProgress("Stealth: Verifying Snowflake circuit… 85%")
            val verifiedSnow = verifyTorCheckWithFallback(maxWaitMs = 22_000L, labelPrefix = "Stealth Snowflake")
            if (verifiedSnow != null) {
                return if (verifiedSnow.contains("Snowflake", ignoreCase = true)) {
                    verifiedSnow
                } else {
                    "$verifiedSnow (Stealth Snowflake)"
                }
            }
        }

        stopIptProxySafely()
        return null
    }

    /**
     * Resolves the ClientTransportPlugin line for obfs4 or snowflake:
     * - First attempts Guardian Project's IPtProxy via reflection (SOCKS5 proxy port)
     * - Otherwise locates bundled libobfs4proxy.so / libsnowflake.so in nativeLibraryDir
     */
    private fun resolveTransportPluginLine(appContext: Context, transport: String): String? {
        // 1. IPtProxy 5.x (Guardian Project) Controller API: local SOCKS5 listener per transport
        try {
            val ctrl = iptController ?: IPtProxy.IPtProxy.newController(
                File(appContext.filesDir, "pt_state").apply { mkdirs() }.absolutePath,
                false, false, "ERROR", null
            ).also { iptController = it }
            if (transport == "snowflake") {
                ctrl.snowflakeIceServers = "stun:stun.l.google.com:19302,stun:stun.antisip.com:3478"
                ctrl.snowflakeBrokerUrl = "https://1098762253.rsc.cdn77.org/"
                ctrl.snowflakeFrontDomains = "www.cdn77.com,www.phpmyadmin.net"
            }
            val name = if (transport == "obfs4") IPtProxy.IPtProxy.Obfs4 else IPtProxy.IPtProxy.Snowflake
            ctrl.start(name, "")
            val port = ctrl.port(name)
            if (port > 0) {
                return "ClientTransportPlugin $transport socks5 127.0.0.1:$port"
            }
        } catch (_: Throwable) {}

        // 2. Check nativeLibraryDir for packaged pluggable transport binaries
        val nativeDir = appContext.applicationInfo.nativeLibraryDir
        val candidates = if (transport == "obfs4") {
            listOf("libobfs4proxy.so", "obfs4proxy", "liblyrebird.so")
        } else {
            listOf("libsnowflake.so", "snowflake-client", "libobfs4proxy.so")
        }
        for (name in candidates) {
            val bin = File(nativeDir, name)
            if (bin.exists() && bin.canExecute()) {
                return "ClientTransportPlugin $transport exec ${bin.absolutePath}"
            }
        }
        return null
    }

    private fun stopIptProxySafely() {
        try {
            iptController?.stop(IPtProxy.IPtProxy.Obfs4)
            iptController?.stop(IPtProxy.IPtProxy.Snowflake)
        } catch (_: Throwable) {}
    }

    /**
     * Attempts to fetch fresh obfs4 bridge lines from Tor Project's Moat API (bridges.torproject.org).
     * Bounded to 5 seconds so offline/censored networks fall back immediately to bundled bridges.
     */
    private fun fetchMoatObfs4Bridges(): List<String> {
        return try {
            val url = URL("https://bridges.torproject.org/moat/circumvention/builtin")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 4_500
                readTimeout = 4_500
                setRequestProperty("Content-Type", "application/vnd.api+json")
                doOutput = true
            }
            conn.outputStream.use {
                it.write("{\"data\":[{\"type\":\"client-transports\",\"supported\":[\"obfs4\"]}]}".toByteArray())
            }
            if (conn.responseCode == 200) {
                val body = conn.inputStream.bufferedReader().use { it.readText() }
                val json = JSONObject(body)
                val arr = json.optJSONArray("obfs4") ?: return emptyList()
                val result = mutableListOf<String>()
                for (i in 0 until arr.length()) {
                    val line = arr.optString(i)?.trim()
                    if (!line.isNullOrEmpty()) result.add(line)
                }
                result
            } else {
                emptyList()
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun buildDirectTorrc(exitCountry: String?): String {
        val cleanCountry = exitCountry?.takeIf {
            it.length == 2 && !it.equals("auto", ignoreCase = true) && !it.equals("any", ignoreCase = true) && !it.equals("un", ignoreCase = true)
        }
        // When a user selects a specific country in Tor/Stealth, apply ExitNodes {cc} + StrictNodes 1
        val exitBlock = if (cleanCountry != null) {
            "ExitNodes {${cleanCountry.lowercase()}}\nStrictNodes 1\n"
        } else {
            ""
        }
        return """
            SocksPort 9050
            DNSPort 5400
            ControlPort 9051
            AutomapHostsOnResolve 1
            VirtualAddrNetworkIPv4 10.255.0.0/16
            ClientRejectInternalAddresses 0
            $exitBlock
        """.trimIndent()
    }

    private fun buildStealthTorrc(
        exitCountry: String?,
        pluginLine: String?,
        bridges: List<String>
    ): String {
        val cleanCountry = exitCountry?.takeIf {
            it.length == 2 && !it.equals("auto", ignoreCase = true) && !it.equals("any", ignoreCase = true) && !it.equals("un", ignoreCase = true)
        }
        val exitBlock = if (cleanCountry != null) {
            "ExitNodes {${cleanCountry.lowercase()}}\nStrictNodes 1\n"
        } else {
            ""
        }
        val sb = StringBuilder()
        sb.appendLine("SocksPort 9050")
        sb.appendLine("DNSPort 5400")
        sb.appendLine("ControlPort 9051")
        sb.appendLine("AutomapHostsOnResolve 1")
        sb.appendLine("VirtualAddrNetworkIPv4 10.255.0.0/16")
        sb.appendLine("ClientRejectInternalAddresses 0")
        if (exitBlock.isNotEmpty()) sb.append(exitBlock)

        // Only enable UseBridges 1 if a valid ClientTransportPlugin is available,
        // otherwise Tor refuses to start or rejects bridge lines.
        if (!pluginLine.isNullOrBlank() && bridges.isNotEmpty()) {
            sb.appendLine("UseBridges 1")
            sb.appendLine(pluginLine)
            for (b in bridges) {
                val clean = if (b.startsWith("Bridge ", ignoreCase = true)) b else "Bridge $b"
                sb.appendLine(clean)
            }
        }
        return sb.toString().trimIndent()
    }

    private fun applyTorConfigAndEnsureRunning(appContext: Context, torrcContent: String, signature: String) {
        val torrcFile = TorService.getTorrc(appContext)
        val changed = activeTorrcSignature != signature
        torrcFile.writeText(torrcContent)
        activeTorrcSignature = signature

        if (!torDaemonStarted && !isSocksPortListening()) {
            torDaemonStarted = true
            appContext.startService(Intent(appContext, TorService::class.java))
        } else if (changed && isSocksPortListening()) {
            // Reload Tor configuration live via ControlPort 9051 or SIGHUP without killing :tor process
            reloadTorConfigLive(exitCountryFromSig(signature), torrcContent)
        }
    }

    private fun exitCountryFromSig(sig: String): String? {
        val last = sig.substringAfterLast(":", "")
        return last.takeIf { it.length == 2 && it != "an" }
    }

    private fun reloadTorConfigLive(exitCountry: String?, torrcContent: String) {
        try {
            Socket().use { s ->
                s.soTimeout = 1500
                s.connect(InetSocketAddress("127.0.0.1", 9051), 1000)
                val out = s.getOutputStream()
                val inp = s.getInputStream().bufferedReader()
                out.write("AUTHENTICATE\r\n".toByteArray())
                out.flush()
                inp.readLine()

                val cleanCountry = exitCountry?.takeIf {
                    it.length == 2 && !it.equals("auto", ignoreCase = true) && !it.equals("any", ignoreCase = true)
                }
                if (cleanCountry != null) {
                    out.write("SETCONF ExitNodes={${cleanCountry.lowercase()}} StrictNodes=1\r\n".toByteArray())
                } else {
                    out.write("RESETCONF ExitNodes StrictNodes\r\n".toByteArray())
                }
                out.write("SIGNAL RELOAD\r\nSIGNAL NEWNYM\r\n".toByteArray())
                out.flush()
            }
        } catch (_: Exception) {}
    }

    private fun waitForTorBootstrap(maxWaitMs: Long, prefix: String): Boolean {
        val startMs = System.currentTimeMillis()
        val deadline = startMs + maxWaitMs
        // Do not treat leftover SOCKS as immediate success after an ExitNodes change
        var ready = torBootstrapped
        var lastPct = 10

        while (!ready && System.currentTimeMillis() < deadline) {
            if (cancelled.get() || Thread.currentThread().isInterrupted) return false
            val elapsed = System.currentTimeMillis() - startMs
            val pct = (15 + ((elapsed * 55) / maxWaitMs).toInt()).coerceIn(15, 72)
            if (pct != lastPct) {
                lastPct = pct
                onProgress("$prefix$pct%…")
            }
            try {
                Thread.sleep(300)
            } catch (_: InterruptedException) {
                return false
            }
            ready = torBootstrapped
        }
        if (ready) torBootstrapped = true
        return ready
    }

    private fun establishTunAndHev(
        exitCountry: String?,
        disallowedApps: List<String>,
        verifiedIpLabel: String
    ) {
        onProgress("Securing Tor tunnel 95%…")

        synchronized(tunnelLock) {
            if (cancelled.get() || Thread.currentThread().isInterrupted) {
                tearDownTunnelLocked()
                return
            }

            val builder = service.Builder()
                .setSession("PathGuard Tor")
                .addAddress("10.0.0.2", 32)
                .addRoute("0.0.0.0", 0)
                .addDnsServer("10.0.0.2")
                .setMtu(1500)

            // Always exclude our own package so Tor (:tor shares UID) never loops back into tun0
            try {
                builder.addDisallowedApplication(service.packageName)
            } catch (_: Exception) {}

            for (pkg in disallowedApps) {
                try {
                    builder.addDisallowedApplication(pkg)
                } catch (_: Exception) {}
            }

            val established = builder.establish()
            if (established == null) {
                if (!cancelled.get()) onError("Failed to establish VPN TUN interface")
                return
            }

            if (cancelled.get() || Thread.currentThread().isInterrupted) {
                try {
                    established.close()
                } catch (_: Exception) {}
                return
            }

            tunFd = established

            val conf = File(service.cacheDir, "tproxy.yaml")
            conf.writeText(
                """
                tunnel:
                  name: tun0
                  mtu: 1500
                  ipv4: 10.0.0.2
                socks5:
                  port: 9050
                  address: 127.0.0.1
                  udp: 'tcp'
                mapdns:
                  address: 10.0.0.2
                  port: 53
                  network: 10.255.0.0
                  netmask: 255.255.0.0
                  cache-size: 10000
                """.trimIndent()
            )

            if (TProxyService.TProxyIsRunning()) {
                try {
                    TProxyService.TProxyStopService()
                } catch (_: Exception) {}
            }

            val started = TProxyService.TProxyStartService(conf.absolutePath, established.fd)
            tproxyStarted = started
            if (!started || !TProxyService.TProxyIsRunning()) {
                tearDownTunnelLocked()
                if (!cancelled.get()) onError("Failed to start hev-socks5-tunnel")
                return
            }
        }

        if (cancelled.get() || Thread.currentThread().isInterrupted) {
            stop()
            return
        }

        onConnected(exitCountry?.takeIf { it.isNotBlank() } ?: "any", verifiedIpLabel)
    }

    /**
     * Requirement: Confirm Tor really works via https://check.torproject.org/api/ip expecting IsTor=true,
     * with SOCKS5 remote-DNS fallback checks over 3 retries (30s total budget).
     */
    private fun verifyTorCheckWithFallback(maxWaitMs: Long, labelPrefix: String): String? {
        val deadline = System.currentTimeMillis() + maxWaitMs
        val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", 9050))

        for (round in 1..3) {
            if (cancelled.get() || Thread.currentThread().isInterrupted) return null
            if (System.currentTimeMillis() >= deadline) break

            val pct = (75 + (round * 6)).coerceAtMost(93)
            onProgress("Verifying $labelPrefix ($round/3)$pct%…")

            // 1. Primary official Tor check: https://check.torproject.org/api/ip expecting IsTor=true
            try {
                val conn = (URL("https://check.torproject.org/api/ip").openConnection(proxy) as HttpURLConnection).apply {
                    connectTimeout = 7_500
                    readTimeout = 7_500
                    setRequestProperty("User-Agent", "curl/8.0")
                }
                if (conn.responseCode == 200) {
                    val body = conn.inputStream.bufferedReader().use { it.readText() }
                    if (body.contains("\"IsTor\":true", ignoreCase = true)) {
                        val ip = Regex("\"IP\":\"([^\"]+)\"").find(body)?.groupValues?.get(1) ?: "Tor Verified"
                        return ip
                    }
                }
            } catch (_: Exception) {}

            if (cancelled.get() || Thread.currentThread().isInterrupted) return null

            // 2. Fallback: raw SOCKS5 with ATYP=0x03 (remote DNS inside Tor) to check.torproject.org / ipify / icanhazip
            val fallbackTargets = listOf(
                Pair("check.torproject.org", "/api/ip"),
                Pair("api.ipify.org", "/?format=json"),
                Pair("icanhazip.com", "/")
            )
            for ((host, path) in fallbackTargets) {
                if (cancelled.get() || Thread.currentThread().isInterrupted) return null
                if (System.currentTimeMillis() >= deadline) break

                val body = socks5HttpGetBody(host, 80, path, timeoutMs = 6_500)
                if (body != null) {
                    if (body.contains("\"IsTor\":true", ignoreCase = true)) {
                        return Regex("\"IP\":\"([^\"]+)\"").find(body)?.groupValues?.get(1) ?: "Tor Verified"
                    }
                    val ipMatch = Regex("(\\d{1,3}(?:\\.\\d{1,3}){3})").find(body)
                    if (ipMatch != null) {
                        return ipMatch.groupValues[1]
                    }
                }
            }

            if (System.currentTimeMillis() < deadline) {
                try {
                    Thread.sleep(1200)
                } catch (_: InterruptedException) {
                    return null
                }
            }
        }
        return null
    }

    /**
     * Performs an RFC 1928 SOCKS5 CONNECT with ATYP=0x03 (DOMAINNAME) so Tor resolves DNS remotely
     * and returns the response payload on HTTP 200/301/302.
     */
    private fun socks5HttpGetBody(host: String, port: Int, path: String, timeoutMs: Int): String? {
        return try {
            Socket().use { sock ->
                sock.soTimeout = timeoutMs
                sock.connect(InetSocketAddress("127.0.0.1", 9050), 2_500)
                val out: OutputStream = sock.getOutputStream()
                val inp: InputStream = sock.getInputStream()

                out.write(byteArrayOf(0x05, 0x01, 0x00))
                out.flush()

                val greet = ByteArray(2)
                if (inp.read(greet) != 2 || greet[0] != 0x05.toByte() || greet[1] != 0x00.toByte()) {
                    return null
                }

                val hostBytes = host.toByteArray(Charsets.US_ASCII)
                val req = ByteArray(4 + 1 + hostBytes.size + 2)
                req[0] = 0x05
                req[1] = 0x01
                req[2] = 0x00
                req[3] = 0x03 // DOMAINNAME
                req[4] = hostBytes.size.toByte()
                System.arraycopy(hostBytes, 0, req, 5, hostBytes.size)
                req[5 + hostBytes.size] = ((port shr 8) and 0xFF).toByte()
                req[6 + hostBytes.size] = (port and 0xFF).toByte()
                out.write(req)
                out.flush()

                val hdr = ByteArray(4)
                if (inp.read(hdr) != 4 || hdr[0] != 0x05.toByte() || hdr[1] != 0x00.toByte()) {
                    return null
                }
                val toSkip = when (hdr[3].toInt() and 0xFF) {
                    0x01 -> 4 + 2
                    0x03 -> (inp.read() and 0xFF) + 2
                    0x04 -> 16 + 2
                    else -> return null
                }
                val skipBuf = ByteArray(toSkip)
                var readCount = 0
                while (readCount < toSkip) {
                    val r = inp.read(skipBuf, readCount, toSkip - readCount)
                    if (r <= 0) break
                    readCount += r
                }

                val httpReq = "GET $path HTTP/1.1\r\nHost:$host\r\nUser-Agent: curl/8.0\r\nConnection: close\r\n\r\n"
                out.write(httpReq.toByteArray(Charsets.US_ASCII))
                out.flush()

                val responseText = inp.bufferedReader(Charsets.UTF_8).readText()
                if (responseText.startsWith("HTTP/1.1 200") || responseText.startsWith("HTTP/1.0 200")) {
                    return responseText.substringAfter("\r\n\r\n", "").trim()
                }
                null
            }
        } catch (_: Exception) {
            null
        }
    }


    private fun verifyRequestedCountry(exitCountry: String?, verifiedLabel: String): Boolean {
        val cc = exitCountry?.takeIf { it.isNotBlank() && !it.equals("auto", ignoreCase = true) } ?: return true
        if (!cc.equals("SA", ignoreCase = true) && !cc.equals("PK", ignoreCase = true)) return true
        val ip = Regex("""(\d{1,3}(?:\.\d{1,3}){3})""").find(verifiedLabel)?.groupValues?.get(1)
            ?: verifiedLabel
        return checkExitCountry(ip, cc)
    }

    private fun checkExitCountry(ip: String, expected: String): Boolean {
        return try {
            val conn = URL("https://ipwho.is/$ip").openConnection() as HttpURLConnection
            conn.connectTimeout = 5000
            conn.readTimeout = 5000
            if (conn.responseCode == 200) {
                val body = conn.inputStream.bufferedReader().use { it.readText() }
                body.contains("\"country_code\":\"${expected.uppercase()}\"", ignoreCase = true)
            } else false
        } catch (_: Exception) { false }
    }

    private fun tearDownTunnelLocked() {
        if (tproxyStarted || TProxyService.TProxyIsRunning()) {
            try {
                TProxyService.TProxyStopService()
            } catch (_: Exception) {}
            tproxyStarted = false
        }
        try {
            tunFd?.close()
        } catch (_: Exception) {}
        tunFd = null
    }

    override fun stop() {
        cancelled.set(true)
        synchronized(tunnelLock) {
            tearDownTunnelLocked()
        }
        try {
            service.stopService(Intent(service, org.torproject.jni.TorService::class.java))
        } catch (_: Exception) {}
        torDaemonStarted = false
        torBootstrapped = false
    }
}

