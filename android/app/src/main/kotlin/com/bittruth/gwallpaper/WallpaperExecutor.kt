package com.bittruth.gwallpaper

import android.app.WallpaperManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.util.Log
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.Calendar

object WallpaperExecutor {
    private const val TAG = "WallpaperExecutor"

    // Keys must match those in WallpaperWorker
    const val PREFS_NAME = "FlutterSharedPreferences"
    const val KEY_URL_POOL = "flutter.auto_wallpaper_pool_urls"
    const val KEY_SOURCE = "flutter.auto_wallpaper_source"
    const val KEY_DAY_POOLS = "flutter.auto_wallpaper_day_pools_json"
    const val KEY_POOL_INDEX = "auto_wallpaper_pool_index"
    const val KEY_LAST_RUN = "last_run_millis"
    const val KEY_TARGET = "flutter.auto_wallpaper_target"
    const val KEY_LOCK_TONE = "flutter.auto_wallpaper_lock_tone"

    suspend fun execute(context: Context): Boolean = withContext(Dispatchers.IO) {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

            // 1. Determine Source
            val sourceIndex = getIntSafe(prefs, KEY_SOURCE, 0) // 0=Fav, 1=Cat, 2=Rand, 3=DayWise
            
            val gson = Gson()
            val listType = object : TypeToken<List<String>>() {}.type
            var pool: List<String> = emptyList()

            // 2. Fetch Pool Logic
            try {
                if (sourceIndex == 3) {
                     // Day Wise
                     val jsonDayPools = prefs.getString(KEY_DAY_POOLS, "{}")
                     val mapType = object : TypeToken<Map<String, List<String>>>() {}.type
                     val dayPools: Map<String, List<String>> = gson.fromJson(jsonDayPools, mapType) ?: emptyMap()
                     
                     val calendar = Calendar.getInstance()
                     val dayOfWeek = calendar.get(Calendar.DAY_OF_WEEK) 
                     // Java: Sun=1, Mon=2 ... Sat=7.
                     // App Map: 1=Mon ... 7=Sun.
                     val flutterDay = if (dayOfWeek == 1) 7 else (dayOfWeek - 1)
                     
                     pool = dayPools[flutterDay.toString()] ?: emptyList()
                     Log.d(TAG, "DayWise: FlutterDay=$flutterDay, PoolSize=${pool.size}")
                }
                
                // Fallback to main pool if empty or not daywise
                if (pool.isEmpty()) {
                     val jsonPool = prefs.getString(KEY_URL_POOL, "[]")
                     pool = gson.fromJson(jsonPool, listType) ?: emptyList()
                }
            } catch (e: Exception) {
                Log.e(TAG, "JSON Parsing failed", e)
                pool = emptyList()
            }

            if (pool.isEmpty()) {
                Log.w(TAG, "Pool is empty. Aborting.")
                return@withContext false
            } else {
                Log.d(TAG, "Execution Pool size: ${pool.size}")
            }

            // [NEW] Expiry Check
            val enabledAt = prefs.getLong("flutter.auto_wallpaper_enabled_at_millis", 0)
            val isDebug = prefs.getBoolean("flutter.auto_wallpaper_is_debug", false)
            
            // 7 Days in millis = 7 * 24 * 60 * 60 * 1000 = 604800000
            // Debug: 20 Minutes = 20 * 60 * 1000 = 1200000
            val limit = if (isDebug) 1200000L else 604800000L 
            val elapsed = System.currentTimeMillis() - enabledAt

            if (enabledAt > 0 && elapsed > limit) {
                Log.i(TAG, "Auto Wallpaper Expired! (Debug=$isDebug, Elapsed=${elapsed}ms > Limit=${limit}ms)")
                
                // 1. Disable in Prefs
                prefs.edit()
                    .putBoolean("flutter.auto_wallpaper_enabled", false)
                    .remove("flutter.auto_wallpaper_enabled_at_millis")
                    .apply()
                
                // 2. Cancel Work
                androidx.work.WorkManager.getInstance(context).cancelUniqueWork("auto_wallpaper_work")
                
                // 3. Show Notification
                showExpiryNotification(context)
                
                return@withContext true // Return true to mark work as "completed" (stopped)
            }

            // 3. Select Wallpaper logic
            var index = getIntSafe(prefs, KEY_POOL_INDEX, 0)
            if (index >= pool.size) index = 0

            val imageUrl = pool[index]
            Log.d(TAG, "Selected URL: $imageUrl at index: $index")
            
            // 4. Download
            // Download as bytes first to allow multiple usage (if setting both separately) and avoid OOM
            val imageBytes = downloadBytes(imageUrl)
            if (imageBytes == null) {
                return@withContext false
            }

            // 5. Set Wallpaper
            val wallpaperManager = WallpaperManager.getInstance(context)
            val targetIndex = getIntSafe(prefs, KEY_TARGET, 0) // 0=Home, 1=Lock, 2=Both
            val lockToneIndex = getIntSafe(prefs, KEY_LOCK_TONE, 0) // 0=Normal, 1=BW
            
            Log.d(TAG, "Setting wallpaper via Stream. Target=$targetIndex, Tone=$lockToneIndex")
            
            // Note: Efficient setStream logic
            // setStream(stream, visibleRect, allowBackup, which) is available API 24+
            // Below that, setStream(stream) sets system (and usually lock if not separate).
            
            try {
                if (targetIndex == 2 && lockToneIndex == 1) {
                    // Both, Lock is BW.
                    // Home (Normal) -> Stream
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
                        wallpaperManager.setStream(java.io.ByteArrayInputStream(imageBytes), null, true, WallpaperManager.FLAG_SYSTEM)
                    } else {
                         wallpaperManager.setStream(java.io.ByteArrayInputStream(imageBytes))
                    }
                    
                    // Lock (BW) -> Bitmap (Grayscale requires processing)
                    val original = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                    val bwBitmap = applyGrayscale(original)
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
                        wallpaperManager.setBitmap(bwBitmap, null, true, WallpaperManager.FLAG_LOCK)
                    }
                } else {
                    // Single target or Both with same tone
                    if (lockToneIndex == 1) {
                        // Needs grayscale, must use Bitmap
                        val original = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                        val bwBitmap = applyGrayscale(original)
                        val flags = getFlags(targetIndex)
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
                             wallpaperManager.setBitmap(bwBitmap, null, true, flags)
                        } else {
                             wallpaperManager.setBitmap(bwBitmap)
                        }
                    } else {
                         // Normal Color -> Use Stream (Fast & Efficient)
                         val stream = java.io.ByteArrayInputStream(imageBytes)
                         if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
                             val flags = getFlags(targetIndex)
                             wallpaperManager.setStream(stream, null, true, flags)
                         } else {
                             wallpaperManager.setStream(stream)
                         }
                    }
                }
            } catch (e: Exception) {
                 Log.e(TAG, "Stream/Bitmap set failed", e)
                 // Last resource fallback: simple bitmap
                 val bmp = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                 wallpaperManager.setBitmap(bmp)
            }

            // 6. Update Index
            val nextIndex = (index + 1) % pool.size
            prefs.edit()
                .putInt(KEY_POOL_INDEX, nextIndex)
                .putLong(KEY_LAST_RUN, System.currentTimeMillis())
                .apply()
            
            // REMOVED USER FACING TOAST FOR BACKGROUND SUCCESS
            // android.os.Handler(android.os.Looper.getMainLooper()).post {
            //    android.widget.Toast.makeText(context, "Wallpaper Updated!", android.widget.Toast.LENGTH_SHORT).show()
            // }
            return@withContext true
        } catch (e: Exception) {
            // REMOVED USER FACING TOAST FOR BACKGROUND ERROR
            Log.e(TAG, "Execution failed", e)
            e.printStackTrace()
            return@withContext false
        }
    }
    
    // Helper for flags
    private fun getFlags(targetIndex: Int): Int {
        return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.N) {
            when (targetIndex) {
                1 -> WallpaperManager.FLAG_LOCK
                2 -> WallpaperManager.FLAG_SYSTEM or WallpaperManager.FLAG_LOCK
                else -> WallpaperManager.FLAG_SYSTEM
            }
        } else {
            1 // FLAG_SYSTEM default pre-N
        }
    }
    
    private fun applyGrayscale(original: Bitmap): Bitmap {
        val width = original.width
        val height = original.height
        val grayBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(grayBitmap)
        val paint = Paint()
        val colorMatrix = ColorMatrix()
        colorMatrix.setSaturation(0f)
        val filter = ColorMatrixColorFilter(colorMatrix)
        paint.colorFilter = filter
        canvas.drawBitmap(original, 0f, 0f, paint)
        return grayBitmap
    }

    private fun getIntSafe(prefs: android.content.SharedPreferences, key: String, defValue: Int): Int {
        return try {
            prefs.getInt(key, defValue)
        } catch (e: ClassCastException) {
            try {
                prefs.getLong(key, defValue.toLong()).toInt()
            } catch (e2: Exception) {
                defValue
            }
        }
    }

    private fun downloadBytes(urlFunc: String): ByteArray? {
        return try {
            Log.d(TAG, "Downloading: $urlFunc")
            val url = URL(urlFunc)
            val connection = url.openConnection() as HttpURLConnection
            connection.connectTimeout = 30000
            connection.readTimeout = 30000
            connection.doInput = true
            // Important: User Agent to prevent 403 Forbidden on some servers
            connection.setRequestProperty("User-Agent", "Mozilla/5.0 (Android) DivineWall/1.0")
            connection.connect()
            
            if (connection.responseCode !in 200..299) {
                 Log.e(TAG, "HTTP Error: ${connection.responseCode}")
                 return null
            }

            val input: InputStream = connection.inputStream
            val bytes = input.readBytes()
            input.close()
            Log.d(TAG, "Downloaded ${bytes.size} bytes")
            bytes
        } catch (e: Exception) {
            Log.e(TAG, "Download failed for $urlFunc", e)
            e.printStackTrace()
            null
        }
    }

    fun showExpiryNotification(context: Context) {
        val channelId = "auto_wallpaper_channel" // Matches NotificationService.dart
        val notificationId = 880071 // Matches NotificationService._expiryReminderId
        
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                channelId,
                "Auto Wallpaper",
                android.app.NotificationManager.IMPORTANCE_HIGH
            )
            channel.description = "Notifications for auto wallpaper updates"
            notificationManager.createNotificationChannel(channel)
        }
        
        // Open App Intent with Explicit Class and Flags
        val intent = android.content.Intent(context, MainActivity::class.java)
        intent.flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK or android.content.Intent.FLAG_ACTIVITY_CLEAR_TOP or android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP
        intent.action = android.content.Intent.ACTION_MAIN
        intent.addCategory(android.content.Intent.CATEGORY_LAUNCHER)
        intent.putExtra("payload", "auto_wallpaper_expired")
        
        Log.d(TAG, "Creating PendingIntent with payload: auto_wallpaper_expired")

        val pendingIntent = android.app.PendingIntent.getActivity(
            context,
            0,
            intent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )

        val builder = androidx.core.app.NotificationCompat.Builder(context, channelId)
            .setSmallIcon(context.resources.getIdentifier("ic_notification", "drawable", context.packageName).takeIf { it != 0 } 
                ?: android.R.drawable.ic_dialog_info) // Fallback icon
            .setContentTitle("Auto wallpaper disabled")
            .setContentText("It’s been 7 days! Tap to turn auto wallpapers back on.")
            .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            
        // Use 'ic_launcher' if 'ic_notification' missing?
        // Usually @mipmap/ic_launcher for small icon is bad (square), but acceptable fallback.

        notificationManager.notify(notificationId, builder.build())
    }
}
