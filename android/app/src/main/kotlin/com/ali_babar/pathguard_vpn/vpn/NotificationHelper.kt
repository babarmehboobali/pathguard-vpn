package com.ali_babar.pathguard_vpn.vpn

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat

object NotificationHelper {
    private const val CHANNEL_ID = "pathguard_vpn"
    private const val NOTIFICATION_ID = 1

    fun startForeground(service: PathGuardVpnService, statusText: String = "Secure tunnel active") {
        createChannel(service)
        val disconnectIntent = PendingIntent.getService(
            service,
            0,
            Intent(service, PathGuardVpnService::class.java).setAction(PathGuardVpnService.ACTION_DISCONNECT),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val notification = NotificationCompat.Builder(service, CHANNEL_ID)
            .setContentTitle("PathGuard VPN")
            .setContentText(statusText)
            .setSmallIcon(com.ali_babar.pathguard_vpn.R.drawable.ic_notification)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Disconnect", disconnectIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            service.startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            service.startForeground(NOTIFICATION_ID, notification)
        }
    }

    fun stop(service: PathGuardVpnService) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                service.stopForeground(Service.STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                service.stopForeground(true)
            }
        } catch (_: Exception) {}
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "PathGuard VPN",
                NotificationManager.IMPORTANCE_LOW
            )
            context.getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }
}
