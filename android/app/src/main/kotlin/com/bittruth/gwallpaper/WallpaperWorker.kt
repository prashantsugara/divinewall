package com.bittruth.gwallpaper

import android.app.WallpaperManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.Calendar

class WallpaperWorker(appContext: Context, workerParams: WorkerParameters) :
    CoroutineWorker(appContext, workerParams) {

    companion object {
        // Standard Flutter SharedPreferences name
        const val PREFS_NAME = "FlutterSharedPreferences"
        
        // Keys prefixed with "flutter." as per shared_preferences plugin
        const val KEY_URL_POOL = "flutter.auto_wallpaper_pool_urls"
        const val KEY_SOURCE = "flutter.auto_wallpaper_source"
        const val KEY_DAY_POOLS = "flutter.auto_wallpaper_day_pools_json"
        
        // Native-only keys (not written by Flutter plugin, so no prefix unless we want one)
        // Actually, if we want to share state back to Flutter, we should prefix.
        // But pool_index is likely local to native iteration.
        const val KEY_POOL_INDEX = "auto_wallpaper_pool_index" 
        const val KEY_LAST_RUN = "last_run_millis"
        
        const val KEY_TARGET = "flutter.auto_wallpaper_target"
        const val KEY_LOCK_TONE = "flutter.auto_wallpaper_lock_tone"
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        if (WallpaperExecutor.execute(applicationContext)) {
            Result.success()
        } else {
            Result.retry()
        }
    }
}
