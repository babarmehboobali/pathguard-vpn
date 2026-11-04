package com.ali_babar.pathguard_vpn.vpn

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.atomic.AtomicInteger

interface VpnEngine {
    fun stop()
}

class PathGuardVpnService : VpnService() {

    companion object {
        const val ACTION_CONNECT = "com.ali_babar.pathguard_vpn.CONNECT"
        const val ACTION_DISCONNECT = "com.ali_babar.pathguard_vpn.DISCONNECT"
        const val ACTION_UPDATE_SPLIT = "com.ali_babar.pathguard_vpn.UPDATE_SPLIT"

        private val mainHandler = Handler(Looper.getMainLooper())
        private val worker = Executors.newCachedThreadPool { r ->
            Thread(r, "PathGuardVpnWorker").apply { isDaemon = true }
        }
        private val engineChangeLock = Any()

        @Volatile
        private var eventSink: EventChannel.EventSink? = null
        @Volatile
        private var instance: PathGuardVpnService? = null
        @Volatile
        private var currentTask: Future<*>? = null

        @Volatile
        private var lastEvent: Map<String, Any?> = mapOf(
            "state" to "idle",
            "mode" to "free"
        )

        private val sessionCounter = AtomicInteger(0)
        @Volatile
        private var activeEngineRef: VpnEngine? = null
        private var crashHandlerInstalled = false

        fun setEventSink(sink: EventChannel.EventSink?) {
            eventSink = sink
            if (sink != null) {
                mainHandler.post {
                    eventSink?.success(lastEvent)
                }
            }
        }

        fun emitState(
            state: String,
            mode: String,
            countryCode: String? = null,
            ip: String? = null,
            errorMessage: String? = null
        ) {
            val payload = mutableMapOf<String, Any?>(
                "state" to state,
                "mode" to mode,
                "countryCode" to countryCode,
                "ip" to ip,
                "errorMessage" to errorMessage
            )
            if (state != "connected") {
                payload["bytesIn"] = 0L
                payload["bytesOut"] = 0L
            }

            lastEvent = payload
            mainHandler.post {
                eventSink?.success(payload)
            }
        }

        fun emitProgress(
            session: Int,
            mode: String,
            stageText: String,
            countryCode: String? = null
        ) {
            if (session != sessionCounter.get()) return
            val current = lastEvent
            if (current["state"] == "connected") return
            val payload = mutableMapOf<String, Any?>(
                "state" to "connecting",
                "mode" to mode,
                "countryCode" to countryCode,
                "ip" to null,
                "errorMessage" to stageText,
                "bytesIn" to 0L,
                "bytesOut" to 0L
            )
            lastEvent = payload
            mainHandler.post {
                if (session == sessionCounter.get() && lastEvent["state"] == "connecting") {
                    eventSink?.success(payload)
                }
            }
        }

        fun emitTraffic(bytesIn: Long, bytesOut: Long) {
            val current = lastEvent
            if (current["state"] != "connected") return
            val payload = mapOf<String, Any?>(
                "state" to "connected",
                "mode" to current["mode"],
                "countryCode" to current["countryCode"],
                "ip" to current["ip"],
                "errorMessage" to null,
                "bytesIn" to bytesIn,
                "bytesOut" to bytesOut
            )
            mainHandler.post {
                if (lastEvent["state"] == "connected") {
                    eventSink?.success(payload)
                }
            }
        }

        fun start(
            context: Context,
            mode: String,
            config: String?,
            country: String?,
            serverIp: String?,
            disallowed: List<String>?,
            preferUdp: Boolean
        ) {
            val appCtx = context.applicationContext
            val intent = Intent(appCtx, PathGuardVpnService::class.java).apply {
                action = ACTION_CONNECT
                putExtra("mode", mode)
                putExtra("config", config)
                putExtra("country", country)
                putExtra("serverIp", serverIp)
                putStringArrayListExtra("disallowed", ArrayList<String>(disallowed ?: emptyList<String>()))
                putExtra("preferUdp", preferUdp)
            }
            appCtx.startForegroundService(intent)
        }

        fun stop(context: Context) {
            sessionCounter.incrementAndGet()
            currentTask?.cancel(true)
            val eng = activeEngineRef
            if (eng != null) {
                worker.execute {
                    try {
                        eng.stop()
                    } catch (_: Exception) {}
                }
            }

            val svc = instance
            if (svc != null) {
                svc.enqueueDisconnect()
            } else {
                val mode = (lastEvent["mode"] as? String) ?: "free"
                emitState(state = "idle", mode = mode)
            }
        }

        fun updateSplit(disallowed: List<String>) {
            instance?.enqueueUpdateSplit(disallowed)
        }
    }

    @Volatile
    private var activeEngine: VpnEngine? = null
        set(value) {
            field = value
            activeEngineRef = value
        }

    private var statsMonitor: TrafficStatsMonitor? = null
    private var reconnectManager: ReconnectManager? = null

    private var currentMode: String = "free"
    private var lastConfig: String? = null
    private var lastCountry: String? = null
    private var lastServerIp: String? = null
    private var lastDisallowed: List<String> = emptyList<String>()
    private var lastPreferUdp: Boolean = true

