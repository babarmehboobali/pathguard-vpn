package com.ali_babar.pathguard_vpn.vpn

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.*
import java.io.File

class VpnPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var applicationContext: Context? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingResult: MethodChannel.Result? = null
    private val ioScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private fun log(msg: String) {
        try {
            val dir = applicationContext?.filesDir ?: activity?.filesDir ?: return
            val file = File(dir, "crash_log.txt")
            file.appendText("${System.currentTimeMillis()}$msg\n")
        } catch (_: Exception) {}
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, "pathguard/vpn")
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "pathguard/vpn/events")
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        log("onMethodCall ${call.method}")
        when (call.method) {
            "prepare" -> {
                val act = activity
                val ctx = act ?: applicationContext
                if (ctx == null) {
                    result.error("NO_CONTEXT", "Context unavailable", null)
                    return
                }
                val intent = VpnService.prepare(ctx)
                if (intent != null) {
                    if (act == null) {
                        result.error("NO_ACTIVITY", "Activity required to request VPN permission", null)
                        return
                    }
                    pendingResult = result
                    act.startActivityForResult(intent, 1001)
                } else {
                    result.success(true)
                }
            }
            "connect" -> {
                val ctx = applicationContext ?: activity
                if (ctx == null) {
                    result.error("NO_CONTEXT", "Context unavailable", null)
                    return
                }
                val mode = call.argument<String>("mode") ?: "free"
                val config = call.argument<String>("config")
                val country = call.argument<String>("countryCode")
                val serverIp = call.argument<String>("serverIp")
                val disallowed = call.argument<List<String>>("disallowedApps")
                val preferUdp = call.argument<Boolean>("preferUdp") ?: true
                try {
                    PathGuardVpnService.start(
                        context = ctx,
                        mode = mode,
                        config = config,
                        country = country,
                        serverIp = serverIp,
                        disallowed = disallowed,
                        preferUdp = preferUdp
                    )
                    result.success(null)
                } catch (e: Exception) {
                    log("connect failed: ${e.message}")
                    result.error("CONNECT_FAILED", e.message, null)
                }
            }
            "disconnect" -> {
                val ctx = applicationContext ?: activity
                if (ctx != null) {
                    PathGuardVpnService.stop(ctx)
                }
                result.success(null)
            }
            "setSplitTunnel" -> {
                val disallowed = call.argument<List<String>>("disallowed") ?: emptyList<String>()
                PathGuardVpnService.updateSplit(disallowed)
                result.success(null)
            }
            "listInstalledApps" -> {
                val pm = (applicationContext ?: activity)?.packageManager
                if (pm == null) {
                    result.success(emptyList<Map<String,String>>())
                    return
                }
                ioScope.launch {
                    val apps = mutableListOf<Map<String,String>>()
                    val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                    val resolved = pm.queryIntentActivities(intent, PackageManager.MATCH_ALL)
                    for (info in resolved) {
                        val label = info.loadLabel(pm).toString()
                        val pkg = info.activityInfo.packageName
                        apps.add(mapOf("label" to label, "package" to pkg))
                    }
                    withContext(Dispatchers.Main) {
                        result.success(apps)
                    }
                }
            }
            "openVpnSettings" -> {
                // Kill switch: Android's own "Always-on VPN" + "Block connections without VPN"
                val ctx = activity ?: applicationContext
                if (ctx == null) {
                    result.success(false)
                    return
                }
                try {
                    val intent = Intent(android.provider.Settings.ACTION_VPN_SETTINGS)
                    if (ctx !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    ctx.startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    log("openVpnSettings failed: ${e.message}")
                    result.success(false)
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == 1001) {
            val granted = resultCode == Activity.RESULT_OK
            pendingResult?.success(granted)
            pendingResult = null
            return true
        }
        return false
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        PathGuardVpnService.setEventSink(events)
    }

    override fun onCancel(arguments: Any?) {
        PathGuardVpnService.setEventSink(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ioScope.cancel()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        applicationContext = null
    }
}

