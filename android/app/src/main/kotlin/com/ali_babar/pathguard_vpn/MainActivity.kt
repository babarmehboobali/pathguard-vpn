package com.ali_babar.pathguard_vpn

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.ali_babar.pathguard_vpn.vpn.VpnPlugin
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Thread.setDefaultUncaughtExceptionHandler { _, e ->
            try {
                val file = File(filesDir, "native_crash.txt")
                val sw = StringWriter()
                e.printStackTrace(PrintWriter(sw))
                file.appendText("${System.currentTimeMillis()}\n$sw\n\n")
            } catch (_: Exception) {}
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(VpnPlugin())
    }
}