    override fun onCreate() {
        super.onCreate()
        instance = this
        reconnectManager = ReconnectManager(this)
        installCrashLoggerOnce()
    }

    private fun installCrashLoggerOnce() {
        if (crashHandlerInstalled) return
        crashHandlerInstalled = true
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, e ->
            try {
                val file = File(filesDir, "native_crash.txt")
                val sw = StringWriter()
                e.printStackTrace(PrintWriter(sw))
                file.appendText("${System.currentTimeMillis()}\n$sw\n\n")
            } catch (_: Exception) {}
            previous?.uncaughtException(thread, e)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        NotificationHelper.startForeground(this, "Initializing VPN…")

        val safeIntent = intent
        if (safeIntent == null) {
            enqueueDisconnect()
            return START_NOT_STICKY
        }

        when (safeIntent.action ?: ACTION_DISCONNECT) {
            ACTION_DISCONNECT -> {
                enqueueDisconnect()
            }
            ACTION_CONNECT -> {
                val mode = safeIntent.getStringExtra("mode") ?: "free"
                val config = safeIntent.getStringExtra("config")
                val country = safeIntent.getStringExtra("country")
                val serverIp = safeIntent.getStringExtra("serverIp")
                val disallowed: List<String> = safeIntent.getStringArrayListExtra("disallowed") ?: arrayListOf<String>()
                val preferUdp = safeIntent.getBooleanExtra("preferUdp", true)

                enqueueConnect(
                    mode = mode,
                    config = config,
                    country = country,
                    serverIp = serverIp,
                    disallowed = disallowed,
                    preferUdp = preferUdp
                )
            }
            ACTION_UPDATE_SPLIT -> {
                val disallowed: List<String> = safeIntent.getStringArrayListExtra("disallowed") ?: arrayListOf<String>()
                enqueueUpdateSplit(disallowed)
            }
            else -> {
                enqueueDisconnect()
            }
        }
        return START_NOT_STICKY
    }

    private fun enqueueConnect(
        mode: String,
        config: String?,
        country: String?,
        serverIp: String?,
        disallowed: List<String>,
        preferUdp: Boolean
    ) {
        val mySession = sessionCounter.incrementAndGet()
        currentTask?.cancel(true)
        val previousEngine = activeEngine
        activeEngine = null

        currentTask = worker.submit {
            synchronized(engineChangeLock) {
                try {
                    previousEngine?.stop()
                } catch (_: Exception) {}
                stopActiveEngineInternal()
            }

            if (mySession != sessionCounter.get() || Thread.currentThread().isInterrupted) return@submit

            currentMode = mode
            lastConfig = config
            lastCountry = country
            lastServerIp = serverIp
            lastDisallowed = disallowed
            lastPreferUdp = preferUdp

            emitProgress(
                session = mySession,
                mode = mode,
                stageText = when (mode) {
                    "tor" -> "Bootstrapping Tor 5%…"
                    "stealth" -> "Starting Stealth (obfs4)… 5%"
                    "warp" -> "Connecting to WARP…"
                    else -> "Preparing OpenVPN tunnel…"
                },
                countryCode = country
            )

            val engine: VpnEngine = when (mode) {
                "free" -> OpenVpnEngine(
                    context = this,
                    onProgress = { stage ->
                        emitProgress(session = mySession, mode = "free", stageText = stage, countryCode = country)
                    },
                    onConnected = { cCode, ip ->
                        if (mySession == sessionCounter.get()) {
                            onEngineTunnelUp(session = mySession, mode = "free", country = cCode, ip = ip)
                        } else {
                            activeEngine?.stop()
                        }
                    },
                    onError = { msg ->
                        if (mySession == sessionCounter.get()) {
                            onEngineFailed(session = mySession, mode = "free", message = msg)
                        }
                    }
                ).also {
                    activeEngine = it
                    it.start(
                        configBase64 = config ?: "",
                        preferUdp = preferUdp,
                        disallowedApps = disallowed,
                        countryCode = country,
                        serverIp = serverIp,
                        forceTcp443 = false
                    )
                }

                "tor" -> TorEngine(
                    service = this,
                    onProgress = { stage ->
                        emitProgress(session = mySession, mode = "tor", stageText = stage, countryCode = country)
                    },
                    onConnected = { cCode, ip ->
                        if (mySession == sessionCounter.get()) {
                            onEngineTunnelUp(session = mySession, mode = "tor", country = cCode, ip = ip)
                        } else {
                            activeEngine?.stop()
                        }
                    },
                    onError = { msg ->
                        if (mySession == sessionCounter.get()) {
                            onEngineFailed(session = mySession, mode = "tor", message = msg)
                        }
                    }
                ).also {
                    activeEngine = it
                    it.start(
                        exitCountry = country,
                        disallowedApps = disallowed,
                        stealthMode = false
                    )
                }

                "stealth" -> StealthEngine(
                    service = this,
                    onProgress = { stage ->
                        emitProgress(session = mySession, mode = "stealth", stageText = stage, countryCode = country)
                    },
                    onConnected = { cCode, ip ->
                        if (mySession == sessionCounter.get()) {
                            onEngineTunnelUp(session = mySession, mode = "stealth", country = cCode, ip = ip)
                        } else {
                            activeEngine?.stop()
                        }
                    },
                    onError = { msg ->
                        if (mySession == sessionCounter.get()) {
                            onEngineFailed(session = mySession, mode = "stealth", message = msg)
                        }
                    }
                ).also {
                    activeEngine = it
                    it.start(
                        exitCountry = country,
                        fallbackOpenVpnConfigBase64 = config,
                        fallbackServerIp = serverIp,
                        disallowedApps = disallowed
                    )
                }

                "warp" -> WarpEngine(
                    service = this,
                    onProgress = { stage ->
                        emitProgress(session = mySession, mode = "warp", stageText = stage, countryCode = country)
                    },
                    onConnected = { cCode, ip ->
                        if (mySession == sessionCounter.get()) {
                            onEngineTunnelUp(session = mySession, mode = "warp", country = cCode, ip = ip)
                        } else {
                            activeEngine?.stop()
                        }
                    },
                    onError = { msg ->
                        if (mySession == sessionCounter.get()) {
                            onEngineFailed(session = mySession, mode = "warp", message = msg)
                        }
                    }
                ).also {
                    activeEngine = it
                    it.start(
                        disallowedApps = disallowed,
                        countryCode = country
                    )
                }

                else -> {
                    onEngineFailed(session = mySession, mode = mode, message = "Unknown VPN mode: $mode")
                    return@submit
                }
            }

            if (mySession != sessionCounter.get() || Thread.currentThread().isInterrupted) {
                try {
                    engine.stop()
                } catch (_: Exception) {}
                if (activeEngine === engine) activeEngine = null
            } else {
                reconnectManager?.start()
            }
        }
    }

