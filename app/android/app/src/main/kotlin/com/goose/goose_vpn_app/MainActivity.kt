package com.goose.goose_vpn_app

import android.content.Intent
import android.net.VpnService
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.goose.vpn/control"
    private val VPN_REQUEST_CODE = 1

    private var pendingVpnConfig: String? = null
    private var pendingVpnMode: String? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startVpn" -> {
                    val configJson = call.argument<String>("config")
                    val mode = call.argument<String>("mode") ?: "VPN"
                    if (configJson != null) {
                        pendingVpnConfig = configJson
                        pendingVpnMode = mode
                        if (mode == "Proxy") {
                            startVpnServiceDirectly()
                            result.success("Starting Proxy Mode")
                        } else {
                            prepareVpn()
                            result.success("Preparing VPN")
                        }
                    } else {
                        result.error("INVALID_ARGS", "Config missing", null)
                    }
                }
                "stopVpn" -> {
                    val intent = Intent(this, GooseVpnService::class.java).apply {
                        action = GooseVpnService.ACTION_DISCONNECT
                    }
                    startService(intent)
                    result.success("VPN Stopped")
                }
                "getStats" -> {
                    val statsJson = android.Android.getStatsJSON()
                    result.success(statsJson)
                }
                "triggerPing" -> {
                    android.Android.triggerPing()
                    result.success("OK")
                }
                "openTelegramProxy" -> {
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        data = android.net.Uri.parse("tg://socks?server=127.0.0.1&port=1080")
                    }
                    try {
                        startActivity(intent)
                        result.success("OK")
                    } catch (e: Exception) {
                        result.error("TELEGRAM_NOT_FOUND", "Telegram is not installed", null)
                    }
                }
                "openTelegramChannel" -> {
                    val username = call.argument<String>("username")
                    if (username != null) {
                        val tgIntent = Intent(Intent.ACTION_VIEW).apply {
                            data = android.net.Uri.parse("tg://resolve?domain=$username")
                        }
                        val webIntent = Intent(Intent.ACTION_VIEW).apply {
                            data = android.net.Uri.parse("https://t.me/$username")
                        }
                        try {
                            startActivity(tgIntent)
                            result.success("OK")
                        } catch (e: Exception) {
                            try {
                                startActivity(webIntent)
                                result.success("OK")
                            } catch (ex: Exception) {
                                result.error("NO_BROWSER", "No browser found to open link", null)
                            }
                        }
                    } else {
                        result.error("INVALID_ARGS", "Username missing", null)
                    }
                }
                "getInstalledApps" -> {
                    Thread {
                        try {
                            val pm = packageManager
                            val apps = pm.getInstalledApplications(android.content.pm.PackageManager.GET_META_DATA)
                            val appList = ArrayList<Map<String, String>>()
                            for (app in apps) {
                                // Filter out system apps if desired, but here we just return all
                                // if ((app.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) == 0) { ... }
                                val map = HashMap<String, String>()
                                map["packageName"] = app.packageName
                                map["appName"] = pm.getApplicationLabel(app).toString()
                                appList.add(map)
                            }
                            // Sort alphabetically by app name
                            appList.sortBy { it["appName"]?.lowercase() }
                            
                            // Return on UI thread
                            runOnUiThread {
                                result.success(appList)
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("ERROR", e.message, null)
                            }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun prepareVpn() {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            startActivityForResult(intent, VPN_REQUEST_CODE)
        } else {
            onActivityResult(VPN_REQUEST_CODE, RESULT_OK, null)
        }
    }

    private fun startVpnServiceDirectly() {
        val intent = Intent(this, GooseVpnService::class.java).apply {
            action = GooseVpnService.ACTION_CONNECT
            putExtra("config", pendingVpnConfig)
            putExtra("mode", pendingVpnMode ?: "Proxy")
        }
        startService(intent)
        pendingVpnConfig = null
        pendingVpnMode = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE && resultCode == RESULT_OK) {
            val intent = Intent(this, GooseVpnService::class.java).apply {
                action = GooseVpnService.ACTION_CONNECT
                putExtra("config", pendingVpnConfig)
                putExtra("mode", pendingVpnMode ?: "VPN")
            }
            startService(intent)
            pendingVpnConfig = null
            pendingVpnMode = null
        }
    }
}
