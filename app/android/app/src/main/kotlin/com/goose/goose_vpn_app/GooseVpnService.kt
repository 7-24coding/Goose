package com.goose.goose_vpn_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log

class GooseVpnService : VpnService() {
    private var vpnInterface: ParcelFileDescriptor? = null
    private val CHANNEL_ID = "GooseVpnChannel"
    private val NOTIFICATION_ID = 1001

    companion object {
        const val ACTION_CONNECT = "com.goose.vpn.CONNECT"
        const val ACTION_DISCONNECT = "com.goose.vpn.DISCONNECT"
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val config = intent?.getStringExtra("config") ?: ""
        val mode = intent?.getStringExtra("mode") ?: "VPN"
        when (intent?.action) {
            ACTION_CONNECT -> connectVpn(config, mode)
            ACTION_DISCONNECT -> disconnectVpn()
        }
        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Goose"
            val descriptionText = "Goose Connection Status"
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun connectVpn(configJson: String, mode: String) {
        if (vpnInterface != null) return

        try {
            val isVpnMode = mode == "VPN"

            if (isVpnMode) {
                val builder = Builder()
                    .addAddress("10.0.0.2", 24)
                    .addRoute("0.0.0.0", 0)
                    .addDnsServer("8.8.8.8")
                    .addDnsServer("1.1.1.1")
                    .setSession("GooseRelay")
                    .setMtu(1500)
                    .addDisallowedApplication(packageName)

                var excludedApps: List<String> = listOf(
                    "com.farsitel.bazaar",
                    "ir.mservices.myket",
                    "cab.snapp.passenger",
                    "ir.snapp.passenger",
                    "ir.snapp.food",
                    "ir.divar",
                    "ir.tapsi.passenger",
                    "ir.resana.rubika",
                    "ir.rubika",
                    "ir.eitaa.messenger",
                    "ir.sproject.bale",
                    "mobi.smartcup.splus",
                    "ir.medu.shad",
                    "com.aparat.filimo",
                    "ir.namava.android",
                    "com.aparat",
                    "org.neshan.maps",
                    "ir.maps.balad",
                    "ir.mtn.myirancell",
                    "ir.mci.myhamrah",
                    "com.digikala.tarh",
                    "com.torob.android"
                )
                
                try {
                    val jsonObject = org.json.JSONObject(configJson)
                    if (jsonObject.has("excluded_apps")) {
                        val jsonArray = jsonObject.getJSONArray("excluded_apps")
                        val dynamicList = mutableListOf<String>()
                        for (i in 0 until jsonArray.length()) {
                            dynamicList.add(jsonArray.getString(i))
                        }
                        excludedApps = dynamicList
                    }
                } catch (e: Exception) {
                    Log.e("GooseVpnService", "Failed to parse excluded_apps from config", e)
                }

                for (app in excludedApps) {
                    try {
                        builder.addDisallowedApplication(app)
                    } catch (e: Exception) {
                        // Package not installed, ignore
                    }
                }

                vpnInterface = builder.establish()
            }

            // Setup notification and run service in foreground to show key icon in status bar
            createNotificationChannel()
            val notification: Notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL_ID)
            } else {
                Notification.Builder(this)
            }
                .setContentTitle(if (isVpnMode) "Goose VPN" else "Goose Proxy")
                .setContentText(if (isVpnMode) "Connected and securing your traffic" else "Proxy running locally")
                .setSmallIcon(applicationInfo.icon)
                .build()

            if (Build.VERSION.SDK_INT >= 34) { // Build.VERSION_CODES.UPSIDE_DOWN_CAKE
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            
            // Start the Go VPN Engine
            android.Android.startVPN(configJson, cacheDir.absolutePath)
            
            if (isVpnMode && vpnInterface != null) {
                // Start the Go tun2socks bridge
                // Duplicate and detach fd to prevent fdsan crash when Go side closes it
                val dupFd = vpnInterface!!.dup().detachFd()
                android.Android.startTun2Socks(dupFd.toLong(), "127.0.0.1:1080")
            }
            
            Log.i("GooseVpnService", "VPN connected successfully in mode: $mode")
        } catch (e: Exception) {
            Log.e("GooseVpnService", "Failed to start VPN in mode: $mode", e)
        }
    }

    private fun disconnectVpn() {
        try {
            android.Android.stopTun2Socks()
            android.Android.stopVPN()
            
            vpnInterface?.close()
            vpnInterface = null
            Log.i("GooseVpnService", "VPN disconnected")
        } catch (e: Exception) {
            Log.e("GooseVpnService", "Failed to close VPN", e)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            stopForeground(true)
        }

        stopSelf()
    }

    override fun onDestroy() {
        disconnectVpn()
        super.onDestroy()
    }
}
