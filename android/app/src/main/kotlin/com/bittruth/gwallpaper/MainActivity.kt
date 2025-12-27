package com.bittruth.gwallpaper

import io.flutter.embedding.android.FlutterActivity

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.bittruth.gwallpaper/auto_wall"

    private var pendingPayload: String? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: android.content.Intent) {
        val action = intent.action
        val data = intent.dataString
        android.util.Log.d("MainActivity", "handleIntent: action=$action data=$data extras=${intent.extras}")
        
        if (intent.hasExtra("payload")) {
            val p = intent.getStringExtra("payload")
            android.util.Log.d("MainActivity", "Found payload: $p")
            pendingPayload = p
        } else {
            android.util.Log.d("MainActivity", "No 'payload' extra found.")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine, "listTile", ListTileNativeAdFactory(context)
        )

        io.flutter.plugin.common.MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startAutoWallpaper" -> {
                        val freqObj = call.argument<Number>("frequency")
                        val frequency = freqObj?.toLong() ?: 60L
                        
                        val urls = call.argument<List<String>>("urls") ?: emptyList()
                        
                        val targetObj = call.argument<Number>("target")
                        val target = targetObj?.toInt() ?: 0
                        
                        val lockObj = call.argument<Number>("lock_tone")
                        val lockTone = lockObj?.toInt() ?: 0
                        
                        AutoWallpaperScheduler.start(context, frequency, urls, target, lockTone)
                        result.success(true)
                    }
                    "stopAutoWallpaper" -> {
                        AutoWallpaperScheduler.stop(context)
                        result.success(true)
                    }
                    "updatePool" -> {
                        val urls = call.argument<List<String>>("urls") ?: emptyList()
                        AutoWallpaperScheduler.updatePool(context, urls)
                        result.success(true)
                    }
                     "triggerNow" -> {
                          // Use direct execution for immediate feedback
                          AutoWallpaperScheduler.triggerImmediateDirect(context)
                          result.success(true)
                     }
                    "getLastWallpaperChangeTime" -> {
                         val time = AutoWallpaperScheduler.getLastRunTime(context)
                         result.success(time)
                    }
                     "requestBatteryOptimization" -> {
                        // Launch intent to ignore optimizations
                        // Note: Only call this if explicitly requested by user as it can violate Play Policy if automated.
                        // User requirements said "Show... explanation screen... Open ... settings"
                        try {
                           val intent = android.content.Intent()
                           intent.action = android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                           intent.data = android.net.Uri.parse("package:$packageName")
                           startActivity(intent)
                           result.success(true)
                        } catch (e: Exception) {
                           // Fallback to generic settings
                           try {
                               val intent = android.content.Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                               startActivity(intent)
                               result.success(true)
                           } catch (z: Exception) {
                               result.success(false)
                           }
                        }
                    }
                    "testExpiryNotification" -> {
                        // 1. Disable in Prefs (Simulate REAL expiry)
                        val prefs = context.getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE)
                        prefs.edit()
                            .putBoolean("flutter.auto_wallpaper_enabled", false)
                            .remove("flutter.auto_wallpaper_enabled_at_millis")
                            .apply()

                        // 2. Show Notification
                        WallpaperExecutor.showExpiryNotification(context)
                        result.success(true)
                    }
                    "checkLaunchPayload" -> {
                        result.success(pendingPayload)
                        pendingPayload = null // Consume once
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "listTile")
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
