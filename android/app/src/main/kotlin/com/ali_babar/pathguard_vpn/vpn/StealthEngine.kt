package com.ali_babar.pathguard_vpn.vpn

import android.net.VpnService
import java.util.concurrent.atomic.AtomicBoolean

/**
 * StealthEngine implements automatic pluggable-transport & port-443 fallback:
 * 1. Tor with obfs4 bridges (bundled + Moat bridges.torproject.org fetch + IPtProxy/obfs4proxy)
 * 2. Tor with Snowflake pluggable transport fallback
 * 3. OpenVPN Stealth (TCP 443 forced) using free VPN Gate / public TCP-443 servers
 * Reports which Stealth transport connected in the IP/status label.
 */
class StealthEngine(
    private val service: VpnService,
    private val onProgress: (String) -> Unit,
    private val onConnected: (country: String, ip: String) -> Unit,
    private val onError: (String) -> Unit
) : VpnEngine {

    private val cancelled = AtomicBoolean(false)
    @Volatile
    private var currentSubEngine: VpnEngine? = null

    fun start(
        exitCountry: String?,
        fallbackOpenVpnConfigBase64: String?,
        fallbackServerIp: String?,
        disallowedApps: List<String>
    ) {
        cancelled.set(false)
        val cleanCountry = exitCountry?.takeIf { it.isNotBlank() } ?: "any"

        // Stage 1 & 2: Tor Pluggable Transports (obfs4 -> Snowflake)
        var torSuccess = false
        var torConnectedLabel = ""

        val torStealth = TorEngine(
            service = service,
            onProgress = { stage ->
                if (!cancelled.get()) onProgress(stage)
            },
            onConnected = { _, ipLabel ->
                torSuccess = true
                torConnectedLabel = ipLabel
            },
            onError = { _ ->
                torSuccess = false
            }
        )
        currentSubEngine = torStealth

        if (!cancelled.get() && !Thread.currentThread().isInterrupted) {
            torStealth.start(
                exitCountry = exitCountry,
                disallowedApps = disallowedApps,
                stealthMode = true
            )
        }

        if (cancelled.get() || Thread.currentThread().isInterrupted) {
            torStealth.stop()
            return
        }

        if (torSuccess) {
            onConnected(cleanCountry, torConnectedLabel)
            return
        }

        // Clean up Tor sub-engine before trying OpenVPN TCP 443 Stealth
        torStealth.stop()
        currentSubEngine = null

        // Stage 3: OpenVPN Stealth (TCP 443)
        if (!fallbackOpenVpnConfigBase64.isNullOrBlank() && !cancelled.get()) {
            val targetIp = fallbackServerIp?.takeIf { it.isNotBlank() } ?: "TCP-443"
            onProgress("Stealth fallback: OpenVPN TCP 443 ($targetIp)…")

            var ovpnSuccess = false
            var ovpnError = "Stealth connection failed"

            val ovpnStealth = OpenVpnEngine(
                context = service,
                onProgress = { stage ->
                    if (!cancelled.get()) onProgress("Stealth TCP 443: $stage")
                },
                onConnected = { cCode, ip ->
                    ovpnSuccess = true
                    onConnected(cCode, "$ip (Stealth TCP-443)")
                },
                onError = { err ->
                    ovpnError = err
                }
            )
            currentSubEngine = ovpnStealth

            ovpnStealth.start(
                configBase64 = fallbackOpenVpnConfigBase64,
                preferUdp = false,
                disallowedApps = disallowedApps,
                countryCode = exitCountry,
                serverIp = fallbackServerIp,
                forceTcp443 = true
            )

            if (cancelled.get() || Thread.currentThread().isInterrupted) {
                ovpnStealth.stop()
                return
            }

            if (!ovpnSuccess) {
                ovpnStealth.stop()
                onError("Stealth failed (obfs4, Snowflake & TCP-443 unreachable): $ovpnError")
            }
        } else {
            if (!cancelled.get()) {
                onError("Stealth obfs4 & Snowflake failed, and no TCP-443 server available")
            }
        }
    }

    override fun stop() {
        cancelled.set(true)
        try {
            currentSubEngine?.stop()
        } catch (_: Exception) {}
        currentSubEngine = null
    }
}

