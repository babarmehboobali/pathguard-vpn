package com.ali_babar.pathguard_vpn

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import de.blinkt.openvpn.core.GlobalPreferences

class PathGuardApp : Application() {
    override fun onCreate() {
        super.onCreate()
        if (!isMainProcess()) return
        GlobalPreferences.setInstance(true, true, false)
        createNotificationChannels()
    }

    private fun isMainProcess(): Boolean {
        return packageName == currentProcessName()
    }

    private fun currentProcessName(): String {
        return try {
            val am = getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
            val pid = android.os.Process.myPid()
            am.runningAppProcesses?.firstOrNull { it.pid == pid }?.processName ?: packageName
        } catch (_: Exception) {
            packageName
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val vpnChannel = NotificationChannel(
                "openvpn_bg",
                "OpenVPN",
                NotificationManager.IMPORTANCE_LOW
            )
            val statusChannel = NotificationChannel(
                "openvpn_newstat",
                "OpenVPN status",
                NotificationManager.IMPORTANCE_LOW
            )
            manager.createNotificationChannel(vpnChannel)
            manager.createNotificationChannel(statusChannel)
        }
    }
}