    fun enqueueDisconnect() {
        val disconnectSession = sessionCounter.incrementAndGet()
        currentTask?.cancel(true)
        val eng = activeEngine
        activeEngine = null

        worker.execute {
            synchronized(engineChangeLock) {
                try {
                    eng?.stop()
                } catch (_: Exception) {}
                stopActiveEngineInternal()
                reconnectManager?.stop()
            }
            if (disconnectSession == sessionCounter.get()) {
                emitState(state = "idle", mode = currentMode, countryCode = lastCountry, ip = null)
                mainHandler.post {
                    if (disconnectSession == sessionCounter.get()) {
                        NotificationHelper.stop(this)
                        stopSelf()
                    }
                }
            }
        }
    }

    fun enqueueUpdateSplit(disallowed: List<String>) {
        lastDisallowed = disallowed
        if (activeEngine != null && lastEvent["state"] == "connected") {
            enqueueConnect(
                mode = currentMode,
                config = lastConfig,
                country = lastCountry,
                serverIp = lastServerIp,
                disallowed = disallowed,
                preferUdp = lastPreferUdp
            )
        }
    }

    private fun onEngineTunnelUp(session: Int, mode: String, country: String, ip: String) {
        if (session != sessionCounter.get()) {
            activeEngine?.stop()
            return
        }
        NotificationHelper.startForeground(this, "Connected (${mode.uppercase()})")
        emitState(
            state = "connected",
            mode = mode,
            countryCode = country,
            ip = ip
        )
        statsMonitor?.stop()
        statsMonitor = TrafficStatsMonitor().also { monitor ->
            monitor.start { rx, tx ->
                if (session == sessionCounter.get()) {
                    emitTraffic(rx, tx)
                }
            }
        }
    }

    private fun onEngineFailed(session: Int, mode: String, message: String) {
        if (session != sessionCounter.get()) return
        val eng = activeEngine
        activeEngine = null
        worker.execute {
            synchronized(engineChangeLock) {
                try {
                    eng?.stop()
                } catch (_: Exception) {}
                stopActiveEngineInternal()
                reconnectManager?.stop()
            }
            if (session == sessionCounter.get()) {
                emitState(
                    state = "error",
                    mode = mode,
                    countryCode = lastCountry,
                    ip = null,
                    errorMessage = message
                )
                mainHandler.post {
                    if (session == sessionCounter.get()) {
                        NotificationHelper.stop(this)
                        stopSelf()
                    }
                }
            }
        }
    }

    private fun stopActiveEngineInternal() {
        statsMonitor?.stop()
        statsMonitor = null
        val eng = activeEngine
        activeEngine = null
        try {
            eng?.stop()
        } catch (_: Exception) {}
    }

    override fun onRevoke() {
        enqueueDisconnect()
        super.onRevoke()
    }

    override fun onDestroy() {
        sessionCounter.incrementAndGet()
        currentTask?.cancel(true)
        val eng = activeEngine
        activeEngine = null
        if (eng != null) {
            worker.execute {
                try {
                    eng.stop()
                } catch (_: Exception) {}
            }
        }
        statsMonitor?.stop()
        reconnectManager?.stop()
        if (instance === this) {
            instance = null
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)
}

