package com.ali_babar.pathguard_vpn.tile

import android.content.Intent
import android.net.VpnService
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.ali_babar.pathguard_vpn.MainActivity
import com.ali_babar.pathguard_vpn.vpn.PathGuardVpnService

class VpnTileService : TileService() {
    override fun onClick() {
        val tile = qsTile
        if (tile.state == Tile.STATE_ACTIVE) {
            PathGuardVpnService.stop(this)
            tile.state = Tile.STATE_INACTIVE
        } else {
            val prepare = VpnService.prepare(this)
            if (prepare != null) {
                // Open the main activity so the user can grant permission / consent
                val intent = Intent(this, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivityAndCollapse(intent)
                return
            }
            PathGuardVpnService.start(this, "free", null, null, null, null, true)
            tile.state = Tile.STATE_ACTIVE
        }
        tile.updateTile()
    }

    override fun onStartListening() {
        super.onStartListening()
        // Tile state can be synced from a static flag in PathGuardVpnService if desired
    }
}
